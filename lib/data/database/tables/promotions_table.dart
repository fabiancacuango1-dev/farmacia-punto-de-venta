import 'package:drift/drift.dart';

/// Promotions / Discounts engine
class Promotions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  TextColumn get type => text()(); // percentage, fixed, 2x1, combo, buy_x_get_y
  RealColumn get value => real().withDefault(const Constant(0.0))(); // discount amount or %
  IntColumn get buyQuantity => integer().withDefault(const Constant(0))(); // for buy X
  IntColumn get getQuantity => integer().withDefault(const Constant(0))(); // get Y free
  RealColumn get minPurchaseAmount => real().withDefault(const Constant(0.0))();
  TextColumn get applicableProducts => text().nullable()(); // JSON array of product IDs
  TextColumn get applicableCategories => text().nullable()(); // JSON array of category IDs
  BoolColumn get appliesToAll => boolean().withDefault(const Constant(false))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get usageLimit => integer().nullable()(); // max times can be used
  IntColumn get usageCount => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
