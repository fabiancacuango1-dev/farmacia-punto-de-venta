import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/credit_notes_table.dart';
import '../tables/products_table.dart';

part 'credit_notes_dao.g.dart';

@DriftAccessor(tables: [CreditNotes, CreditNoteItems, Products])
class CreditNotesDao extends DatabaseAccessor<AppDatabase>
    with _$CreditNotesDaoMixin {
  CreditNotesDao(super.db);

  Future<List<CreditNote>> getAllCreditNotes({int limit = 100}) {
    return (select(creditNotes)
          ..orderBy([(n) => OrderingTerm.desc(n.createdAt)])
          ..limit(limit))
        .get();
  }

  Stream<List<CreditNote>> watchCreditNotes() {
    return (select(creditNotes)
          ..orderBy([(n) => OrderingTerm.desc(n.createdAt)])
          ..limit(100))
        .watch();
  }

  Future<void> createCreditNote({
    required CreditNotesCompanion note,
    required List<CreditNoteItemsCompanion> items,
  }) async {
    await transaction(() async {
      await into(creditNotes).insert(note);
      for (final item in items) {
        await into(creditNoteItems).insert(item);
        // Return stock if applicable
        if (item.returnToStock.value) {
          final product = await (select(products)
                ..where((p) => p.id.equals(item.productId.value)))
              .getSingleOrNull();
          if (product != null) {
            await (update(products)..where((p) => p.id.equals(item.productId.value)))
                .write(ProductsCompanion(
              currentStock: Value(product.currentStock + item.quantity.value),
              updatedAt: Value(DateTime.now()),
            ));
          }
        }
      }
    });
  }

  Future<List<CreditNoteItem>> getNoteItems(String noteId) {
    return (select(creditNoteItems)
          ..where((i) => i.creditNoteId.equals(noteId)))
        .get();
  }

  Future<List<CreditNoteItem>> getCreditNoteItems(String noteId) {
    return getNoteItems(noteId);
  }

  Future<void> voidCreditNote(String noteId) {
    return (update(creditNotes)..where((n) => n.id.equals(noteId)))
        .write(const CreditNotesCompanion(
      status: Value('cancelled'),
    ));
  }

  Future<void> applyCreditNote(String noteId) {
    return (update(creditNotes)..where((n) => n.id.equals(noteId)))
        .write(const CreditNotesCompanion(
      status: Value('applied'),
    ));
  }

  Future<String> generateNoteNumber() async {
    final today = DateTime.now();
    final prefix =
        'NC-${today.year}${today.month.toString().padLeft(2, '0')}';
    final result = await customSelect(
      "SELECT COUNT(*) as c FROM credit_notes WHERE note_number LIKE ?",
      variables: [Variable('$prefix%')],
      readsFrom: {creditNotes},
    ).getSingle();
    final count = (result.data['c'] as int) + 1;
    return '$prefix-${count.toString().padLeft(5, '0')}';
  }
}
