import 'package:drift/drift.dart';
import 'sales_table.dart';
import 'products_table.dart';
import 'product_batches_table.dart';

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get batchId => text().nullable().references(ProductBatches, #id)();
  TextColumn get productName => text()(); // Snapshot at time of sale
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get costPrice => real()(); // Snapshot for profit calc
  RealColumn get discount => real().withDefault(const Constant(0.0))();
  RealColumn get taxRate => real().withDefault(const Constant(15.0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get subtotal => real()();
  RealColumn get total => real()();

  @override
  Set<Column> get primaryKey => {id};
}
