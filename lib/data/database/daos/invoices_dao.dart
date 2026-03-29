import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/extra_tables.dart';
import '../tables/label_templates_table.dart';

part 'invoices_dao.g.dart';

@DriftAccessor(tables: [ElectronicInvoices, SupplierPriceHistory, ProductSuggestions, BackupRecords, LabelTemplates])
class InvoicesDao extends DatabaseAccessor<AppDatabase>
    with _$InvoicesDaoMixin {
  InvoicesDao(super.db);

  // ── Electronic Invoices ──

  Future<List<ElectronicInvoice>> getInvoices({String? status, int limit = 100}) {
    final query = select(electronicInvoices)
      ..orderBy([(i) => OrderingTerm.desc(i.emittedAt)])
      ..limit(limit);
    if (status != null) {
      query.where((i) => i.status.equals(status));
    }
    return query.get();
  }

  Stream<List<ElectronicInvoice>> watchInvoices() {
    return (select(electronicInvoices)
          ..orderBy([(i) => OrderingTerm.desc(i.emittedAt)])
          ..limit(100))
        .watch();
  }

  Future<int> insertInvoice(ElectronicInvoicesCompanion invoice) {
    return into(electronicInvoices).insert(invoice);
  }

  Future<void> updateInvoiceStatus(String invoiceId, String status, {String? authNumber, String? response}) {
    return (update(electronicInvoices)..where((i) => i.id.equals(invoiceId)))
        .write(ElectronicInvoicesCompanion(
      status: Value(status),
      authorizationNumber: Value(authNumber),
      sriResponse: Value(response),
      authorizedAt: status == 'authorized' ? Value(DateTime.now()) : const Value.absent(),
    ));
  }

  // ── Supplier Price History ──

  Future<int> recordPriceChange(SupplierPriceHistoryCompanion record) {
    return into(supplierPriceHistory).insert(record);
  }

  Future<List<SupplierPriceHistoryData>> getPriceHistory(String productId, {String? supplierId}) {
    final query = select(supplierPriceHistory)
      ..where((h) => h.productId.equals(productId))
      ..orderBy([(h) => OrderingTerm.desc(h.recordedAt)]);
    if (supplierId != null) {
      query.where((h) => h.supplierId.equals(supplierId));
    }
    return query.get();
  }

  // ── Product Suggestions ──

  Future<List<ProductSuggestion>> getSuggestions(String productId) {
    return (select(productSuggestions)
          ..where((s) => s.productId.equals(productId))
          ..where((s) => s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm.desc(s.priority)]))
        .get();
  }

  Future<int> insertSuggestion(ProductSuggestionsCompanion suggestion) {
    return into(productSuggestions).insert(suggestion);
  }

  Future<void> removeSuggestion(String id) {
    return (delete(productSuggestions)..where((s) => s.id.equals(id))).go();
  }

  // ── Backups ──

  Future<List<BackupRecord>> getBackupHistory({int limit = 20}) {
    return (select(backupRecords)
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<int> insertBackupRecord(BackupRecordsCompanion record) {
    return into(backupRecords).insert(record);
  }

  // ── Labels ──

  Future<List<LabelTemplate>> getLabelTemplates() {
    return (select(labelTemplates)
          ..orderBy([(l) => OrderingTerm.asc(l.name)]))
        .get();
  }

  Future<LabelTemplate?> getDefaultTemplate() {
    return (select(labelTemplates)
          ..where((l) => l.isDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> insertLabelTemplate(LabelTemplatesCompanion template) {
    return into(labelTemplates).insert(template);
  }

  Future<bool> updateLabelTemplate(LabelTemplatesCompanion template) {
    return (update(labelTemplates)..where((l) => l.id.equals(template.id.value)))
        .write(template)
        .then((rows) => rows > 0);
  }
}
