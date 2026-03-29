import 'package:drift/drift.dart';

/// Multi-branch management
class Branches extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get code => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get managerId => text().nullable()();
  BoolColumn get isMain => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Inter-branch inventory transfers
class BranchTransfers extends Table {
  TextColumn get id => text()();
  TextColumn get transferNumber => text()();
  TextColumn get fromBranchId => text().references(Branches, #id)();
  TextColumn get toBranchId => text()();
  TextColumn get createdBy => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, in_transit, received, cancelled
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get receivedAt => dateTime().nullable()();
  TextColumn get receivedBy => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Transfer line items
class BranchTransferItems extends Table {
  TextColumn get id => text()();
  TextColumn get transferId => text().references(BranchTransfers, #id)();
  TextColumn get productId => text()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get receivedQuantity => real().withDefault(const Constant(0.0))();
  TextColumn get batchNumber => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
