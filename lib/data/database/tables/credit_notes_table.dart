import 'package:drift/drift.dart';

/// Credit notes for returns or discounts
class CreditNotes extends Table {
  TextColumn get id => text()();
  TextColumn get noteNumber => text()();
  TextColumn get saleId => text().nullable()(); // original sale
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text().nullable()();
  TextColumn get reason => text()(); // return, discount, error, damaged
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, applied, cancelled
  TextColumn get createdBy => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Credit note line items
class CreditNoteItems extends Table {
  TextColumn get id => text()();
  TextColumn get creditNoteId => text().references(CreditNotes, #id)();
  TextColumn get productId => text()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get total => real()();
  BoolColumn get returnToStock => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
