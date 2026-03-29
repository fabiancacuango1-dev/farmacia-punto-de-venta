import 'package:drift/drift.dart';

/// Quotations convertible to sales
class Quotations extends Table {
  TextColumn get id => text()();
  TextColumn get quoteNumber => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text().nullable()();
  TextColumn get sellerId => text()();
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, converted, expired, cancelled
  TextColumn get convertedSaleId => text().nullable()();
  DateTimeColumn get validUntil => dateTime()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Quotation line items
class QuotationItems extends Table {
  TextColumn get id => text()();
  TextColumn get quotationId => text().references(Quotations, #id)();
  TextColumn get productId => text()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0.0))();
  RealColumn get taxRate => real().withDefault(const Constant(15.0))();
  RealColumn get total => real()();

  @override
  Set<Column> get primaryKey => {id};
}
