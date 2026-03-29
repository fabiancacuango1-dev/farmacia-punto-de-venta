import 'package:drift/drift.dart';

/// Product label templates
class LabelTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get size => text().withDefault(const Constant('medium'))(); // small, medium, large, custom
  RealColumn get width => real().withDefault(const Constant(50.0))(); // mm
  RealColumn get height => real().withDefault(const Constant(30.0))(); // mm
  BoolColumn get showBarcode => boolean().withDefault(const Constant(true))();
  BoolColumn get showPrice => boolean().withDefault(const Constant(true))();
  BoolColumn get showName => boolean().withDefault(const Constant(true))();
  BoolColumn get showExpiry => boolean().withDefault(const Constant(false))();
  BoolColumn get showLab => boolean().withDefault(const Constant(false))();
  IntColumn get fontSize => integer().withDefault(const Constant(12))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
