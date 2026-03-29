import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/quotations_table.dart';

part 'quotations_dao.g.dart';

@DriftAccessor(tables: [Quotations, QuotationItems])
class QuotationsDao extends DatabaseAccessor<AppDatabase>
    with _$QuotationsDaoMixin {
  QuotationsDao(super.db);

  Future<List<Quotation>> getActiveQuotations() {
    return (select(quotations)
          ..where((q) => q.status.equals('active'))
          ..where((q) => q.validUntil.isBiggerOrEqualValue(DateTime.now()))
          ..orderBy([(q) => OrderingTerm.desc(q.createdAt)]))
        .get();
  }

  Stream<List<Quotation>> watchQuotations() {
    return (select(quotations)
          ..orderBy([(q) => OrderingTerm.desc(q.createdAt)])
          ..limit(100))
        .watch();
  }

  Future<void> createQuotation({
    required QuotationsCompanion quote,
    required List<QuotationItemsCompanion> items,
  }) async {
    await transaction(() async {
      await into(quotations).insert(quote);
      for (final item in items) {
        await into(quotationItems).insert(item);
      }
    });
  }

  Future<List<QuotationItem>> getQuotationItems(String quotationId) {
    return (select(quotationItems)
          ..where((i) => i.quotationId.equals(quotationId)))
        .get();
  }

  Future<void> convertToSale(String quotationId, String saleId) {
    return (update(quotations)..where((q) => q.id.equals(quotationId)))
        .write(QuotationsCompanion(
      status: const Value('converted'),
      convertedSaleId: Value(saleId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> cancelQuotation(String quotationId) {
    return (update(quotations)..where((q) => q.id.equals(quotationId)))
        .write(QuotationsCompanion(
      status: const Value('cancelled'),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<String> generateQuoteNumber() async {
    final today = DateTime.now();
    final prefix =
        'COT-${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    final result = await customSelect(
      "SELECT COUNT(*) as c FROM quotations WHERE quote_number LIKE ?",
      variables: [Variable('$prefix%')],
      readsFrom: {quotations},
    ).getSingle();
    final count = (result.data['c'] as int) + 1;
    return '$prefix-${count.toString().padLeft(4, '0')}';
  }
}
