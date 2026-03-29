import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Text('Clientes',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showCustomerDialog(context, db),
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Nuevo Cliente'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Tabs
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Clientes'),
                Tab(text: 'Créditos Pendientes'),
                Tab(text: 'Puntos de Lealtad'),
              ],
            ),
            const SizedBox(height: 12),
            // Search
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, cédula, RUC o teléfono...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 12),
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCustomersList(db),
                  _buildCreditsList(db),
                  _buildLoyaltyList(db),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomersList(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<Customer>>(
        stream: db.customersDao.watchAllCustomers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var customers = snapshot.data!;
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            customers = customers.where((c) {
              return c.name.toLowerCase().contains(q) ||
                  (c.cedula?.toLowerCase().contains(q) ?? false) ||
                  (c.ruc?.toLowerCase().contains(q) ?? false) ||
                  (c.phone?.toLowerCase().contains(q) ?? false);
            }).toList();
          }

          if (customers.isEmpty) {
            return const Center(child: Text('No se encontraron clientes'));
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Nombre')),
                  DataColumn(label: Text('Cédula/RUC')),
                  DataColumn(label: Text('Teléfono')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Puntos'), numeric: true),
                  DataColumn(label: Text('Monedero'), numeric: true),
                  DataColumn(label: Text('Límite Crédito'), numeric: true),
                  DataColumn(label: Text('Acciones')),
                ],
                rows: customers.map((c) {
                  return DataRow(cells: [
                    DataCell(Text(c.name)),
                    DataCell(Text(c.ruc ?? c.cedula ?? '-')),
                    DataCell(Text(c.phone ?? '-')),
                    DataCell(Text(c.email ?? '-')),
                    DataCell(Text(c.loyaltyPoints.toString())),
                    DataCell(Text(c.walletBalance.currency)),
                    DataCell(Text(c.creditLimit.currency)),
                    DataCell(Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () =>
                              _showCustomerDialog(context, ref.read(appDatabaseProvider), customer: c),
                          tooltip: 'Editar',
                        ),
                        IconButton(
                          icon: const Icon(Icons.account_balance_wallet,
                              size: 18),
                          onPressed: () => _showWalletDialog(context, ref.read(appDatabaseProvider), c),
                          tooltip: 'Monedero',
                        ),
                        IconButton(
                          icon: const Icon(Icons.credit_card, size: 18),
                          onPressed: () {
                            _tabController.animateTo(1);
                          },
                          tooltip: 'Créditos',
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCreditsList(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<({CustomerCredit credit, String customerName})>>(
        stream: db.customersDao.watchPendingCreditsWithCustomer(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('No hay créditos pendientes'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final credit = item.credit;
              final isOverdue = credit.dueDate.isBefore(DateTime.now());
              return Card(
                color: isOverdue
                    ? AppColors.error.withValues(alpha: 0.05)
                    : null,
                child: ListTile(
                  leading: Icon(
                    isOverdue ? Icons.warning : Icons.receipt_long,
                    color: isOverdue ? AppColors.error : AppColors.info,
                  ),
                  title: Text(item.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      'Pendiente: ${credit.balance.currency} | Vence: ${credit.dueDate.formatted} | Total: ${credit.amount.currency}'),
                  trailing: ElevatedButton(
                    onPressed: () => _showPayCreditDialog(context, db, credit),
                    child: const Text('Abonar'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLoyaltyList(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<Customer>>(
        stream: db.customersDao.watchAllCustomers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final customers =
              snapshot.data!.where((c) => c.loyaltyPoints > 0).toList()
                ..sort((a, b) => b.loyaltyPoints.compareTo(a.loyaltyPoints));

          if (customers.isEmpty) {
            return const Center(
                child: Text('No hay clientes con puntos de lealtad'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: customers.length,
            itemBuilder: (context, index) {
              final c = customers[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text(c.name[0],
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(c.name),
                  subtitle: Text(
                      'Monedero: ${c.walletBalance.currency} | Puntos: ${c.loyaltyPoints}'),
                  trailing: Text('${c.loyaltyPoints} pts',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showCustomerDialog(BuildContext context, AppDatabase db,
      {Customer? customer}) {
    final nameCtrl = TextEditingController(text: customer?.name);
    final cedulaCtrl = TextEditingController(text: customer?.cedula);
    final rucCtrl = TextEditingController(text: customer?.ruc);
    final phoneCtrl = TextEditingController(text: customer?.phone);
    final emailCtrl = TextEditingController(text: customer?.email);
    final addressCtrl = TextEditingController(text: customer?.address);
    final creditLimitCtrl = TextEditingController(
        text: customer?.creditLimit.toStringAsFixed(2) ?? '0.00');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(customer == null ? 'Nuevo Cliente' : 'Editar Cliente'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nombre *')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                          controller: cedulaCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Cédula')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                          controller: rucCtrl,
                          decoration:
                              const InputDecoration(labelText: 'RUC')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                          controller: phoneCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Teléfono')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                          controller: emailCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Email')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: addressCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Dirección')),
                const SizedBox(height: 12),
                TextField(
                    controller: creditLimitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Límite de Crédito')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final now = DateTime.now();
              if (customer == null) {
                final id =
                    'cust_${now.millisecondsSinceEpoch}';
                await db.customersDao.insertCustomer(CustomersCompanion.insert(
                  id: id,
                  name: nameCtrl.text.trim(),
                  cedula: Value(cedulaCtrl.text.trim().isEmpty
                      ? null
                      : cedulaCtrl.text.trim()),
                  ruc: Value(rucCtrl.text.trim().isEmpty
                      ? null
                      : rucCtrl.text.trim()),
                  phone: Value(phoneCtrl.text.trim().isEmpty
                      ? null
                      : phoneCtrl.text.trim()),
                  email: Value(emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim()),
                  address: Value(addressCtrl.text.trim().isEmpty
                      ? null
                      : addressCtrl.text.trim()),
                  creditLimit: Value(
                      double.tryParse(creditLimitCtrl.text) ?? 0.0),
                ));
              } else {
                await db.customersDao.updateCustomer(CustomersCompanion(
                  id: Value(customer.id),
                  name: Value(nameCtrl.text.trim()),
                  cedula: Value(cedulaCtrl.text.trim().isEmpty
                      ? null
                      : cedulaCtrl.text.trim()),
                  ruc: Value(rucCtrl.text.trim().isEmpty
                      ? null
                      : rucCtrl.text.trim()),
                  phone: Value(phoneCtrl.text.trim().isEmpty
                      ? null
                      : phoneCtrl.text.trim()),
                  email: Value(emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim()),
                  address: Value(addressCtrl.text.trim().isEmpty
                      ? null
                      : addressCtrl.text.trim()),
                  creditLimit: Value(
                      double.tryParse(creditLimitCtrl.text) ?? 0.0),
                  updatedAt: Value(now),
                ));
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showWalletDialog(
      BuildContext context, AppDatabase db, Customer customer) {
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Monedero - ${customer.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Saldo actual: ${customer.walletBalance.currency}',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Monto a agregar', prefixText: r'$ '),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;
              await (db.update(db.customers)..where((c) => c.id.equals(customer.id))).write(
                CustomersCompanion(
                  walletBalance: Value(customer.walletBalance + amount),
                  updatedAt: Value(DateTime.now()),
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _showPayCreditDialog(
      BuildContext context, AppDatabase db, CustomerCredit credit) {
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abonar a Crédito'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Saldo pendiente: ${credit.balance.currency}',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Monto a abonar', prefixText: r'$ '),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0 || amount > credit.balance) return;
              await db.customersDao.registerCreditPayment(
                creditId: credit.id,
                customerId: credit.customerId,
                payment: CreditPaymentsCompanion.insert(
                  id: 'cp_${DateTime.now().millisecondsSinceEpoch}',
                  creditId: credit.id,
                  customerId: credit.customerId,
                  amount: amount,
                  receivedBy: 'admin',
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Abonar'),
          ),
        ],
      ),
    );
  }
}
