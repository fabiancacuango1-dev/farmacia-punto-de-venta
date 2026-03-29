import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/promotions_table.dart';
import '../tables/product_combos_table.dart';

part 'promotions_dao.g.dart';

@DriftAccessor(tables: [Promotions, ProductCombos, ComboItems])
class PromotionsDao extends DatabaseAccessor<AppDatabase>
    with _$PromotionsDaoMixin {
  PromotionsDao(super.db);

  // ── Promotions CRUD ──

  Future<List<Promotion>> getActivePromotions() {
    final now = DateTime.now();
    return (select(promotions)
          ..where((p) => p.isActive.equals(true))
          ..where((p) => p.startDate.isSmallerOrEqualValue(now))
          ..where((p) => p.endDate.isBiggerOrEqualValue(now))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
  }

  Stream<List<Promotion>> watchActivePromotions() {
    final now = DateTime.now();
    return (select(promotions)
          ..where((p) => p.isActive.equals(true))
          ..where((p) => p.startDate.isSmallerOrEqualValue(now))
          ..where((p) => p.endDate.isBiggerOrEqualValue(now))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  Future<List<Promotion>> getAllPromotions() {
    return (select(promotions)
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .get();
  }

  Future<int> insertPromotion(PromotionsCompanion promo) {
    return into(promotions).insert(promo);
  }

  Future<bool> updatePromotion(PromotionsCompanion promo) {
    return (update(promotions)..where((p) => p.id.equals(promo.id.value)))
        .write(promo)
        .then((rows) => rows > 0);
  }

  Future<void> incrementUsage(String promoId) async {
    final promo = await (select(promotions)..where((p) => p.id.equals(promoId)))
        .getSingle();
    await (update(promotions)..where((p) => p.id.equals(promoId)))
        .write(PromotionsCompanion(usageCount: Value(promo.usageCount + 1)));
  }

  // ── Combos CRUD ──

  Future<List<ProductCombo>> getActiveCombos() {
    return (select(productCombos)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
  }

  Stream<List<ProductCombo>> watchActiveCombos() {
    return (select(productCombos)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<void> createCombo({
    required ProductCombosCompanion combo,
    required List<ComboItemsCompanion> items,
  }) async {
    await transaction(() async {
      await into(productCombos).insert(combo);
      for (final item in items) {
        await into(comboItems).insert(item);
      }
    });
  }

  Future<List<ComboItem>> getComboItems(String comboId) {
    return (select(comboItems)..where((i) => i.comboId.equals(comboId))).get();
  }

  Future<bool> updateCombo(ProductCombosCompanion combo) {
    return (update(productCombos)..where((c) => c.id.equals(combo.id.value)))
        .write(combo)
        .then((rows) => rows > 0);
  }

  Future<void> deleteComboItems(String comboId) {
    return (delete(comboItems)..where((i) => i.comboId.equals(comboId))).go();
  }
}
