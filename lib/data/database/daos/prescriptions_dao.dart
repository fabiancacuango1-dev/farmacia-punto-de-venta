import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/prescriptions_table.dart';

part 'prescriptions_dao.g.dart';

@DriftAccessor(tables: [Prescriptions])
class PrescriptionsDao extends DatabaseAccessor<AppDatabase>
    with _$PrescriptionsDaoMixin {
  PrescriptionsDao(super.db);

  Future<List<Prescription>> getAllPrescriptions({int limit = 100}) {
    return (select(prescriptions)
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
          ..limit(limit))
        .get();
  }

  Stream<List<Prescription>> watchPrescriptions() {
    return (select(prescriptions)
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
          ..limit(100))
        .watch();
  }

  Future<List<Prescription>> searchPrescriptions(String query) {
    final pattern = '%$query%';
    return (select(prescriptions)
          ..where((p) =>
              p.patientName.like(pattern) |
              p.doctorName.like(pattern) |
              p.prescriptionNumber.like(pattern))
          ..limit(30))
        .get();
  }

  Future<List<Prescription>> getPrescriptionsForProduct(String productId) {
    return (select(prescriptions)
          ..where((p) => p.productId.equals(productId))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .get();
  }

  Future<int> insertPrescription(PrescriptionsCompanion prescription) {
    return into(prescriptions).insert(prescription);
  }

  Future<void> markAsDispensed(String prescriptionId) {
    return markDispensed(
      prescriptionId: prescriptionId,
      quantity: 0,
      dispensedBy: 'system',
    );
  }

  Future<void> markDispensed({
    required String prescriptionId,
    required double quantity,
    required String dispensedBy,
  }) {
    return (update(prescriptions)..where((p) => p.id.equals(prescriptionId)))
        .write(PrescriptionsCompanion(
      quantityDispensed: Value(quantity),
      dispensedBy: Value(dispensedBy),
      dispensedAt: Value(DateTime.now()),
    ));
  }

  Future<List<Prescription>> getPendingDispensations() {
    return (select(prescriptions)
          ..where((p) => p.dispensedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.prescriptionDate)]))
        .get();
  }
}
