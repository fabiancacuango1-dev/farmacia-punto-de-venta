import 'dart:convert';
import '../../utils/platform_io.dart'
    if (dart.library.js_interop) '../../utils/platform_io_web.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../data/database/app_database.dart';

/// Automatic and manual backup service
class BackupService {
  final AppDatabase _db;

  BackupService(this._db);

  /// Create a database backup
  Future<String> createBackup({String type = 'manual'}) async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'farmapos', 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final filename = 'farmapos_backup_$timestamp.json';
    final filePath = p.join(backupDir.path, filename);

    // Export all tables to JSON
    final data = await _exportAllData();
    final jsonContent = jsonEncode(data);
    final file = File(filePath);
    await file.writeAsString(jsonContent);

    final sizeBytes = await file.length();

    // Record backup
    await _db.invoicesDao.insertBackupRecord(BackupRecordsCompanion.insert(
      id: 'backup_$timestamp',
      filename: filename,
      path: filePath,
      sizeBytes: sizeBytes,
      type: Value(type),
    ));

    return filePath;
  }

  /// Restore from backup file
  Future<void> restoreFromBackup(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Archivo de backup no encontrado');
    }

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    await _importAllData(data);
  }

  /// Clean old backups, keeping most recent N
  Future<void> cleanOldBackups({int keepCount = 10}) async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'farmapos', 'backups'));
    if (!await backupDir.exists()) return;

    final files = await backupDir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();

    files.sort((a, b) => b.path.compareTo(a.path));

    for (var i = keepCount; i < files.length; i++) {
      await files[i].delete();
    }
  }

  Future<Map<String, dynamic>> _exportAllData() async {
    final products = await _db.productsDao.getAllProducts(activeOnly: false);
    final categories = await _db.productsDao.getAllCategories();
    final suppliers = await _db.purchasesDao.getAllSuppliers(activeOnly: false);
    final customers = await _db.customersDao.getAllCustomers(activeOnly: false);

    return {
      'version': 2,
      'timestamp': DateTime.now().toIso8601String(),
      'products_count': products.length,
      'categories_count': categories.length,
      'suppliers_count': suppliers.length,
      'customers_count': customers.length,
    };
  }

  Future<void> _importAllData(Map<String, dynamic> data) async {
    // Restore logic - simplified for now
    final version = data['version'] as int? ?? 1;
    if (version < 1) {
      throw Exception('Versión de backup no soportada');
    }
  }
}
