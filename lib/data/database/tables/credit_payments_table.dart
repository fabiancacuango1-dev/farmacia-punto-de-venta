import 'package:drift/drift.dart';
import 'customers_table.dart';

/// Customer credit payment records
class CreditPayments extends Table {
  TextColumn get id => text()();
  TextColumn get creditId => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  RealColumn get amount => real()();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))();
  TextColumn get reference => text().nullable()();
  TextColumn get receivedBy => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
