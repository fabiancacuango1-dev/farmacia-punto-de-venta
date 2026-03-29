import 'package:drift/drift.dart';
import 'products_table.dart';

/// Product combos/packages
class ProductCombos extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  RealColumn get comboPrice => real()();
  RealColumn get regularPrice => real()(); // sum of individual prices for comparison
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get imagePath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Items in a combo
class ComboItems extends Table {
  TextColumn get id => text()();
  TextColumn get comboId => text().references(ProductCombos, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real().withDefault(const Constant(1.0))();

  @override
  Set<Column> get primaryKey => {id};
}
