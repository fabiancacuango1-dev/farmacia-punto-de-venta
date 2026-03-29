import 'package:drift/drift.dart';
import 'products_table.dart';

/// Prescription records for controlled medications
class Prescriptions extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().nullable()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get doctorName => text()();
  TextColumn get doctorLicense => text().nullable()();
  TextColumn get patientName => text()();
  TextColumn get patientId => text().nullable()();
  TextColumn get diagnosis => text().nullable()();
  TextColumn get prescriptionNumber => text().nullable()();
  RealColumn get quantityPrescribed => real()();
  RealColumn get quantityDispensed => real().withDefault(const Constant(0.0))();
  TextColumn get dispensedBy => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get imagePath => text().nullable()(); // scanned prescription
  DateTimeColumn get prescriptionDate => dateTime()();
  DateTimeColumn get dispensedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
