import 'package:drift/drift.dart';
import 'products_table.dart';

/// Stock alert configurations and triggered alerts
class StockAlerts extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get alertType =>
      text()(); // low_stock, overstock, expiring_soon, expired, stagnant, high_demand
  RealColumn get threshold => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  TextColumn get message => text().nullable()();
  TextColumn get severity =>
      text().withDefault(const Constant('warning'))(); // info, warning, critical
  DateTimeColumn get triggeredAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI-generated purchase suggestions
class PurchaseSuggestions extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get supplierId => text().nullable()();
  RealColumn get suggestedQty => real()();
  RealColumn get estimatedCost => real().withDefault(const Constant(0.0))();
  RealColumn get avgDailySales => real().withDefault(const Constant(0.0))();
  RealColumn get daysUntilStockout => real().withDefault(const Constant(0.0))();
  IntColumn get priority =>
      integer().withDefault(const Constant(0))(); // 0=low, 1=medium, 2=high, 3=critical
  TextColumn get reason => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending, approved, ordered, dismissed
  DateTimeColumn get generatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Periodic inventory snapshots for comparison and history
class InventorySnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get snapshotType =>
      text().withDefault(const Constant('daily'))(); // daily, weekly, monthly, manual
  DateTimeColumn get snapshotDate =>
      dateTime().withDefault(currentDateAndTime)();
  IntColumn get totalProducts => integer().withDefault(const Constant(0))();
  RealColumn get totalUnits => real().withDefault(const Constant(0.0))();
  RealColumn get totalCostValue => real().withDefault(const Constant(0.0))();
  RealColumn get totalSaleValue => real().withDefault(const Constant(0.0))();
  IntColumn get lowStockCount => integer().withDefault(const Constant(0))();
  IntColumn get expiringCount => integer().withDefault(const Constant(0))();
  IntColumn get stagnantCount => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Snapshot detail: per-product data at the time of snapshot
class InventorySnapshotItems extends Table {
  TextColumn get id => text()();
  TextColumn get snapshotId => text().references(InventorySnapshots, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get costPrice => real()();
  RealColumn get salePrice => real()();
  RealColumn get costValue => real()(); // quantity * costPrice
  RealColumn get saleValue => real()(); // quantity * salePrice

  @override
  Set<Column> get primaryKey => {id};
}
