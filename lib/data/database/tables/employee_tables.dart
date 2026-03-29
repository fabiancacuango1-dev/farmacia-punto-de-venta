import 'package:drift/drift.dart';
import 'users_table.dart';

/// Employee attendance tracking
class EmployeeAttendance extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get type => text()(); // check_in, check_out, break_start, break_end
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Employee activity log (beyond audit)
class EmployeeActivities extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get activityType => text()(); // sale, return, adjustment, register_open, register_close
  TextColumn get description => text()();
  TextColumn get reference => text().nullable()();
  RealColumn get amount => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
