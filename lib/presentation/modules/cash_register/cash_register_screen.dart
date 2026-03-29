import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';
import '../../../services/auth/auth_service.dart';

class CashRegisterScreen extends ConsumerStatefulWidget {
  const CashRegisterScreen({super.key});

  @override
  ConsumerState<CashRegisterScreen> createState() =>
      _CashRegisterScreenState();
}

class _CashRegisterScreenState extends ConsumerState<CashRegisterScreen> {
  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final user = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Control de Caja',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<CashRegister?>(
                stream: db.cashRegisterDao.watchOpenRegister(user.id),
                builder: (context, snapshot) {
                  final openRegister = snapshot.data;

                  if (openRegister == null) {
                    return _buildNoOpenRegister(context, db, user);
                  }

                  return _buildOpenRegister(context, db, openRegister);
                },
              ),
            ),
            const SizedBox(height: 20),
            // History
            const Text(
              'Historial de Cajas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: StreamBuilder<List<CashRegister>>(
                  stream: db.cashRegisterDao.watchRegisterHistory(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final registers = snapshot.data!;
                    if (registers.isEmpty) {
                      return const Center(child: Text('Sin historial'));
                    }

                    return SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Apertura')),
                          DataColumn(label: Text('Cierre')),
                          DataColumn(
                              label: Text('Monto Inicial'), numeric: true),
                          DataColumn(
                              label: Text('Total Ventas'), numeric: true),
                          DataColumn(
                              label: Text('Cierre Real'), numeric: true),
                          DataColumn(
                              label: Text('Diferencia'), numeric: true),
                          DataColumn(label: Text('Estado')),
                        ],
                        rows: registers.map((r) {
                          return DataRow(cells: [
                            DataCell(Text(r.openedAt.formattedWithTime)),
                            DataCell(Text(
                                r.closedAt?.formattedWithTime ?? '-')),
                            DataCell(Text(r.openingAmount.currency)),
                            DataCell(Text(r.totalSales.currency)),
                            DataCell(
                                Text(r.closingAmount?.currency ?? '-')),
                            DataCell(Text(
                              r.difference?.currency ?? '-',
                              style: TextStyle(
                                color: (r.difference ?? 0) >= 0
                                    ? AppColors.success
                                    : AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            )),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: r.status == 'open'
                                    ? AppColors.success
                                        .withValues(alpha: 0.1)
                                    : AppColors.borderLight
                                        .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                r.status == 'open' ? 'Abierta' : 'Cerrada',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: r.status == 'open'
                                      ? AppColors.success
                                      : Colors.grey,
                                ),
                              ),
                            )),
                          ]);
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoOpenRegister(
      BuildContext context, AppDatabase db, User user) {
    final openingController = TextEditingController();

    return Center(
      child: SingleChildScrollView(
        child: Card(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                const Icon(Icons.point_of_sale,
                    size: 64, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text(
                  'No hay caja abierta',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text('Abre una caja para comenzar a vender'),
                const SizedBox(height: 24),
                TextField(
                  controller: openingController,
                  decoration: const InputDecoration(
                    labelText: 'Monto Inicial',
                    prefixText: r'$ ',
                    hintText: '0.00',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final amount =
                          double.tryParse(openingController.text) ?? 0;
                      await db.cashRegisterDao.openRegister(
                        CashRegistersCompanion.insert(
                          id: const Uuid().v4(),
                          userId: user.id,
                          openingAmount: amount,
                        ),
                      );
                    },
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Abrir Caja'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildOpenRegister(
      BuildContext context, AppDatabase db, CashRegister register) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.circle,
                                size: 8, color: AppColors.success),
                            SizedBox(width: 6),
                            Text(
                              'CAJA ABIERTA',
                              style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Desde: ${register.openedAt.formattedWithTime}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _CashStat(
                      label: 'Monto Inicial',
                      value: register.openingAmount.currency,
                      icon: Icons.account_balance_wallet),
                  _CashStat(
                      label: 'Ventas del Turno',
                      value: register.totalSales.currency,
                      icon: Icons.trending_up,
                      color: AppColors.success),
                  _CashStat(
                      label: 'Transacciones',
                      value: register.salesCount.toString(),
                      icon: Icons.receipt),
                  const Divider(),
                  _CashStat(
                      label: 'Efectivo',
                      value: register.totalCash.currency,
                      icon: Icons.money),
                  _CashStat(
                      label: 'Tarjeta',
                      value: register.totalCard.currency,
                      icon: Icons.credit_card),
                  _CashStat(
                      label: 'Transferencia',
                      value: register.totalTransfer.currency,
                      icon: Icons.account_balance),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showCloseDialog(context, db, register),
                      icon: const Icon(Icons.lock),
                      label: const Text('Cerrar Caja'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Movimientos del Turno',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<List<CashMovement>>(
                      stream: db.cashRegisterDao
                          .watchMovementsForRegister(register.id),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(
                              child: Text('Sin movimientos'));
                        }

                        return ListView.builder(
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final m = snapshot.data![index];
                            return ListTile(
                              leading: Icon(
                                m.type == 'income'
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: m.type == 'income'
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                              title: Text(m.reason),
                              subtitle: Text(m.createdAt.formattedWithTime),
                              trailing: Text(
                                m.amount.currency,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: m.type == 'income'
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showCloseDialog(
      BuildContext context, AppDatabase db, CashRegister register) {
    final closingController = TextEditingController();
    final notesController = TextEditingController();
    final expected =
        register.openingAmount + register.totalCash;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Caja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Monto esperado: ${expected.currency}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: closingController,
              decoration: const InputDecoration(
                labelText: 'Monto Real en Caja',
                prefixText: r'$ ',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^\d+\.?\d{0,2}')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final closing =
                  double.tryParse(closingController.text) ?? 0;
              await db.cashRegisterDao.closeRegister(
                registerId: register.id,
                closingAmount: closing,
                expectedAmount: expected,
                totalSales: register.totalSales,
                totalCash: register.totalCash,
                totalCard: register.totalCard,
                totalTransfer: register.totalTransfer,
                salesCount: register.salesCount,
                notes: notesController.text.isEmpty
                    ? null
                    : notesController.text,
              );
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Cerrar Caja'),
          ),
        ],
      ),
    );
  }
}

class _CashStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _CashStat({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
