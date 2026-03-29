import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/users_table.dart';
import '../tables/audit_log_table.dart';

part 'users_dao.g.dart';

@DriftAccessor(tables: [Users, AuditLog])
class UsersDao extends DatabaseAccessor<AppDatabase> with _$UsersDaoMixin {
  UsersDao(super.db);

  // ── Users CRUD ──

  Future<User?> getUserByUsername(String username) {
    return (select(users)..where((u) => u.username.equals(username)))
        .getSingleOrNull();
  }

  Future<User?> getUserById(String id) {
    return (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();
  }

  Future<List<User>> getAllUsers({bool activeOnly = true}) {
    final query = select(users);
    if (activeOnly) {
      query.where((u) => u.isActive.equals(true));
    }
    query.orderBy([(u) => OrderingTerm.asc(u.fullName)]);
    return query.get();
  }

  Stream<List<User>> watchAllUsers() {
    return (select(users)
          ..where((u) => u.isActive.equals(true))
          ..orderBy([(u) => OrderingTerm.asc(u.fullName)]))
        .watch();
  }

  Future<int> insertUser(UsersCompanion user) {
    return into(users).insert(user);
  }

  Future<bool> updateUser(UsersCompanion user) {
    return (update(users)..where((u) => u.id.equals(user.id.value)))
        .write(user)
        .then((rows) => rows > 0);
  }

  Future<void> updateLastLogin(String userId) {
    return (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(lastLogin: Value(DateTime.now())),
    );
  }

  Future<void> deactivateUser(String userId) {
    return (update(users)..where((u) => u.id.equals(userId))).write(
      const UsersCompanion(isActive: Value(false)),
    );
  }

  // ── Audit Log ──

  Future<void> logAction({
    required String userId,
    required String action,
    String? targetTable,
    String? recordId,
    String? oldValues,
    String? newValues,
  }) {
    return into(auditLog).insert(AuditLogCompanion.insert(
      userId: userId,
      action: action,
      targetTable: Value(targetTable),
      recordId: Value(recordId),
      oldValues: Value(oldValues),
      newValues: Value(newValues),
    ));
  }

  Future<List<AuditLogData>> getAuditLog({
    String? userId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) {
    final query = select(auditLog)
      ..orderBy([(a) => OrderingTerm.desc(a.createdAt)])
      ..limit(limit);

    if (userId != null) {
      query.where((a) => a.userId.equals(userId));
    }
    if (from != null) {
      query.where((a) => a.createdAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((a) => a.createdAt.isSmallerOrEqualValue(to));
    }

    return query.get();
  }
}
