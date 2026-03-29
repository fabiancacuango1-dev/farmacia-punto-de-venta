import 'package:drift/drift.dart';
import 'purchase_orders_table.dart';
import 'products_table.dart';

class PurchaseOrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseOrderId => text().references(PurchaseOrders, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get productName => text().withDefault(const Constant(''))(); // Snapshot at time of order
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get total => real()();
  TextColumn get batchNumber => text().nullable()();
  DateTimeColumn get expirationDate => dateTime().nullable()();
  RealColumn get receivedQuantity => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {id};
}
