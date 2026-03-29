import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/employee_tables.dart';
import '../tables/users_table.dart';

part 'employees_dao.g.dart';

@DriftAccessor(tables: [EmployeeAttendance, EmployeeActivities, Users])
class EmployeesDao extends DatabaseAccessor<AppDatabase>
    with _$EmployeesDaoMixin {
  EmployeesDao(super.db);

  // ── Attendance ──

  Future<int> recordAttendance(EmployeeAttendanceCompanion record) {
    return into(employeeAttendance).insert(record);
  }

  Future<List<EmployeeAttendanceData>> getAttendanceForUser(
    String userId, {
    DateTime? from,
    DateTime? to,
  }) {
    final query = select(employeeAttendance)
      ..where((a) => a.userId.equals(userId))
      ..orderBy([(a) => OrderingTerm.desc(a.timestamp)]);
    if (from != null) {
      query.where((a) => a.timestamp.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((a) => a.timestamp.isSmallerOrEqualValue(to));
    }
    return query.get();
  }

  Future<EmployeeAttendanceData?> getLastAttendance(String userId) {
    return (select(employeeAttendance)
          ..where((a) => a.userId.equals(userId))
          ..orderBy([(a) => OrderingTerm.desc(a.timestamp)])
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<List<EmployeeAttendanceData>> watchTodayAttendance() {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return (select(employeeAttendance)
          ..where((a) => a.timestamp.isBiggerOrEqualValue(start))
          ..orderBy([(a) => OrderingTerm.desc(a.timestamp)]))
        .watch();
  }

  // ── Activities ──

  Future<int> logActivity(EmployeeActivitiesCompanion activity) {
    return into(employeeActivities).insert(activity);
  }

  Future<List<EmployeeActivity>> getActivitiesForUser(
    String userId, {
    int limit = 50,
  }) {
    return (select(employeeActivities)
          ..where((a) => a.userId.equals(userId))
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)])
          ..limit(limit))
        .get();
  }

  Stream<List<EmployeeActivity>> watchRecentActivities({int limit = 20}) {
    return (select(employeeActivities)
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)])
          ..limit(limit))
        .watch();
  }

  // ── Employee Reports ──

  Future<Map<String, dynamic>> getEmployeeSummary(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    final salesResult = await customSelect(
      '''
      SELECT COUNT(*) as sales_count, COALESCE(SUM(total), 0) as total_sales
      FROM sales
      WHERE seller_id = ? AND created_at BETWEEN ? AND ? AND status = 'completed'
      ''',
      variables: [
        Variable(userId),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
      readsFrom: {db.sales},
    ).getSingle();

    final attendanceResult = await customSelect(
      '''
      SELECT COUNT(*) as check_ins
      FROM employee_attendance
      WHERE user_id = ? AND timestamp BETWEEN ? AND ? AND type = 'check_in'
      ''',
      variables: [
        Variable(userId),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
      readsFrom: {employeeAttendance},
    ).getSingle();

    return {
      'sales_count': salesResult.data['sales_count'] as int,
      'total_sales': (salesResult.data['total_sales'] as num).toDouble(),
      'check_ins': attendanceResult.data['check_ins'] as int,
    };
  }
}
