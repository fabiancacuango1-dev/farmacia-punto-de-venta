import 'package:drift/drift.dart';
import 'suppliers_table.dart';
import 'users_table.dart';

class PurchaseOrders extends Table {
  TextColumn get id => text()();
  TextColumn get orderNumber => text()();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  TextColumn get createdBy => text().references(Users, #id)();
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft, ordered, received, cancelled
  TextColumn get notes => text().nullable()();
  DateTimeColumn get expectedDate => dateTime().nullable()();
  DateTimeColumn get receivedDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
