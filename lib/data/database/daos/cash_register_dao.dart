import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/cash_registers_table.dart';
import '../tables/cash_movements_table.dart';

part 'cash_register_dao.g.dart';

@DriftAccessor(tables: [CashRegisters, CashMovements])
class CashRegisterDao extends DatabaseAccessor<AppDatabase>
    with _$CashRegisterDaoMixin {
  CashRegisterDao(super.db);

  // ── Cash Register ──

  Future<CashRegister?> getOpenRegister(String userId) {
    return (select(cashRegisters)
          ..where((c) => c.userId.equals(userId))
          ..where((c) => c.status.equals('open'))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<CashRegister?> getAnyOpenRegister() {
    return (select(cashRegisters)
          ..where((c) => c.status.equals('open'))
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<CashRegister?> watchOpenRegister(String userId) {
    return (select(cashRegisters)
          ..where((c) => c.userId.equals(userId))
          ..where((c) => c.status.equals('open'))
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<int> openRegister(CashRegistersCompanion register) {
    return into(cashRegisters).insert(register);
  }

  Future<void> closeRegister({
    required String registerId,
    required double closingAmount,
    required double expectedAmount,
    required double totalSales,
    required double totalCash,
    required double totalCard,
    required double totalTransfer,
    required int salesCount,
    String? notes,
  }) {
    return (update(cashRegisters)..where((c) => c.id.equals(registerId)))
        .write(CashRegistersCompanion(
      closingAmount: Value(closingAmount),
      expectedAmount: Value(expectedAmount),
      difference: Value(closingAmount - expectedAmount),
      totalSales: Value(totalSales),
      totalCash: Value(totalCash),
      totalCard: Value(totalCard),
      totalTransfer: Value(totalTransfer),
      salesCount: Value(salesCount),
      status: const Value('closed'),
      notes: Value(notes),
      closedAt: Value(DateTime.now()),
      syncStatus: const Value('pending'),
    ));
  }

  Future<void> updateRegisterTotals(
    String registerId, {
    required double saleAmount,
    required String paymentMethod,
  }) async {
    final register = await (select(cashRegisters)
          ..where((c) => c.id.equals(registerId)))
        .getSingle();

    final companion = CashRegistersCompanion(
      totalSales: Value(register.totalSales + saleAmount),
      salesCount: Value(register.salesCount + 1),
    );

    // Update specific payment method total
    CashRegistersCompanion updated;
    switch (paymentMethod) {
      case 'cash':
        updated = companion.copyWith(
          totalCash: Value(register.totalCash + saleAmount),
        );
        break;
      case 'card':
        updated = companion.copyWith(
          totalCard: Value(register.totalCard + saleAmount),
        );
        break;
      case 'transfer':
        updated = companion.copyWith(
          totalTransfer: Value(register.totalTransfer + saleAmount),
        );
        break;
      default:
        updated = companion;
    }

    await (update(cashRegisters)..where((c) => c.id.equals(registerId)))
        .write(updated);
  }

  // ── Cash Movements ──

  Future<int> addMovement(CashMovementsCompanion movement) {
    return into(cashMovements).insert(movement);
  }

  Future<List<CashMovement>> getMovementsForRegister(String registerId) {
    return (select(cashMovements)
          ..where((m) => m.cashRegisterId.equals(registerId))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
        .get();
  }

  Stream<List<CashMovement>> watchMovementsForRegister(String registerId) {
    return (select(cashMovements)
          ..where((m) => m.cashRegisterId.equals(registerId))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
        .watch();
  }

  // ── History ──

  Future<List<CashRegister>> getRegisterHistory({int limit = 30}) {
    return (select(cashRegisters)
          ..orderBy([(c) => OrderingTerm.desc(c.openedAt)])
          ..limit(limit))
        .get();
  }

  Stream<List<CashRegister>> watchRegisterHistory({int limit = 30}) {
    return (select(cashRegisters)
          ..orderBy([(c) => OrderingTerm.desc(c.openedAt)])
          ..limit(limit))
        .watch();
  }
}

// Extension to support copyWith on CashRegistersCompanion
extension CashRegistersCompanionCopyWith on CashRegistersCompanion {
  CashRegistersCompanion copyWith({
    Value<double>? totalCash,
    Value<double>? totalCard,
    Value<double>? totalTransfer,
  }) {
    return CashRegistersCompanion(
      totalSales: totalSales,
      salesCount: salesCount,
      totalCash: totalCash ?? this.totalCash,
      totalCard: totalCard ?? this.totalCard,
      totalTransfer: totalTransfer ?? this.totalTransfer,
    );
  }
}
