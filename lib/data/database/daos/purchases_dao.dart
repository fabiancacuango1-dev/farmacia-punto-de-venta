import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/purchase_orders_table.dart';
import '../tables/purchase_order_items_table.dart';
import '../tables/suppliers_table.dart';
import '../tables/products_table.dart';
import '../tables/product_batches_table.dart';

part 'purchases_dao.g.dart';

class PurchaseOrderWithItems {
  final PurchaseOrder order;
  final Supplier supplier;
  final List<PurchaseOrderItem> items;
  PurchaseOrderWithItems({
    required this.order,
    required this.supplier,
    required this.items,
  });
}

@DriftAccessor(
    tables: [PurchaseOrders, PurchaseOrderItems, Suppliers, Products, ProductBatches])
class PurchasesDao extends DatabaseAccessor<AppDatabase>
    with _$PurchasesDaoMixin {
  PurchasesDao(super.db);

  // ── Suppliers ──

  Future<List<Supplier>> getAllSuppliers({bool activeOnly = true}) {
    final query = select(suppliers);
    if (activeOnly) {
      query.where((s) => s.isActive.equals(true));
    }
    query.orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.get();
  }

  Stream<List<Supplier>> watchSuppliers() {
    return (select(suppliers)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .watch();
  }

  Future<int> insertSupplier(SuppliersCompanion supplier) {
    return into(suppliers).insert(supplier);
  }

  Future<bool> updateSupplier(SuppliersCompanion supplier) {
    return (update(suppliers)..where((s) => s.id.equals(supplier.id.value)))
        .write(supplier)
        .then((rows) => rows > 0);
  }

  // ── Purchase Orders ──

  Future<void> createPurchaseOrder({
    required PurchaseOrdersCompanion order,
    required List<PurchaseOrderItemsCompanion> items,
  }) async {
    await transaction(() async {
      await into(purchaseOrders).insert(order);
      for (final item in items) {
        await into(purchaseOrderItems).insert(item);
      }
    });
  }

  Future<void> receivePurchaseOrder(String orderId) async {
    await transaction(() async {
      final items = await (select(purchaseOrderItems)
            ..where((i) => i.purchaseOrderId.equals(orderId)))
          .get();

      for (final item in items) {
        // Update product stock
        final product = await (select(products)
              ..where((p) => p.id.equals(item.productId)))
            .getSingle();

        final newStock = product.currentStock + item.quantity;
        await (update(products)..where((p) => p.id.equals(item.productId)))
            .write(ProductsCompanion(
          currentStock: Value(newStock),
          costPrice: Value(item.unitCost),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value('pending'),
        ));

        // Update received quantity
        await (update(purchaseOrderItems)
              ..where((i) => i.id.equals(item.id)))
            .write(PurchaseOrderItemsCompanion(
          receivedQuantity: Value(item.quantity),
        ));

        // Create batch if batch info provided
        if (item.batchNumber != null) {
          await into(productBatches).insert(ProductBatchesCompanion.insert(
            id: 'batch_${DateTime.now().millisecondsSinceEpoch}_${item.productId}',
            productId: item.productId,
            batchNumber: item.batchNumber!,
            expirationDate: item.expirationDate ?? DateTime.now().add(const Duration(days: 365)),
            quantity: Value(item.quantity),
            costPrice: Value(item.unitCost),
          ));
        }
      }

      // Update order status
      await (update(purchaseOrders)..where((o) => o.id.equals(orderId)))
          .write(PurchaseOrdersCompanion(
        status: const Value('received'),
        receivedDate: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ));
    });
  }

  Future<List<PurchaseOrder>> getPurchaseOrders({String? status}) {
    final query = select(purchaseOrders)
      ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]);
    if (status != null) {
      query.where((o) => o.status.equals(status));
    }
    return query.get();
  }

  Future<List<PurchaseOrderItem>> getOrderItems(String orderId) {
    return (select(purchaseOrderItems)
          ..where((i) => i.purchaseOrderId.equals(orderId)))
        .get();
  }
}
