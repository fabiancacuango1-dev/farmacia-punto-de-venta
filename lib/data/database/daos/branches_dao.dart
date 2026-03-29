import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/branches_table.dart';
import '../tables/supplier_returns_table.dart';

part 'branches_dao.g.dart';

@DriftAccessor(tables: [Branches, BranchTransfers, BranchTransferItems, SupplierReturns, SupplierReturnItems])
class BranchesDao extends DatabaseAccessor<AppDatabase>
    with _$BranchesDaoMixin {
  BranchesDao(super.db);

  // ── Branches ──

  Future<List<Branche>> getAllBranches({bool activeOnly = true}) {
    final query = select(branches);
    if (activeOnly) {
      query.where((b) => b.isActive.equals(true));
    }
    query.orderBy([(b) => OrderingTerm.asc(b.name)]);
    return query.get();
  }

  Stream<List<Branche>> watchBranches() {
    return (select(branches)
          ..where((b) => b.isActive.equals(true))
          ..orderBy([(b) => OrderingTerm.asc(b.name)]))
        .watch();
  }

  Future<List<Branche>> getActiveBranches() {
    return getAllBranches(activeOnly: true);
  }

  Future<int> insertBranch(BranchesCompanion branch) {
    return into(branches).insert(branch);
  }

  Future<bool> updateBranch(BranchesCompanion branch) {
    return (update(branches)..where((b) => b.id.equals(branch.id.value)))
        .write(branch)
        .then((rows) => rows > 0);
  }

  // ── Transfers ──

  Future<void> createTransfer({
    required BranchTransfersCompanion transfer,
    required List<BranchTransferItemsCompanion> items,
  }) async {
    await transaction(() async {
      await into(branchTransfers).insert(transfer);
      for (final item in items) {
        await into(branchTransferItems).insert(item);
      }
    });
  }

  Future<List<BranchTransfer>> getTransfers({String? status}) {
    final query = select(branchTransfers)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    return query.get();
  }

  Stream<List<BranchTransfer>> watchTransfers() {
    return (select(branchTransfers)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(50))
        .watch();
  }

  Future<List<BranchTransferItem>> getTransferItems(String transferId) {
    return (select(branchTransferItems)
          ..where((i) => i.transferId.equals(transferId)))
        .get();
  }

  Future<void> receiveTransfer(String transferId, String receivedBy) {
    return (update(branchTransfers)..where((t) => t.id.equals(transferId)))
        .write(BranchTransfersCompanion(
      status: const Value('received'),
      receivedAt: Value(DateTime.now()),
      receivedBy: Value(receivedBy),
    ));
  }

  // ── Supplier Returns ──

  Future<void> createSupplierReturn({
    required SupplierReturnsCompanion ret,
    required List<SupplierReturnItemsCompanion> items,
  }) async {
    await transaction(() async {
      await into(supplierReturns).insert(ret);
      for (final item in items) {
        await into(supplierReturnItems).insert(item);
      }
    });
  }

  Future<List<SupplierReturn>> getSupplierReturns({String? status}) {
    final query = select(supplierReturns)
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (status != null) {
      query.where((r) => r.status.equals(status));
    }
    return query.get();
  }

  Stream<List<SupplierReturn>> watchSupplierReturns() {
    return (select(supplierReturns)
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
          ..limit(50))
        .watch();
  }

  Future<List<SupplierReturnItem>> getReturnItems(String returnId) {
    return (select(supplierReturnItems)
          ..where((i) => i.returnId.equals(returnId)))
        .get();
  }

  Future<void> completeSupplierReturn(String returnId) {
    return (update(supplierReturns)..where((r) => r.id.equals(returnId)))
        .write(SupplierReturnsCompanion(
      status: const Value('completed'),
      processedAt: Value(DateTime.now()),
    ));
  }
}
