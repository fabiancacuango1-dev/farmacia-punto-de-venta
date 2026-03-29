import 'package:drift/drift.dart';

/// Supplier returns / devolutions
class SupplierReturns extends Table {
  TextColumn get id => text()();
  TextColumn get returnNumber => text()();
  TextColumn get supplierId => text()();
  TextColumn get purchaseOrderId => text().nullable()();
  TextColumn get reason => text()(); // expired, damaged, quality, excess
  RealColumn get totalAmount => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, approved, completed, rejected
  TextColumn get createdBy => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get processedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Items in a supplier return
class SupplierReturnItems extends Table {
  TextColumn get id => text()();
  TextColumn get returnId => text().references(SupplierReturns, #id)();
  TextColumn get productId => text()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get total => real()();
  TextColumn get batchNumber => text().nullable()();
  TextColumn get reason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
