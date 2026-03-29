import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/app_database.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncService(db);
});

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

enum SyncStatus { idle, syncing, success, error, offline }

class SyncService {
  final AppDatabase _db;
  final Dio _dio = Dio();
  final Connectivity _connectivity = Connectivity();
  Timer? _syncTimer;
  String? _remoteApiUrl;
  final String _deviceId = const Uuid().v4();

  SyncService(this._db);

  /// Configure remote API URL (optional)
  void configure({required String apiUrl}) {
    _remoteApiUrl = apiUrl;
    _dio.options.baseUrl = apiUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  /// Start automatic sync timer
  void startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(AppConstants.syncInterval, (_) => sync());
    
    // Also listen for connectivity changes
    _connectivity.onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        sync(); // Sync when connection is restored
      }
    });
  }

  /// Stop auto sync
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Check if we have internet
  Future<bool> get hasInternet async {
    final result = await _connectivity.checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  /// Main sync method
  Future<SyncResult> sync() async {
    if (_remoteApiUrl == null) {
      return SyncResult(
        success: false,
        message: 'API remota no configurada',
        uploaded: 0,
        downloaded: 0,
      );
    }

    if (!await hasInternet) {
      return SyncResult(
        success: false,
        message: 'Sin conexión a internet',
        uploaded: 0,
        downloaded: 0,
      );
    }

    try {
      int uploaded = 0;
      int downloaded = 0;

      // 1. Upload pending changes
      uploaded = await _uploadPendingChanges();

      // 2. Download remote changes
      downloaded = await _downloadRemoteChanges();

      return SyncResult(
        success: true,
        message: 'Sincronización completada',
        uploaded: uploaded,
        downloaded: downloaded,
      );
    } on DioException catch (e) {
      throw SyncException(
        'Error de red: ${e.message}',
        originalError: e,
      );
    }
  }

  /// Upload all pending local changes to remote
  Future<int> _uploadPendingChanges() async {
    final pendingLogs = await (db.select(db.syncLog)
          ..where((s) => s.status.equals('pending'))
          ..orderBy([(s) => OrderingTerm.asc(s.createdAt)])
          ..limit(100))
        .get();

    if (pendingLogs.isEmpty) return 0;

    int synced = 0;
    for (final log in pendingLogs) {
      try {
        await _dio.post('/sync/push', data: {
          'table': log.targetTable,
          'record_id': log.recordId,
          'operation': log.operation,
          'payload': jsonDecode(log.payload),
          'device_id': log.deviceId,
          'created_at': log.createdAt.toIso8601String(),
        });

        // Mark as synced
        await (db.update(db.syncLog)..where((s) => s.id.equals(log.id)))
            .write(SyncLogCompanion(
          status: const Value('synced'),
          syncedAt: Value(DateTime.now()),
        ));
        synced++;
      } catch (e) {
        // Mark retry
        await (db.update(db.syncLog)..where((s) => s.id.equals(log.id)))
            .write(SyncLogCompanion(
          retryCount: Value(log.retryCount + 1),
          errorMessage: Value(e.toString()),
        ));

        if (log.retryCount >= AppConstants.maxSyncRetries) {
          await (db.update(db.syncLog)..where((s) => s.id.equals(log.id)))
              .write(const SyncLogCompanion(status: Value('failed')));
        }
      }
    }

    return synced;
  }

  /// Download changes from remote server
  Future<int> _downloadRemoteChanges() async {
    try {
      final response = await _dio.get('/sync/pull', queryParameters: {
        'device_id': _deviceId,
        'last_sync': DateTime.now()
            .subtract(AppConstants.syncInterval)
            .toIso8601String(),
      });

      final changes = response.data['changes'] as List? ?? [];
      int applied = 0;

      for (final change in changes) {
        await _applyRemoteChange(change as Map<String, dynamic>);
        applied++;
      }

      return applied;
    } catch (e) {
      // Non-critical: remote might not be available
      return 0;
    }
  }

  /// Apply a single remote change using last-write-wins
  Future<void> _applyRemoteChange(Map<String, dynamic> change) async {
    final table = change['table'] as String;
    final operation = change['operation'] as String;
    final payload = change['payload'] as Map<String, dynamic>;
    final remoteUpdatedAt = DateTime.parse(change['updated_at'] as String);

    // Conflict resolution: last-write-wins based on updated_at
    switch (table) {
      case 'products':
        if (operation == 'update') {
          final local = await db.productsDao.getProductById(payload['id'] as String);
          if (local != null && local.updatedAt != null) {
            if (local.updatedAt!.isAfter(remoteUpdatedAt)) {
              return; // Local is newer, skip
            }
          }
        }
      // Apply the remote change to local DB
      // (Implementation depends on table structure)
    }
  }

  /// Log a change for later sync
  Future<void> logChange({
    required String targetTable,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    await db.into(db.syncLog).insert(SyncLogCompanion.insert(
      id: const Uuid().v4(),
      targetTable: targetTable,
      recordId: recordId,
      operation: operation,
      payload: jsonEncode(payload),
      deviceId: _deviceId,
    ));
  }

  AppDatabase get db => _db;

  void dispose() {
    _syncTimer?.cancel();
  }
}

class SyncResult {
  final bool success;
  final String message;
  final int uploaded;
  final int downloaded;

  SyncResult({
    required this.success,
    required this.message,
    required this.uploaded,
    required this.downloaded,
  });
}
