import 'package:drift/drift.dart';
import 'users_table.dart';

/// Physical inventory count sessions
class InventoryCounts extends Table {
  TextColumn get id => text()();
  TextColumn get countNumber =>
      text()(); // AUTO-generated: INV-2024-001
  TextColumn get type =>
      text()(); // full, partial (by category/location)
  TextColumn get status =>
      text().withDefault(const Constant('in_progress'))(); // in_progress, completed, cancelled
  TextColumn get startedBy => text().references(Users, #id)();
  @ReferenceName('completedCounts')
  TextColumn get completedBy => text().nullable().references(Users, #id)();
  TextColumn get categoryFilter =>
      text().nullable()(); // null=all, or category id for partial
  TextColumn get notes => text().nullable()();
  IntColumn get totalItems => integer().withDefault(const Constant(0))();
  IntColumn get countedItems => integer().withDefault(const Constant(0))();
  IntColumn get discrepancies => integer().withDefault(const Constant(0))();
  DateTimeColumn get startedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Individual items within a physical inventory count
class InventoryCountItems extends Table {
  TextColumn get id => text()();
  TextColumn get countId => text().references(InventoryCounts, #id)();
  TextColumn get productId => text()();
  TextColumn get batchNumber => text().nullable()();
  RealColumn get expectedQty => real()();
  RealColumn get countedQty => real().nullable()();
  RealColumn get difference => real().nullable()(); // counted - expected
  TextColumn get notes => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending, counted, skipped
  DateTimeColumn get countedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
