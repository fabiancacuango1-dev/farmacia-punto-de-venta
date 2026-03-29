import 'package:drift/drift.dart';
import 'customers_table.dart';

/// Customer credits/loans with payment tracking
class CustomerCredits extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get saleId => text().nullable()();
  RealColumn get amount => real()();
  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();
  RealColumn get balance => real()();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, paid, overdue, cancelled
  DateTimeColumn get dueDate => dateTime()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
