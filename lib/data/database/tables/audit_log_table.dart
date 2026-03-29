import 'package:drift/drift.dart';
import 'users_table.dart';

class AuditLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get action => text()(); // login, logout, sale, edit_product, delete_product, etc.
  TextColumn get targetTable => text().nullable()();
  TextColumn get recordId => text().nullable()();
  TextColumn get oldValues => text().nullable()(); // JSON
  TextColumn get newValues => text().nullable()(); // JSON
  TextColumn get ipAddress => text().nullable()();
  TextColumn get deviceInfo => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
