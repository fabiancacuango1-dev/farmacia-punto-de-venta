import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../core/errors/app_exceptions.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  throw UnimplementedError('AuthService must be initialized in main()');
});

final currentUserProvider = StateProvider<User?>((ref) => null);

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

class AuthService {
  final AppDatabase _db;

  AuthService(this._db);

  /// Hash password using SHA-256 (for local auth without external dependencies)
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Authenticate user with username and password
  Future<User> login(String username, String password) async {
    final user = await _db.usersDao.getUserByUsername(username);

    if (user == null) {
      throw const AuthException('Usuario no encontrado', code: 'USER_NOT_FOUND');
    }

    if (!user.isActive) {
      throw const AuthException('Usuario desactivado', code: 'USER_INACTIVE');
    }

    final hashedPassword = _hashPassword(password);
    if (user.passwordHash != hashedPassword) {
      throw const AuthException('Contraseña incorrecta', code: 'INVALID_PASSWORD');
    }

    // Update last login
    await _db.usersDao.updateLastLogin(user.id);

    // Log the login
    await _db.usersDao.logAction(
      userId: user.id,
      action: 'login',
    );

    return user;
  }

  /// Create a new user
  Future<User> createUser({
    required String id,
    required String username,
    required String password,
    required String fullName,
    required String role,
    String? email,
    String? phone,
  }) async {
    // Validate role
    if (!['admin', 'cashier', 'warehouse'].contains(role)) {
      throw const ValidationException('Rol no válido');
    }

    // Check unique username
    final existing = await _db.usersDao.getUserByUsername(username);
    if (existing != null) {
      throw const ValidationException('El nombre de usuario ya existe');
    }

    final hashedPassword = _hashPassword(password);

    await _db.usersDao.insertUser(UsersCompanion.insert(
      id: id,
      username: username,
      passwordHash: hashedPassword,
      fullName: fullName,
      role: Value(role),
    ));

    final user = await _db.usersDao.getUserById(id);
    return user!;
  }

  /// Change password
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = await _db.usersDao.getUserById(userId);
    if (user == null) {
      throw const AuthException('Usuario no encontrado');
    }

    final currentHash = _hashPassword(currentPassword);
    if (user.passwordHash != currentHash) {
      throw const AuthException('Contraseña actual incorrecta');
    }

    if (newPassword.length < 6) {
      throw const ValidationException('La contraseña debe tener al menos 6 caracteres');
    }

    final newHash = _hashPassword(newPassword);
    await _db.usersDao.updateUser(UsersCompanion(
      id: Value(userId),
      passwordHash: Value(newHash),
      mustChangePassword: const Value(false),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Check if user has a specific permission based on role
  bool hasPermission(User user, String permission) {
    final rolePermissions = _rolePermissions[user.role] ?? [];
    return rolePermissions.contains(permission) || rolePermissions.contains('*');
  }

  static const Map<String, List<String>> _rolePermissions = {
    'admin': ['*'], // All permissions
    'cashier': [
      'pos.sell',
      'pos.view',
      'cash_register.open',
      'cash_register.close',
      'products.view',
      'inventory.view',
      'reports.view_own',
    ],
    'warehouse': [
      'products.view',
      'products.edit',
      'inventory.view',
      'inventory.adjust',
      'purchases.view',
      'purchases.create',
      'purchases.receive',
    ],
  };
}
