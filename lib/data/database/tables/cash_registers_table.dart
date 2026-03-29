import 'package:drift/drift.dart';
import 'users_table.dart';

class CashRegisters extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  RealColumn get openingAmount => real()();
  RealColumn get closingAmount => real().nullable()();
  RealColumn get expectedAmount => real().nullable()();
  RealColumn get difference => real().nullable()();
  RealColumn get totalSales => real().withDefault(const Constant(0.0))();
  RealColumn get totalCash => real().withDefault(const Constant(0.0))();
  RealColumn get totalCard => real().withDefault(const Constant(0.0))();
  RealColumn get totalTransfer => real().withDefault(const Constant(0.0))();
  IntColumn get salesCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('open'))(); // open, closed
  TextColumn get notes => text().nullable()();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
