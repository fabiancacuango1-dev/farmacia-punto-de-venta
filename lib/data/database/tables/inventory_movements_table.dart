import 'package:drift/drift.dart';
import 'products_table.dart';
import 'users_table.dart';

class InventoryMovements extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get type => text()(); // sale, purchase, adjustment, return, loss, transfer
  RealColumn get quantity => real()(); // positive = in, negative = out
  RealColumn get previousStock => real()();
  RealColumn get newStock => real()();
  TextColumn get reference => text().nullable()(); // sale_id, purchase_order_id, etc.
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
