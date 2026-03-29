import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/sales_table.dart';
import '../tables/sale_items_table.dart';
import '../tables/products_table.dart';

part 'sales_dao.g.dart';

class SaleWithItems {
  final Sale sale;
  final List<SaleItem> items;
  SaleWithItems({required this.sale, required this.items});
}

@DriftAccessor(tables: [Sales, SaleItems, Products])
class SalesDao extends DatabaseAccessor<AppDatabase> with _$SalesDaoMixin {
  SalesDao(super.db);

  // ── Create Sale (transaction) ──

  Future<void> createSale({
    required SalesCompanion sale,
    required List<SaleItemsCompanion> items,
  }) async {
    await transaction(() async {
      await into(sales).insert(sale);

      for (final item in items) {
        await into(saleItems).insert(item);

        // Update stock
        final product = await (select(products)
              ..where((p) => p.id.equals(item.productId.value)))
            .getSingle();

        final newStock = product.currentStock - item.quantity.value;
        await (update(products)
              ..where((p) => p.id.equals(item.productId.value)))
            .write(ProductsCompanion(
          currentStock: Value(newStock),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value('pending'),
        ));
      }
    });
  }

  // ── Cancel Sale ──

  Future<void> cancelSale(String saleId) async {
    await transaction(() async {
      // Get items to restore stock
      final items = await (select(saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .get();

      for (final item in items) {
        final product = await (select(products)
              ..where((p) => p.id.equals(item.productId)))
            .getSingle();

        await (update(products)
              ..where((p) => p.id.equals(item.productId)))
            .write(ProductsCompanion(
          currentStock: Value(product.currentStock + item.quantity),
          updatedAt: Value(DateTime.now()),
        ));
      }

      await (update(sales)..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(
          status: const Value('cancelled'),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  // ── Queries ──

  Future<List<Sale>> getSalesByDateRange(DateTime start, DateTime end) {
    return (select(sales)
          ..where((s) => s.createdAt.isBetweenValues(start, end))
          ..where((s) => s.status.equals('completed'))
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .get();
  }

  Stream<List<Sale>> watchTodaySales() {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    return (select(sales)
          ..where((s) => s.createdAt.isBetweenValues(start, end))
          ..where((s) => s.status.equals('completed'))
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .watch();
  }

  Future<SaleWithItems?> getSaleWithItems(String saleId) async {
    final sale = await (select(sales)..where((s) => s.id.equals(saleId)))
        .getSingleOrNull();
    if (sale == null) return null;

    final items = await (select(saleItems)
          ..where((i) => i.saleId.equals(saleId)))
        .get();

    return SaleWithItems(sale: sale, items: items);
  }

  Future<List<SaleItem>> getItemsForSale(String saleId) {
    return (select(saleItems)..where((i) => i.saleId.equals(saleId))).get();
  }

  // ── Stats ──

  Future<double> totalSalesToday() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final result = await customSelect(
      'SELECT COALESCE(SUM(total), 0) as total FROM sales WHERE created_at >= ? AND status = ?',
      variables: [Variable.withDateTime(start), const Variable('completed')],
      readsFrom: {sales},
    ).getSingle();
    return (result.data['total'] as num).toDouble();
  }

  Future<int> countSalesToday() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final result = await customSelect(
      'SELECT COUNT(*) as c FROM sales WHERE created_at >= ? AND status = ?',
      variables: [Variable.withDateTime(start), const Variable('completed')],
      readsFrom: {sales},
    ).getSingle();
    return result.data['c'] as int;
  }

  Future<String> generateInvoiceNumber() async {
    final today = DateTime.now();
    final prefix =
        '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';

    final result = await customSelect(
      "SELECT COUNT(*) as c FROM sales WHERE invoice_number LIKE ?",
      variables: [Variable('$prefix%')],
      readsFrom: {sales},
    ).getSingle();

    final count = (result.data['c'] as int) + 1;
    return '$prefix-${count.toString().padLeft(4, '0')}';
  }
}
