import 'package:drift/drift.dart';
import 'users_table.dart';

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceNumber => text().nullable()();
  TextColumn get sriAuthNumber => text().nullable()(); // Autorización SRI
  TextColumn get sriAccessKey => text().nullable()(); // Clave de acceso SRI
  TextColumn get customerName => text().nullable()();
  TextColumn get customerRuc => text().nullable()();
  TextColumn get customerAddress => text().nullable()();
  TextColumn get sellerId => text().references(Users, #id)();
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))(); // cash, card, transfer, mixed
  RealColumn get cashReceived => real().nullable()();
  RealColumn get changeGiven => real().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))(); // completed, cancelled, refunded
  TextColumn get notes => text().nullable()();
  TextColumn get cashRegisterId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  IntColumn get syncVersion => integer().withDefault(const Constant(0))();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
