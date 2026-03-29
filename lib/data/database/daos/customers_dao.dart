import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/customers_table.dart';
import '../tables/customer_credits_table.dart';
import '../tables/credit_payments_table.dart';
import '../tables/loyalty_transactions_table.dart';

part 'customers_dao.g.dart';

@DriftAccessor(tables: [Customers, CustomerCredits, CreditPayments, LoyaltyTransactions])
class CustomersDao extends DatabaseAccessor<AppDatabase>
    with _$CustomersDaoMixin {
  CustomersDao(super.db);

  // ── Customers CRUD ──

  Future<List<Customer>> getAllCustomers({bool activeOnly = true}) {
    final query = select(customers);
    if (activeOnly) {
      query.where((c) => c.isActive.equals(true));
    }
    query.orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.get();
  }

  Stream<List<Customer>> watchAllCustomers() {
    return (select(customers)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<Customer?> getCustomerById(String id) {
    return (select(customers)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<Customer>> searchCustomers(String query) {
    final pattern = '%$query%';
    return (select(customers)
          ..where((c) =>
              c.name.like(pattern) |
              c.ruc.like(pattern) |
              c.cedula.like(pattern) |
              c.phone.like(pattern))
          ..where((c) => c.isActive.equals(true))
          ..limit(30))
        .get();
  }

  Future<int> insertCustomer(CustomersCompanion customer) {
    return into(customers).insert(customer);
  }

  Future<bool> updateCustomer(CustomersCompanion customer) {
    return (update(customers)..where((c) => c.id.equals(customer.id.value)))
        .write(customer)
        .then((rows) => rows > 0);
  }

  // ── Credits ──

  Future<List<CustomerCredit>> getActiveCredits(String customerId) {
    return (select(customerCredits)
          ..where((c) => c.customerId.equals(customerId))
          ..where((c) => c.status.isIn(['active', 'overdue']))
          ..orderBy([(c) => OrderingTerm.asc(c.dueDate)]))
        .get();
  }

  Stream<List<CustomerCredit>> watchActiveCredits(String customerId) {
    return (select(customerCredits)
          ..where((c) => c.customerId.equals(customerId))
          ..where((c) => c.status.isIn(['active', 'overdue']))
          ..orderBy([(c) => OrderingTerm.asc(c.dueDate)]))
        .watch();
  }

  Future<List<CustomerCredit>> getOverdueCredits() {
    return (select(customerCredits)
          ..where((c) => c.status.equals('active'))
          ..where((c) => c.dueDate.isSmallerThanValue(DateTime.now()))
          ..orderBy([(c) => OrderingTerm.asc(c.dueDate)]))
        .get();
  }

  /// Watch pending credits joined with customer name
  Stream<List<({CustomerCredit credit, String customerName})>> watchPendingCreditsWithCustomer() {
    final query = select(customerCredits).join([
      innerJoin(customers, customers.id.equalsExp(customerCredits.customerId)),
    ])
      ..where(customerCredits.status.isIn(['active', 'overdue']))
      ..orderBy([OrderingTerm.asc(customerCredits.dueDate)]);

    return query.watch().map((rows) => rows.map((row) {
      return (
        credit: row.readTable(customerCredits),
        customerName: row.readTable(customers).name,
      );
    }).toList());
  }

  Future<int> insertCredit(CustomerCreditsCompanion credit) {
    return into(customerCredits).insert(credit);
  }

  Future<void> registerCreditPayment({
    required String creditId,
    required String customerId,
    required CreditPaymentsCompanion payment,
  }) async {
    await transaction(() async {
      await into(creditPayments).insert(payment);

      final credit = await (select(customerCredits)
            ..where((c) => c.id.equals(creditId)))
          .getSingle();

      final newPaid = credit.paidAmount + payment.amount.value;
      final newBalance = credit.amount - newPaid;
      final newStatus = newBalance <= 0 ? 'paid' : 'active';

      await (update(customerCredits)..where((c) => c.id.equals(creditId)))
          .write(CustomerCreditsCompanion(
        paidAmount: Value(newPaid),
        balance: Value(newBalance < 0 ? 0 : newBalance),
        status: Value(newStatus),
        updatedAt: Value(DateTime.now()),
      ));

      // Update customer balance
      final customer = await (select(customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();
      await (update(customers)..where((c) => c.id.equals(customerId)))
          .write(CustomersCompanion(
        currentBalance: Value(customer.currentBalance - payment.amount.value),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  Future<List<CreditPayment>> getPaymentsForCredit(String creditId) {
    return (select(creditPayments)
          ..where((p) => p.creditId.equals(creditId))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .get();
  }

  // ── Loyalty Points ──

  Future<void> addLoyaltyPoints({
    required String customerId,
    required int points,
    required String type,
    String? reference,
    String? description,
  }) async {
    await transaction(() async {
      await into(loyaltyTransactions).insert(LoyaltyTransactionsCompanion.insert(
        id: 'loy_${DateTime.now().millisecondsSinceEpoch}',
        customerId: customerId,
        type: type,
        points: points,
        reference: Value(reference),
        description: Value(description),
      ));

      final customer = await (select(customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();

      await (update(customers)..where((c) => c.id.equals(customerId)))
          .write(CustomersCompanion(
        loyaltyPoints: Value(customer.loyaltyPoints + points),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  Future<void> redeemPoints({
    required String customerId,
    required int points,
    required double walletAmount,
    String? reference,
  }) async {
    await transaction(() async {
      await into(loyaltyTransactions).insert(LoyaltyTransactionsCompanion.insert(
        id: 'loy_${DateTime.now().millisecondsSinceEpoch}',
        customerId: customerId,
        type: 'redeem',
        points: -points,
        reference: Value(reference),
        description: const Value('Canje de puntos'),
      ));

      final customer = await (select(customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();

      await (update(customers)..where((c) => c.id.equals(customerId)))
          .write(CustomersCompanion(
        loyaltyPoints: Value(customer.loyaltyPoints - points),
        walletBalance: Value(customer.walletBalance + walletAmount),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  Future<List<LoyaltyTransaction>> getLoyaltyHistory(String customerId, {int limit = 50}) {
    return (select(loyaltyTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  // ── Stats ──

  Future<int> countActiveCustomers() async {
    final result = await customSelect(
      'SELECT COUNT(*) as c FROM customers WHERE is_active = 1',
      readsFrom: {customers},
    ).getSingle();
    return result.data['c'] as int;
  }

  Future<double> totalOutstandingCredits() async {
    final result = await customSelect(
      "SELECT COALESCE(SUM(balance), 0) as total FROM customer_credits WHERE status IN ('active', 'overdue')",
      readsFrom: {customerCredits},
    ).getSingle();
    return (result.data['total'] as num).toDouble();
  }
}
