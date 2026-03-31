import 'package:drift/drift.dart';
import 'categories_table.dart';

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get barcode => text().nullable().unique()();
  TextColumn get internalCode => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get genericName => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get presentation => text().nullable()(); // tableta, jarabe, crema, etc.
  TextColumn get concentration => text().nullable()(); // 500mg, 10ml, etc.
  TextColumn get laboratory => text().nullable()();
  RealColumn get costPrice => real().withDefault(const Constant(0.0))();
  RealColumn get salePrice => real().withDefault(const Constant(0.0))();
  RealColumn get wholesalePrice => real().nullable()();
  RealColumn get price2 => real().nullable()(); // Precio nivel 2 (ej: descuento 20%)
  RealColumn get price3 => real().nullable()(); // Precio nivel 3 (ej: descuento 40%)
  RealColumn get taxRate => real().withDefault(const Constant(15.0))(); // IVA Ecuador 15%
  BoolColumn get isTaxExempt => boolean().withDefault(const Constant(false))();
  IntColumn get unitsPerBox => integer().withDefault(const Constant(1))(); // Unidades por caja/empaque
  RealColumn get costPerBox => real().withDefault(const Constant(0.0))(); // Costo total de la caja
  BoolColumn get allowFractions => boolean().withDefault(const Constant(false))(); // Permite venta fraccionada (por unidad de caja)
  RealColumn get currentStock => real().withDefault(const Constant(0.0))();
  RealColumn get minStock => real().withDefault(const Constant(10.0))();
  RealColumn get maxStock => real().nullable()();
  TextColumn get unit => text().withDefault(const Constant('unidad'))(); // unidad, caja, frasco
  BoolColumn get requiresPrescription => boolean().withDefault(const Constant(false))();
  BoolColumn get isControlled => boolean().withDefault(const Constant(false))();
  TextColumn get adminRoute => text().nullable()(); // Oral, Tópica, Intravenosa, etc.
  TextColumn get saleType => text().withDefault(const Constant('Unidad/Pieza'))();
  TextColumn get storageCondition => text().nullable()();
  TextColumn get storageNotes => text().nullable()();
  TextColumn get registroSanitario => text().nullable()();
  BoolColumn get usesInventory => boolean().withDefault(const Constant(true))();
  TextColumn get location => text().nullable()(); // Ubicación: Estante A, Vitrina 3, etc.
  TextColumn get shelf => text().nullable()(); // Pasillo, anaquel, gaveta
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get imagePath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
