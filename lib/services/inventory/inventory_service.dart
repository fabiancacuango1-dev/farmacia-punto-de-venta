import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../data/database/daos/inventory_dao.dart';
import 'package:drift/drift.dart';

final inventoryServiceProvider = Provider<InventoryService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return InventoryService(db);
});

class InventoryService {
  final AppDatabase _db;

  InventoryService(this._db);

  InventoryDao get _inventoryDao => _db.inventoryDao;

  // ══════════════════════════════════════════════════
  // ── ALERT GENERATION ──
  // ══════════════════════════════════════════════════

  /// Scan all products and generate appropriate alerts
  Future<int> generateAlerts(String userId) async {
    int alertsCreated = 0;
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;

    // 1. Low stock alerts
    final lowStock = await _db.productsDao.getLowStockProducts();
    for (final p in lowStock) {
      if (p.currentStock <= 0) {
        await _inventoryDao.insertAlert(StockAlertsCompanion.insert(
          id: 'alert_out_${ts}_${p.id}',
          productId: p.id,
          alertType: 'low_stock',
          threshold: Value(p.minStock),
          message: Value(
              '${p.name}: SIN STOCK (mín: ${p.minStock.toInt()})'),
          severity: const Value('critical'),
        ));
        alertsCreated++;
      } else {
        await _inventoryDao.insertAlert(StockAlertsCompanion.insert(
          id: 'alert_low_${ts}_${p.id}',
          productId: p.id,
          alertType: 'low_stock',
          threshold: Value(p.minStock),
          message: Value(
              '${p.name}: Stock bajo (${p.currentStock.toInt()}/${p.minStock.toInt()})'),
          severity: const Value('warning'),
        ));
        alertsCreated++;
      }
    }

    // 2. Overstock alerts
    final overstock = await _inventoryDao.getOverstockProducts();
    for (final p in overstock) {
      await _inventoryDao.insertAlert(StockAlertsCompanion.insert(
        id: 'alert_over_${ts}_${p.id}',
        productId: p.id,
        alertType: 'overstock',
        threshold: Value(p.maxStock ?? 0),
        message: Value(
            '${p.name}: Sobrestock (${p.currentStock.toInt()}/${p.maxStock?.toInt() ?? 0})'),
        severity: const Value('info'),
      ));
      alertsCreated++;
    }

    // 3. Expiring soon alerts
    final expiring = await _inventoryDao.getExpiringBatches(30);
    for (final b in expiring) {
      final daysLeft =
          b.expirationDate.difference(now).inDays;
      await _inventoryDao.insertAlert(StockAlertsCompanion.insert(
        id: 'alert_exp_${ts}_${b.id}',
        productId: b.productId,
        alertType: daysLeft < 0 ? 'expired' : 'expiring_soon',
        threshold: Value(30),
        message: Value(daysLeft < 0
            ? 'Lote ${b.batchNumber}: CADUCADO hace ${-daysLeft} días (${b.quantity.toInt()} unids)'
            : 'Lote ${b.batchNumber}: Caduca en $daysLeft días (${b.quantity.toInt()} unids)'),
        severity: Value(daysLeft < 0 ? 'critical' : 'warning'),
      ));
      alertsCreated++;
    }

    return alertsCreated;
  }

  // ══════════════════════════════════════════════════
  // ── PURCHASE SUGGESTION ENGINE ──
  // ══════════════════════════════════════════════════

  /// Generate AI-based purchase suggestions using sales velocity
  Future<int> generatePurchaseSuggestions() async {
    int suggestionsCreated = 0;
    final ts = DateTime.now().millisecondsSinceEpoch;

    // Clear old dismissed/ordered suggestions
    await _inventoryDao.clearOldSuggestions();

    // Analyze rotation to get avg daily sales
    final rotations = await _inventoryDao.analyzeRotation(days: 30);

    for (final r in rotations) {
      if (r.avgDailySales <= 0) continue; // Skip products with no sales

      // Get product for min stock info
      final product = await _db.productsDao.getProductById(r.productId);
      if (product == null) continue;

      final daysUntilStockout =
          r.currentStock / r.avgDailySales;

      // Suggest purchase if stock will run out in < 14 days
      if (daysUntilStockout < 14) {
        // Suggest enough for 30 days of stock
        final targetStock = r.avgDailySales * 30;
        final suggestedQty =
            targetStock - r.currentStock;

        if (suggestedQty <= 0) continue;

        int priority;
        if (daysUntilStockout <= 0) {
          priority = 3; // critical - already out of stock
        } else if (daysUntilStockout <= 3) {
          priority = 2; // high
        } else if (daysUntilStockout <= 7) {
          priority = 1; // medium
        } else {
          priority = 0; // low
        }

        String reason;
        if (daysUntilStockout <= 0) {
          reason = 'SIN STOCK. Venta promedio: ${r.avgDailySales.toStringAsFixed(1)}/día';
        } else {
          reason =
              'Stock para ${daysUntilStockout.toStringAsFixed(0)} días. Venta promedio: ${r.avgDailySales.toStringAsFixed(1)}/día';
        }

        await _inventoryDao
            .insertPurchaseSuggestion(PurchaseSuggestionsCompanion.insert(
          id: 'sug_${ts}_${r.productId}',
          productId: r.productId,
          suggestedQty: suggestedQty.roundToDouble(),
          estimatedCost: Value(suggestedQty * product.costPrice),
          avgDailySales: Value(r.avgDailySales),
          daysUntilStockout: Value(daysUntilStockout),
          priority: Value(priority),
          reason: Value(reason),
          expiresAt: Value(DateTime.now().add(const Duration(days: 7))),
        ));
        suggestionsCreated++;
      }
    }

    return suggestionsCreated;
  }

  // ══════════════════════════════════════════════════
  // ── INVENTORY SNAPSHOT ──
  // ══════════════════════════════════════════════════

  /// Create a manual inventory snapshot
  Future<String> takeSnapshot({
    required String userId,
    String type = 'manual',
    String? notes,
  }) async {
    final id =
        'snap_${DateTime.now().millisecondsSinceEpoch}';
    return _inventoryDao.createSnapshot(
      id: id,
      snapshotType: type,
      createdBy: userId,
      notes: notes,
    );
  }

  // ══════════════════════════════════════════════════
  // ── DASHBOARD KPIs ──
  // ══════════════════════════════════════════════════

  /// Get all KPIs for the inventory dashboard
  Future<Map<String, dynamic>> getDashboardKPIs() async {
    final valuation = await _inventoryDao.getInventoryValuation();
    final stockStatus = await _inventoryDao.stockStatusCounts();
    final categoryData = await _inventoryDao.inventoryByCategory();

    final now = DateTime.now();
    final movementCounts = await _inventoryDao.movementCountsByType(
      DateTime(now.year, now.month, 1),
      now,
    );

    return {
      'valuation': valuation,
      'stockStatus': stockStatus,
      'categories': categoryData,
      'movementsThisMonth': movementCounts,
    };
  }
}
