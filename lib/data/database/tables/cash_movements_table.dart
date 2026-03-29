import 'package:drift/drift.dart';
import 'cash_registers_table.dart';
import 'users_table.dart';

class CashMovements extends Table {
  TextColumn get id => text()();
  TextColumn get cashRegisterId => text().references(CashRegisters, #id)();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get type => text()(); // income, expense, withdrawal, deposit
  RealColumn get amount => real()();
  TextColumn get reason => text()();
  TextColumn get reference => text().nullable()(); // e.g., sale ID
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
