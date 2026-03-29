import 'package:drift/drift.dart';
import 'customers_table.dart';

/// Loyalty points transactions
class LoyaltyTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get type => text()(); // earn, redeem, adjust, expire
  IntColumn get points => integer()();
  TextColumn get reference => text().nullable()(); // sale ID, etc.
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
