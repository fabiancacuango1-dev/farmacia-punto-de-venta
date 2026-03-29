import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';

class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
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
            Row(
              children: [
                const Text('Sucursales',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showBranchDialog(context, db),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nueva Sucursal'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showTransferDialog(context, db),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Transferir Inventario'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Sucursales'),
                Tab(text: 'Transferencias'),
                Tab(text: 'Devoluciones a Proveedores'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBranchesList(db),
                  _buildTransfersList(db),
                  _buildSupplierReturnsList(db),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchesList(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<Branche>>(
        stream: db.branchesDao.watchBranches(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final branches = snapshot.data!;
          if (branches.isEmpty) {
            return const Center(child: Text('No hay sucursales'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: branches.length,
            itemBuilder: (context, index) {
              final b = branches[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: b.isMain
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.info.withValues(alpha: 0.2),
                    child: Icon(
                      b.isMain ? Icons.store : Icons.storefront,
                      color: b.isMain ? AppColors.primary : AppColors.info,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(b.name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      if (b.isMain) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Principal',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.primary)),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                      '${b.address ?? "Sin dirección"} | ${b.phone ?? "Sin teléfono"}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: b.isActive
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(b.isActive ? 'Activa' : 'Inactiva',
                            style: TextStyle(
                                fontSize: 12,
                                color: b.isActive
                                    ? AppColors.success
                                    : AppColors.error)),
                      ),
                      if (!b.isMain) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () =>
                              _showBranchDialog(context, db, branch: b),
                          tooltip: 'Editar',
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTransfersList(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<BranchTransfer>>(
        stream: db.branchesDao.watchTransfers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final transfers = snapshot.data!;
          if (transfers.isEmpty) {
            return const Center(child: Text('No hay transferencias'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: transfers.length,
            itemBuilder: (context, index) {
              final t = transfers[index];
              final statusColor = switch (t.status) {
                'pending' => AppColors.warning,
                'in_transit' => AppColors.info,
                'received' => AppColors.success,
                'cancelled' => AppColors.error,
                _ => AppColors.textSecondaryLight,
              };

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.local_shipping, color: statusColor),
                  title: Text(
                      '${t.fromBranchId} → ${t.toBranchId}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      'Fecha: ${t.createdAt.formatted} | Estado: ${t.status}'),
                  trailing: t.status == 'pending'
                      ? ElevatedButton(
                          onPressed: () async {
                            await db.branchesDao
                                .receiveTransfer(t.id, 'admin');
                          },
                          child: const Text('Recibir'),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(t.status,
                              style: TextStyle(
                                  fontSize: 12, color: statusColor)),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSupplierReturnsList(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<SupplierReturn>>(
        stream: db.branchesDao.watchSupplierReturns(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final returns = snapshot.data!;
          if (returns.isEmpty) {
            return const Center(
                child: Text('No hay devoluciones a proveedores'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: returns.length,
            itemBuilder: (context, index) {
              final r = returns[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.assignment_return,
                      color: AppColors.warning),
                  title: Text('Devolución ${r.returnNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      'Motivo: ${r.reason} | Total: ${r.totalAmount.currency} | ${r.createdAt.formatted}'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (r.status == 'completed'
                              ? AppColors.success
                              : AppColors.warning)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                        r.status == 'completed' ? 'Completada' : 'Pendiente',
                        style: TextStyle(
                            fontSize: 12,
                            color: r.status == 'completed'
                                ? AppColors.success
                                : AppColors.warning)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showBranchDialog(BuildContext context, AppDatabase db,
      {Branche? branch}) {
    final nameCtrl = TextEditingController(text: branch?.name);
    final addressCtrl = TextEditingController(text: branch?.address);
    final phoneCtrl = TextEditingController(text: branch?.phone);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            branch == null ? 'Nueva Sucursal' : 'Editar Sucursal'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              if (branch == null) {
                final now = DateTime.now();
                await db.branchesDao.insertBranch(BranchesCompanion.insert(
                  id: 'branch_${now.millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  address: Value(addressCtrl.text.trim().isEmpty
                      ? null
                      : addressCtrl.text.trim()),
                  phone: Value(phoneCtrl.text.trim().isEmpty
                      ? null
                      : phoneCtrl.text.trim()),
                ));
              } else {
                await db.branchesDao.updateBranch(BranchesCompanion(
                  id: Value(branch.id),
                  name: Value(nameCtrl.text.trim()),
                  address: Value(addressCtrl.text.trim().isEmpty
                      ? null
                      : addressCtrl.text.trim()),
                  phone: Value(phoneCtrl.text.trim().isEmpty
                      ? null
                      : phoneCtrl.text.trim()),
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

  void _showTransferDialog(BuildContext context, AppDatabase db) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva Transferencia'),
        content: SizedBox(
          width: 500,
          child: FutureBuilder<List<Branche>>(
            future: db.branchesDao.getActiveBranches(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final branches = snap.data!;
              if (branches.length < 2) {
                return const Text(
                    'Necesita al menos 2 sucursales para transferir');
              }
              String? fromId = branches.first.id;
              String? toId = branches.length > 1 ? branches[1].id : null;

              return StatefulBuilder(
                builder: (context, setDialogState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: fromId,
                      decoration: const InputDecoration(
                          labelText: 'Sucursal Origen'),
                      items: branches
                          .map((b) => DropdownMenuItem(
                              value: b.id, child: Text(b.name)))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => fromId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: toId,
                      decoration: const InputDecoration(
                          labelText: 'Sucursal Destino'),
                      items: branches
                          .where((b) => b.id != fromId)
                          .map((b) => DropdownMenuItem(
                              value: b.id, child: Text(b.name)))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => toId = v),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Después de crear la transferencia, podrá agregar productos.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Transferencia creada')),
              );
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }
}
