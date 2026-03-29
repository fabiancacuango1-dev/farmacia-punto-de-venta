import 'package:drift/drift.dart';

/// Supplier price history tracking
class SupplierPriceHistory extends Table {
  TextColumn get id => text()();
  TextColumn get supplierId => text()();
  TextColumn get productId => text()();
  RealColumn get price => real()();
  RealColumn get previousPrice => real().nullable()();
  TextColumn get purchaseOrderId => text().nullable()();
  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Product cross-sell / suggestions
class ProductSuggestions extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get suggestedProductId => text()();
  TextColumn get type => text().withDefault(const Constant('complementary'))(); // complementary, alternative, upgrade
  IntColumn get priority => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Backup records
class BackupRecords extends Table {
  TextColumn get id => text()();
  TextColumn get filename => text()();
  TextColumn get path => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get type => text().withDefault(const Constant('auto'))(); // auto, manual
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Electronic invoice (SRI Ecuador)
class ElectronicInvoices extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()();
  TextColumn get invoiceNumber => text()();
  TextColumn get accessKey => text().nullable()(); // 49-digit SRI key
  TextColumn get authorizationNumber => text().nullable()();
  TextColumn get environment => text().withDefault(const Constant('1'))(); // 1=test, 2=prod
  TextColumn get emissionType => text().withDefault(const Constant('1'))(); // 1=normal
  TextColumn get customerRuc => text().nullable()();
  TextColumn get customerName => text().nullable()();
  TextColumn get customerAddress => text().nullable()();
  TextColumn get customerEmail => text().nullable()();
  RealColumn get subtotalNoTax => real().withDefault(const Constant(0.0))();
  RealColumn get subtotalWithTax => real().withDefault(const Constant(0.0))();
  RealColumn get totalDiscount => real().withDefault(const Constant(0.0))();
  RealColumn get iva => real().withDefault(const Constant(0.0))();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  TextColumn get xmlContent => text().nullable()();
  TextColumn get pdfPath => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, signed, sent, authorized, rejected
  TextColumn get sriResponse => text().nullable()();
  DateTimeColumn get emittedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get authorizedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
