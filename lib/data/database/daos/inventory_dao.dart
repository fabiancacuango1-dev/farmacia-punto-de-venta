import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/inventory_movements_table.dart';
import '../tables/products_table.dart';
import '../tables/product_batches_table.dart';
import '../tables/inventory_counts_table.dart';
import '../tables/inventory_intelligence_table.dart';
import '../tables/categories_table.dart';

part 'inventory_dao.g.dart';

/// Data class for product rotation analysis
class ProductRotation {
  final String productId;
  final String productName;
  final double currentStock;
  final double totalSold;
  final double avgDailySales;
  final double daysOfStock;
  final String rotationLevel; // alta, media, baja, estancado

  ProductRotation({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.totalSold,
    required this.avgDailySales,
    required this.daysOfStock,
    required this.rotationLevel,
  });
}

/// Data class for inventory valuation
class InventoryValuation {
  final int totalProducts;
  final double totalUnits;
  final double totalCostValue;
  final double totalSaleValue;
  final double potentialProfit;

  InventoryValuation({
    required this.totalProducts,
    required this.totalUnits,
    required this.totalCostValue,
    required this.totalSaleValue,
    required this.potentialProfit,
  });
}

@DriftAccessor(tables: [
  InventoryMovements,
  Products,
  ProductBatches,
  Categories,
  InventoryCounts,
  InventoryCountItems,
  StockAlerts,
  PurchaseSuggestions,
  InventorySnapshots,
  InventorySnapshotItems,
])
class InventoryDao extends DatabaseAccessor<AppDatabase>
    with _$InventoryDaoMixin {
  InventoryDao(super.db);

  // ══════════════════════════════════════════════════
  // ── STOCK MOVEMENTS ──
  // ══════════════════════════════════════════════════

  /// Records a stock adjustment and updates product stock
  Future<void> recordMovement({
    required String id,
    required String productId,
    required String userId,
    required String type,
    required double quantity,
    String? reference,
    String? reason,
  }) async {
    await transaction(() async {
      final product = await (select(products)
            ..where((p) => p.id.equals(productId)))
          .getSingle();

      final newStock = product.currentStock + quantity;

      await into(inventoryMovements).insert(InventoryMovementsCompanion.insert(
        id: id,
        productId: productId,
        userId: userId,
        type: type,
        quantity: quantity,
        previousStock: product.currentStock,
        newStock: newStock,
        reference: Value(reference),
        reason: Value(reason),
      ));

      await (update(products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          currentStock: Value(newStock),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  Future<List<InventoryMovement>> getMovementsForProduct(
    String productId, {
    int limit = 50,
  }) {
    return (select(inventoryMovements)
          ..where((m) => m.productId.equals(productId))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<List<InventoryMovement>> getMovementsByDateRange(
    DateTime start,
    DateTime end, {
    String? type,
    int? limit,
  }) {
    final query = select(inventoryMovements)
      ..where((m) => m.createdAt.isBetweenValues(start, end))
      ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]);
    if (type != null) {
      query.where((m) => m.type.equals(type));
    }
    if (limit != null) {
      query.limit(limit);
    }
    return query.get();
  }

  Stream<List<InventoryMovement>> watchRecentMovements({int limit = 20}) {
    return (select(inventoryMovements)
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(limit))
        .watch();
  }

  /// Total movements count in a period grouped by type
  Future<Map<String, int>> movementCountsByType(
      DateTime start, DateTime end) async {
    final results = await customSelect(
      '''SELECT type, COUNT(*) as cnt 
         FROM inventory_movements 
         WHERE created_at BETWEEN ? AND ?
         GROUP BY type''',
      variables: [Variable.withDateTime(start), Variable.withDateTime(end)],
      readsFrom: {inventoryMovements},
    ).get();

    final map = <String, int>{};
    for (final row in results) {
      map[row.data['type'] as String] = row.data['cnt'] as int;
    }
    return map;
  }

  // ══════════════════════════════════════════════════
  // ── PHYSICAL INVENTORY COUNTS ──
  // ══════════════════════════════════════════════════

  /// Start a new physical inventory count session
  Future<String> startInventoryCount({
    required String id,
    required String countNumber,
    required String type,
    required String startedBy,
    String? categoryFilter,
    String? notes,
  }) async {
    await into(inventoryCounts).insert(InventoryCountsCompanion.insert(
      id: id,
      countNumber: countNumber,
      type: type,
      startedBy: startedBy,
      categoryFilter: Value(categoryFilter),
      notes: Value(notes),
    ));

    // Pre-populate count items with current stock
    String sql =
        'SELECT id, current_stock FROM products WHERE is_active = 1';
    final vars = <Variable>[];
    if (categoryFilter != null) {
      sql += ' AND category_id = ?';
      vars.add(Variable.withString(categoryFilter));
    }

    final prods = await customSelect(sql,
            variables: vars, readsFrom: {products})
        .get();

    int totalItems = 0;
    for (final p in prods) {
      totalItems++;
      final prodId = p.data['id'] as String;
      final expectedQty = (p.data['current_stock'] as num).toDouble();
      await into(inventoryCountItems)
          .insert(InventoryCountItemsCompanion.insert(
        id: 'ci_${id}_$prodId',
        countId: id,
        productId: prodId,
        expectedQty: expectedQty,
      ));
    }

    await (update(inventoryCounts)..where((c) => c.id.equals(id))).write(
      InventoryCountsCompanion(totalItems: Value(totalItems)),
    );

    return id;
  }

  /// Record a count for an item
  Future<void> recordCountItem({
    required String countItemId,
    required double countedQty,
    String? notes,
  }) async {
    final item = await (select(inventoryCountItems)
          ..where((i) => i.id.equals(countItemId)))
        .getSingle();

    final difference = countedQty - item.expectedQty;

    await (update(inventoryCountItems)
          ..where((i) => i.id.equals(countItemId)))
        .write(InventoryCountItemsCompanion(
      countedQty: Value(countedQty),
      difference: Value(difference),
      status: const Value('counted'),
      countedAt: Value(DateTime.now()),
      notes: Value(notes),
    ));

    // Update count progress
    final countId = item.countId;
    final counted = await customSelect(
      "SELECT COUNT(*) as c FROM inventory_count_items WHERE count_id = ? AND status = 'counted'",
      variables: [Variable.withString(countId)],
      readsFrom: {inventoryCountItems},
    ).getSingle();

    final discrepancies = await customSelect(
      "SELECT COUNT(*) as c FROM inventory_count_items WHERE count_id = ? AND status = 'counted' AND difference != 0",
      variables: [Variable.withString(countId)],
      readsFrom: {inventoryCountItems},
    ).getSingle();

    await (update(inventoryCounts)..where((c) => c.id.equals(countId))).write(
      InventoryCountsCompanion(
        countedItems: Value(counted.data['c'] as int),
        discrepancies: Value(discrepancies.data['c'] as int),
      ),
    );
  }

  /// Complete a count and apply adjustments
  Future<void> completeInventoryCount({
    required String countId,
    required String completedBy,
    required bool applyAdjustments,
  }) async {
    await transaction(() async {
      if (applyAdjustments) {
        final items = await (select(inventoryCountItems)
              ..where((i) => i.countId.equals(countId))
              ..where((i) => i.status.equals('counted'))
              ..where((i) => i.difference.isBiggerThanValue(0) |
                  i.difference.isSmallerThanValue(0)))
            .get();

        for (final item in items) {
          if (item.difference != null && item.difference != 0) {
            await recordMovement(
              id: 'adj_${countId}_${item.productId}',
              productId: item.productId,
              userId: completedBy,
              type: 'adjustment',
              quantity: item.difference!,
              reference: countId,
              reason:
                  'Ajuste por conteo físico (esperado: ${item.expectedQty}, contado: ${item.countedQty})',
            );
          }
        }
      }

      await (update(inventoryCounts)..where((c) => c.id.equals(countId)))
          .write(InventoryCountsCompanion(
        status: const Value('completed'),
        completedBy: Value(completedBy),
        completedAt: Value(DateTime.now()),
      ));
    });
  }

  /// Get all inventory counts
  Future<List<InventoryCount>> getInventoryCounts({String? status}) {
    final query = select(inventoryCounts)
      ..orderBy([(c) => OrderingTerm.desc(c.startedAt)]);
    if (status != null) {
      query.where((c) => c.status.equals(status));
    }
    return query.get();
  }

  Stream<List<InventoryCount>> watchInventoryCounts() {
    return (select(inventoryCounts)
          ..orderBy([(c) => OrderingTerm.desc(c.startedAt)])
          ..limit(20))
        .watch();
  }

  /// Get count items for a specific count
  Future<List<InventoryCountItem>> getCountItems(String countId) {
    return (select(inventoryCountItems)
          ..where((i) => i.countId.equals(countId)))
        .get();
  }

  /// Get next count number
  Future<String> getNextCountNumber() async {
    final year = DateTime.now().year;
    final result = await customSelect(
      "SELECT COUNT(*) as c FROM inventory_counts WHERE count_number LIKE ?",
      variables: [Variable.withString('INV-$year-%')],
      readsFrom: {inventoryCounts},
    ).getSingle();
    final count = (result.data['c'] as int) + 1;
    return 'INV-$year-${count.toString().padLeft(3, '0')}';
  }

  // ══════════════════════════════════════════════════
  // ── FIFO / BATCH MANAGEMENT ──
  // ══════════════════════════════════════════════════

  /// Get batches for a product ordered by FIFO (oldest first)
  Future<List<ProductBatche>> getFifoBatches(String productId) {
    return (select(productBatches)
          ..where((b) => b.productId.equals(productId))
          ..where((b) => b.quantity.isBiggerThanValue(0))
          ..orderBy([(b) => OrderingTerm.asc(b.receivedAt)]))
        .get();
  }

  /// Consume stock using FIFO: deducts from oldest batches first
  Future<void> consumeFifo({
    required String productId,
    required double quantity,
  }) async {
    await transaction(() async {
      final batches = await getFifoBatches(productId);
      double remaining = quantity;

      for (final batch in batches) {
        if (remaining <= 0) break;

        final deduct =
            remaining > batch.quantity ? batch.quantity : remaining;
        final newQty = batch.quantity - deduct;
        remaining -= deduct;

        await (update(productBatches)..where((b) => b.id.equals(batch.id)))
            .write(ProductBatchesCompanion(quantity: Value(newQty)));
      }
    });
  }

  /// Get batches expiring within N days
  Future<List<ProductBatche>> getExpiringBatches(int daysAhead) {
    final cutoff = DateTime.now().add(Duration(days: daysAhead));
    return (select(productBatches)
          ..where((b) => b.expirationDate.isSmallerOrEqualValue(cutoff))
          ..where((b) => b.quantity.isBiggerThanValue(0))
          ..orderBy([(b) => OrderingTerm.asc(b.expirationDate)]))
        .get();
  }

  /// Get already expired batches still with stock
  Future<List<ProductBatche>> getExpiredBatches() {
    return (select(productBatches)
          ..where(
              (b) => b.expirationDate.isSmallerThanValue(DateTime.now()))
          ..where((b) => b.quantity.isBiggerThanValue(0))
          ..orderBy([(b) => OrderingTerm.asc(b.expirationDate)]))
        .get();
  }

  // ══════════════════════════════════════════════════
  // ── STOCK ALERTS ──
  // ══════════════════════════════════════════════════

  Future<int> insertAlert(StockAlertsCompanion alert) {
    return into(stockAlerts).insert(alert);
  }

  Future<List<StockAlert>> getActiveAlerts({String? alertType}) {
    final query = select(stockAlerts)
      ..where((a) => a.isActive.equals(true))
      ..where((a) => a.resolvedAt.isNull())
      ..orderBy([(a) => OrderingTerm.desc(a.triggeredAt)]);
    if (alertType != null) {
      query.where((a) => a.alertType.equals(alertType));
    }
    return query.get();
  }

  Stream<List<StockAlert>> watchActiveAlerts() {
    return (select(stockAlerts)
          ..where((a) => a.isActive.equals(true))
          ..where((a) => a.resolvedAt.isNull())
          ..orderBy([(a) => OrderingTerm.desc(a.triggeredAt)])
          ..limit(50))
        .watch();
  }

  Stream<int> watchUnreadAlertCount() {
    return customSelect(
      "SELECT COUNT(*) as c FROM stock_alerts WHERE is_active = 1 AND is_read = 0 AND resolved_at IS NULL",
      readsFrom: {stockAlerts},
    ).map((row) => row.data['c'] as int).watchSingle();
  }

  Future<void> markAlertRead(String alertId) {
    return (update(stockAlerts)..where((a) => a.id.equals(alertId)))
        .write(const StockAlertsCompanion(isRead: Value(true)));
  }

  Future<void> resolveAlert(String alertId) {
    return (update(stockAlerts)..where((a) => a.id.equals(alertId))).write(
      StockAlertsCompanion(resolvedAt: Value(DateTime.now())),
    );
  }

  Future<void> markAllAlertsRead() {
    return (update(stockAlerts)
          ..where((a) => a.isRead.equals(false))
          ..where((a) => a.resolvedAt.isNull()))
        .write(const StockAlertsCompanion(isRead: Value(true)));
  }

  // ══════════════════════════════════════════════════
  // ── PURCHASE SUGGESTIONS (AI) ──
  // ══════════════════════════════════════════════════

  Future<int> insertPurchaseSuggestion(PurchaseSuggestionsCompanion s) {
    return into(purchaseSuggestions).insert(s);
  }

  Future<List<PurchaseSuggestion>> getPendingSuggestions() {
    return (select(purchaseSuggestions)
          ..where((s) => s.status.equals('pending'))
          ..orderBy([(s) => OrderingTerm.desc(s.priority)]))
        .get();
  }

  Stream<List<PurchaseSuggestion>> watchPurchaseSuggestions() {
    return (select(purchaseSuggestions)
          ..where((s) => s.status.equals('pending'))
          ..orderBy([(s) => OrderingTerm.desc(s.priority)])
          ..limit(50))
        .watch();
  }

  Future<void> updateSuggestionStatus(String id, String status) {
    return (update(purchaseSuggestions)..where((s) => s.id.equals(id)))
        .write(PurchaseSuggestionsCompanion(status: Value(status)));
  }

  Future<void> clearOldSuggestions() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return (delete(purchaseSuggestions)
          ..where((s) => s.generatedAt.isSmallerThanValue(cutoff))
          ..where((s) =>
              s.status.equals('dismissed') | s.status.equals('ordered')))
        .go();
  }

  // ══════════════════════════════════════════════════
  // ── INVENTORY SNAPSHOTS ──
  // ══════════════════════════════════════════════════

  /// Create an inventory snapshot with all current product data
  Future<String> createSnapshot({
    required String id,
    required String snapshotType,
    String? createdBy,
    String? notes,
  }) async {
    await transaction(() async {
      final prods = await customSelect(
        'SELECT id, current_stock, cost_price, sale_price FROM products WHERE is_active = 1',
        readsFrom: {products},
      ).get();

      double totalUnits = 0;
      double totalCostValue = 0;
      double totalSaleValue = 0;

      for (final p in prods) {
        final qty = (p.data['current_stock'] as num).toDouble();
        final cost = (p.data['cost_price'] as num).toDouble();
        final sale = (p.data['sale_price'] as num).toDouble();
        totalUnits += qty;
        totalCostValue += qty * cost;
        totalSaleValue += qty * sale;

        await into(inventorySnapshotItems)
            .insert(InventorySnapshotItemsCompanion.insert(
          id: 'si_${id}_${p.data['id']}',
          snapshotId: id,
          productId: p.data['id'] as String,
          quantity: qty,
          costPrice: cost,
          salePrice: sale,
          costValue: qty * cost,
          saleValue: qty * sale,
        ));
      }

      // Count low stock
      final lowStock = await customSelect(
        'SELECT COUNT(*) as c FROM products WHERE current_stock <= min_stock AND is_active = 1',
        readsFrom: {products},
      ).getSingle();

      // Count expiring
      final cutoff = DateTime.now().add(const Duration(days: 90));
      final expiring = await customSelect(
        'SELECT COUNT(DISTINCT product_id) as c FROM product_batches WHERE expiration_date <= ? AND quantity > 0',
        variables: [Variable.withDateTime(cutoff)],
        readsFrom: {productBatches},
      ).getSingle();

      await into(inventorySnapshots)
          .insert(InventorySnapshotsCompanion.insert(
        id: id,
        snapshotType: Value(snapshotType),
        totalProducts: Value(prods.length),
        totalUnits: Value(totalUnits),
        totalCostValue: Value(totalCostValue),
        totalSaleValue: Value(totalSaleValue),
        lowStockCount: Value(lowStock.data['c'] as int),
        expiringCount: Value(expiring.data['c'] as int),
        createdBy: Value(createdBy),
        notes: Value(notes),
      ));
    });
    return id;
  }

  Future<List<InventorySnapshot>> getSnapshots({int limit = 30}) {
    return (select(inventorySnapshots)
          ..orderBy([(s) => OrderingTerm.desc(s.snapshotDate)])
          ..limit(limit))
        .get();
  }

  Future<List<InventorySnapshotItem>> getSnapshotItems(String snapshotId) {
    return (select(inventorySnapshotItems)
          ..where((i) => i.snapshotId.equals(snapshotId)))
        .get();
  }

  // ══════════════════════════════════════════════════
  // ── PRODUCT ROTATION ANALYSIS ──
  // ══════════════════════════════════════════════════

  /// Analyze product rotation over N days
  Future<List<ProductRotation>> analyzeRotation({int days = 30}) async {
    final start = DateTime.now().subtract(Duration(days: days));
    final results = await customSelect(
      '''
      SELECT 
        p.id as product_id,
        p.name as product_name,
        p.current_stock,
        COALESCE(SUM(CASE WHEN m.type = 'sale' THEN ABS(m.quantity) ELSE 0 END), 0) as total_sold
      FROM products p
      LEFT JOIN inventory_movements m ON m.product_id = p.id AND m.created_at >= ?
      WHERE p.is_active = 1
      GROUP BY p.id, p.name, p.current_stock
      ORDER BY total_sold DESC
      ''',
      variables: [Variable.withDateTime(start)],
      readsFrom: {products, inventoryMovements},
    ).get();

    return results.map((row) {
      final totalSold = (row.data['total_sold'] as num).toDouble();
      final currentStock = (row.data['current_stock'] as num).toDouble();
      final avgDaily = totalSold / days;
      final daysOfStock = avgDaily > 0 ? currentStock / avgDaily : 9999.0;

      String level;
      if (avgDaily >= 5) {
        level = 'alta';
      } else if (avgDaily >= 1) {
        level = 'media';
      } else if (totalSold > 0) {
        level = 'baja';
      } else {
        level = 'estancado';
      }

      return ProductRotation(
        productId: row.data['product_id'] as String,
        productName: row.data['product_name'] as String,
        currentStock: currentStock,
        totalSold: totalSold,
        avgDailySales: avgDaily,
        daysOfStock: daysOfStock,
        rotationLevel: level,
      );
    }).toList();
  }

  /// Get stagnant products (no sales in N days)
  Future<List<ProductRotation>> getStagnantProducts({int days = 60}) async {
    final rotations = await analyzeRotation(days: days);
    return rotations
        .where((r) => r.rotationLevel == 'estancado')
        .toList();
  }

  // ══════════════════════════════════════════════════
  // ── INVENTORY VALUATION & KPI ──
  // ══════════════════════════════════════════════════

  /// Full inventory valuation
  Future<InventoryValuation> getInventoryValuation() async {
    final result = await customSelect(
      '''
      SELECT 
        COUNT(*) as total_products,
        COALESCE(SUM(current_stock), 0) as total_units,
        COALESCE(SUM(current_stock * cost_price), 0) as total_cost,
        COALESCE(SUM(current_stock * sale_price), 0) as total_sale
      FROM products WHERE is_active = 1
      ''',
      readsFrom: {products},
    ).getSingle();

    final totalCost = (result.data['total_cost'] as num).toDouble();
    final totalSale = (result.data['total_sale'] as num).toDouble();

    return InventoryValuation(
      totalProducts: result.data['total_products'] as int,
      totalUnits: (result.data['total_units'] as num).toDouble(),
      totalCostValue: totalCost,
      totalSaleValue: totalSale,
      potentialProfit: totalSale - totalCost,
    );
  }

  /// Count products by stock status
  Future<Map<String, int>> stockStatusCounts() async {
    final row = await customSelect(
      '''
      SELECT
        SUM(CASE WHEN current_stock <= 0 THEN 1 ELSE 0 END) as out_of_stock,
        SUM(CASE WHEN current_stock > 0 AND current_stock <= min_stock THEN 1 ELSE 0 END) as low_stock,
        SUM(CASE WHEN current_stock > min_stock AND (max_stock IS NULL OR current_stock <= max_stock) THEN 1 ELSE 0 END) as normal,
        SUM(CASE WHEN max_stock IS NOT NULL AND current_stock > max_stock THEN 1 ELSE 0 END) as overstock
      FROM products WHERE is_active = 1
      ''',
      readsFrom: {products},
    ).getSingle();

    return {
      'out_of_stock': (row.data['out_of_stock'] as num?)?.toInt() ?? 0,
      'low_stock': (row.data['low_stock'] as num?)?.toInt() ?? 0,
      'normal': (row.data['normal'] as num?)?.toInt() ?? 0,
      'overstock': (row.data['overstock'] as num?)?.toInt() ?? 0,
    };
  }

  /// Products with stock = 0
  Future<List<Product>> getOutOfStockProducts() {
    return (select(products)
          ..where((p) => p.isActive.equals(true))
          ..where((p) => p.currentStock.isSmallerOrEqualValue(0))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
  }

  /// Products over max stock
  Future<List<Product>> getOverstockProducts() {
    return customSelect(
      'SELECT * FROM products WHERE is_active = 1 AND max_stock IS NOT NULL AND current_stock > max_stock',
      readsFrom: {products},
    ).map((row) => products.map(row.data)).get();
  }

  /// Category-level inventory summary
  Future<List<Map<String, dynamic>>> inventoryByCategory() async {
    final results = await customSelect(
      '''
      SELECT 
        COALESCE(c.name, 'Sin categoría') as category_name,
        COUNT(p.id) as product_count,
        COALESCE(SUM(p.current_stock), 0) as total_stock,
        COALESCE(SUM(p.current_stock * p.cost_price), 0) as total_value
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE p.is_active = 1
      GROUP BY c.name
      ORDER BY total_value DESC
      ''',
      readsFrom: {products, categories},
    ).get();

    return results
        .map((row) => {
              'category': row.data['category_name'] as String,
              'count': row.data['product_count'] as int,
              'stock': (row.data['total_stock'] as num).toDouble(),
              'value': (row.data['total_value'] as num).toDouble(),
            })
        .toList();
  }
}
