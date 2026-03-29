import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products_table.dart';
import '../tables/categories_table.dart';
import '../tables/product_batches_table.dart';

part 'products_dao.g.dart';

@DriftAccessor(tables: [Products, Categories, ProductBatches])
class ProductsDao extends DatabaseAccessor<AppDatabase>
    with _$ProductsDaoMixin {
  ProductsDao(super.db);

  // ── Products CRUD ──

  Future<List<Product>> getAllProducts({bool activeOnly = true}) {
    final query = select(products);
    if (activeOnly) {
      query.where((p) => p.isActive.equals(true));
    }
    query.orderBy([(p) => OrderingTerm.asc(p.name)]);
    return query.get();
  }

  Stream<List<Product>> watchAllProducts({bool activeOnly = true}) {
    final query = select(products);
    if (activeOnly) {
      query.where((p) => p.isActive.equals(true));
    }
    query.orderBy([(p) => OrderingTerm.asc(p.name)]);
    return query.watch();
  }

  Future<Product?> getProductById(String id) {
    return (select(products)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Product?> getProductByBarcode(String barcode) {
    return (select(products)..where((p) => p.barcode.equals(barcode)))
        .getSingleOrNull();
  }

  Future<List<Product>> searchProducts(String query) {
    final pattern = '%$query%';
    return (select(products)
          ..where((p) =>
              p.name.like(pattern) |
              p.barcode.like(pattern) |
              p.genericName.like(pattern) |
              p.internalCode.like(pattern))
          ..where((p) => p.isActive.equals(true))
          ..limit(50))
        .get();
  }

  Future<int> insertProduct(ProductsCompanion product) {
    return into(products).insert(product);
  }

  Future<bool> updateProduct(ProductsCompanion product) {
    return (update(products)..where((p) => p.id.equals(product.id.value)))
        .write(product)
        .then((rows) => rows > 0);
  }

  Future<int> softDeleteProduct(String id) {
    return (update(products)..where((p) => p.id.equals(id)))
        .write(const ProductsCompanion(isActive: Value(false)));
  }

  // ── Stock ──

  Future<List<Product>> getLowStockProducts() {
    return customSelect(
      'SELECT * FROM products WHERE current_stock <= min_stock AND is_active = 1',
      readsFrom: {products},
    ).map((row) => products.map(row.data)).get();
  }

  Stream<List<Product>> watchLowStockProducts() {
    return customSelect(
      'SELECT * FROM products WHERE current_stock <= min_stock AND is_active = 1',
      readsFrom: {products},
    ).map((row) => products.map(row.data)).watch();
  }

  Future<void> updateStock(String productId, double newStock) {
    return (update(products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        currentStock: Value(newStock),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  // ── Categories ──

  Future<List<Category>> getAllCategories() {
    return (select(categories)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
  }

  Stream<List<Category>> watchCategories() {
    return (select(categories)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<int> insertCategory(CategoriesCompanion category) {
    return into(categories).insert(category);
  }

  // ── Batches ──

  Future<List<ProductBatche>> getBatchesForProduct(String productId) {
    return (select(productBatches)
          ..where((b) => b.productId.equals(productId))
          ..where((b) => b.quantity.isBiggerThanValue(0))
          ..orderBy([(b) => OrderingTerm.asc(b.expirationDate)]))
        .get();
  }

  Stream<List<ProductBatche>> watchExpiringBatches(int daysAhead) {
    final cutoff = DateTime.now().add(Duration(days: daysAhead));
    return (select(productBatches)
          ..where((b) => b.expirationDate.isSmallerOrEqualValue(cutoff))
          ..where((b) => b.quantity.isBiggerThanValue(0))
          ..orderBy([(b) => OrderingTerm.asc(b.expirationDate)]))
        .watch();
  }

  Future<int> insertBatch(ProductBatchesCompanion batch) {
    return into(productBatches).insert(batch);
  }

  Future<void> updateBatchQuantity(String batchId, double newQuantity) {
    return (update(productBatches)..where((b) => b.id.equals(batchId)))
        .write(ProductBatchesCompanion(quantity: Value(newQuantity)));
  }

  // ── Stats ──

  Future<int> countActiveProducts() async {
    final result = await customSelect(
      'SELECT COUNT(*) as c FROM products WHERE is_active = 1',
      readsFrom: {products},
    ).getSingle();
    return result.data['c'] as int;
  }

  Future<double> totalInventoryValue() async {
    final result = await customSelect(
      'SELECT SUM(current_stock * cost_price) as total FROM products WHERE is_active = 1',
      readsFrom: {products},
    ).getSingle();
    return (result.data['total'] as num?)?.toDouble() ?? 0.0;
  }
}
