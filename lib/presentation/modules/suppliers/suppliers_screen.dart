import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen>
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
            // Header con gradiente farmacéutico
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.secondary,
                    AppColors.secondary.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppShadows.md,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_shipping,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gestión de Proveedores',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        StreamBuilder<List<Supplier>>(
                          stream: db.purchasesDao.watchSuppliers(),
                          builder: (context, snapshot) {
                            final count = snapshot.data?.length ?? 0;
                            return Text(
                              '$count proveedores activos',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showSupplierForm(context, db),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nuevo Proveedor',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Tabs
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.list), text: 'Directorio'),
                Tab(icon: Icon(Icons.star_outline), text: 'Favoritos'),
                Tab(icon: Icon(Icons.history), text: 'Historial Compras'),
              ],
            ),
            const SizedBox(height: 12),
            // Búsqueda
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText:
                    'Buscar por nombre, RUC, contacto, teléfono...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 12),
            // Contenido
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSuppliersDirectory(db),
                  _buildFavoriteSuppliers(db),
                  _buildPurchaseHistory(db),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Directorio completo de proveedores ──
  Widget _buildSuppliersDirectory(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<Supplier>>(
        stream: db.purchasesDao.watchSuppliers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var suppliers = snapshot.data!;
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            suppliers = suppliers.where((s) {
              return s.name.toLowerCase().contains(q) ||
                  (s.ruc?.toLowerCase().contains(q) ?? false) ||
                  (s.contactPerson?.toLowerCase().contains(q) ?? false) ||
                  (s.phone?.toLowerCase().contains(q) ?? false) ||
                  (s.email?.toLowerCase().contains(q) ?? false) ||
                  (s.city?.toLowerCase().contains(q) ?? false);
            }).toList();
          }

          if (suppliers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_shipping_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'No se encontraron proveedores'
                        : 'No hay proveedores registrados',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  if (_searchQuery.isEmpty) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showSupplierForm(context, db),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar primer proveedor'),
                    ),
                  ],
                ],
              ),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Empresa')),
                  DataColumn(label: Text('RUC')),
                  DataColumn(label: Text('Contacto')),
                  DataColumn(label: Text('Teléfono')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Ciudad')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Acciones')),
                ],
                rows: suppliers.map((s) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  AppColors.secondary.withValues(alpha: 0.1),
                              child: Text(
                                s.name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(s.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DataCell(Text(s.ruc ?? '-')),
                      DataCell(Text(s.contactPerson ?? '-')),
                      DataCell(
                        s.phone != null
                            ? InkWell(
                                onTap: () {},
                                child: Text(s.phone!,
                                    style: const TextStyle(
                                        color: AppColors.primary)),
                              )
                            : const Text('-'),
                      ),
                      DataCell(Text(s.email ?? '-')),
                      DataCell(Text(s.city ?? '-')),
                      DataCell(_SupplierStatusBadge(isActive: s.isActive)),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: 'Editar',
                            onPressed: () =>
                                _showSupplierForm(context, db, supplier: s),
                          ),
                          IconButton(
                            icon: const Icon(Icons.shopping_cart_outlined,
                                size: 18),
                            tooltip: 'Nueva orden de compra',
                            onPressed: () => _createPurchaseOrder(context, db, s),
                          ),
                          IconButton(
                            icon: Icon(
                              s.isActive
                                  ? Icons.block_outlined
                                  : Icons.check_circle_outline,
                              size: 18,
                            ),
                            tooltip:
                                s.isActive ? 'Desactivar' : 'Reactivar',
                            onPressed: () async {
                              await db.purchasesDao.updateSupplier(
                                SuppliersCompanion(
                                  id: Value(s.id),
                                  isActive: Value(!s.isActive),
                                  updatedAt: Value(DateTime.now()),
                                ),
                              );
                            },
                          ),
                        ],
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Tab 2: Proveedores favoritos / más usados ──
  Widget _buildFavoriteSuppliers(AppDatabase db) {
    return Card(
      child: FutureBuilder<List<PurchaseOrder>>(
        future: db.purchasesDao.getPurchaseOrders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Contar compras por proveedor
          final ordersBySupplier = <String, int>{};
          final totalBySupplier = <String, double>{};
          for (final order in snapshot.data!) {
            ordersBySupplier[order.supplierId] =
                (ordersBySupplier[order.supplierId] ?? 0) + 1;
            totalBySupplier[order.supplierId] =
                (totalBySupplier[order.supplierId] ?? 0) + order.total;
          }

          if (ordersBySupplier.isEmpty) {
            return const Center(
              child: Text('Aún no hay órdenes de compra registradas'),
            );
          }

          final sortedSuppliers = ordersBySupplier.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return FutureBuilder<List<Supplier>>(
            future: db.purchasesDao.getAllSuppliers(activeOnly: false),
            builder: (context, suppSnapshot) {
              if (!suppSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final supplierMap = {
                for (final s in suppSnapshot.data!) s.id: s
              };

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sortedSuppliers.length,
                itemBuilder: (context, index) {
                  final entry = sortedSuppliers[index];
                  final supplier = supplierMap[entry.key];
                  if (supplier == null) return const SizedBox.shrink();

                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _rankColor(index),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(supplier.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${entry.value} órdenes | Total: ${totalBySupplier[entry.key]?.currency ?? '\$0.00'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            supplier.phone ?? '',
                            style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.shopping_cart_outlined),
                            tooltip: 'Nueva orden',
                            onPressed: () =>
                                _createPurchaseOrder(context, db, supplier),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ── Tab 3: Historial de compras recientes ──
  Widget _buildPurchaseHistory(AppDatabase db) {
    return Card(
      child: FutureBuilder<List<PurchaseOrder>>(
        future: db.purchasesDao.getPurchaseOrders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return const Center(
                child: Text('No hay historial de compras'));
          }

          return FutureBuilder<List<Supplier>>(
            future: db.purchasesDao.getAllSuppliers(activeOnly: false),
            builder: (context, suppSnapshot) {
              if (!suppSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final supplierMap = {
                for (final s in suppSnapshot.data!) s.id: s
              };

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final supplier = supplierMap[order.supplierId];

                  return Card(
                    child: ExpansionTile(
                      leading: _OrderStatusIcon(status: order.status),
                      title: Text(
                        'Orden ${order.orderNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${supplier?.name ?? 'Proveedor desconocido'} | ${order.createdAt.formatted}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            order.total.currency,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          _OrderStatusBadge(status: order.status),
                        ],
                      ),
                      children: [
                        FutureBuilder<List<PurchaseOrderItem>>(
                          future: db.purchasesDao.getOrderItems(order.id),
                          builder: (context, itemsSnapshot) {
                            if (!itemsSnapshot.hasData) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              );
                            }
                            final items = itemsSnapshot.data!;
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  ...items.map((item) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Row(
                                          children: [
                                            Expanded(
                                                flex: 3,
                                                child: Text(item.productName)),
                                            Expanded(
                                                child: Text(
                                                    'x${item.quantity}',
                                                    textAlign:
                                                        TextAlign.center)),
                                            Expanded(
                                                child: Text(
                                                    item.unitCost.currency,
                                                    textAlign:
                                                        TextAlign.right)),
                                            Expanded(
                                                child: Text(
                                                    (item.quantity *
                                                            item.unitCost)
                                                        .currency,
                                                    textAlign:
                                                        TextAlign.right,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600))),
                                          ],
                                        ),
                                      )),
                                  const Divider(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (order.status == 'ordered')
                                        ElevatedButton.icon(
                                          onPressed: () async {
                                            await db.purchasesDao
                                                .receivePurchaseOrder(
                                                    order.id);
                                            setState(() {});
                                          },
                                          icon: const Icon(
                                              Icons.check_circle, size: 18),
                                          label: const Text(
                                              'Marcar Recibido'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.success,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ── Formulario de proveedor ──
  void _showSupplierForm(BuildContext context, AppDatabase db,
      {Supplier? supplier}) {
    final nameCtrl = TextEditingController(text: supplier?.name);
    final rucCtrl = TextEditingController(text: supplier?.ruc);
    final contactCtrl = TextEditingController(text: supplier?.contactPerson);
    final emailCtrl = TextEditingController(text: supplier?.email);
    final phoneCtrl = TextEditingController(text: supplier?.phone);
    final addressCtrl = TextEditingController(text: supplier?.address);
    final cityCtrl = TextEditingController(text: supplier?.city);
    final notesCtrl = TextEditingController(text: supplier?.notes);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header del diálogo
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          supplier == null ? Icons.person_add : Icons.edit,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        supplier == null
                            ? 'Nuevo Proveedor'
                            : 'Editar Proveedor',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Formulario
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // Nombre de empresa
                          TextFormField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nombre de la Empresa *',
                              prefixIcon: Icon(Icons.business),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'El nombre es obligatorio'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          // RUC y Contacto
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: rucCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'RUC',
                                    prefixIcon: Icon(Icons.badge),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: contactCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Persona de Contacto',
                                    prefixIcon: Icon(Icons.person),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Teléfono y Email
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: phoneCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Teléfono',
                                    prefixIcon: Icon(Icons.phone),
                                  ),
                                  keyboardType: TextInputType.phone,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: emailCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.email),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Dirección y Ciudad
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: addressCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Dirección',
                                    prefixIcon: Icon(Icons.location_on),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: cityCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Ciudad',
                                    prefixIcon: Icon(Icons.location_city),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Notas
                          TextFormField(
                            controller: notesCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Notas / Observaciones',
                              prefixIcon: Icon(Icons.note),
                              alignLabelWithHint: true,
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Botones
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          final now = DateTime.now();

                          if (supplier == null) {
                            final id =
                                'sup_${now.millisecondsSinceEpoch}';
                            await db.purchasesDao.insertSupplier(
                              SuppliersCompanion.insert(
                                id: id,
                                name: nameCtrl.text.trim(),
                                ruc: Value(rucCtrl.text.trim().isEmpty
                                    ? null
                                    : rucCtrl.text.trim()),
                                contactPerson: Value(
                                    contactCtrl.text.trim().isEmpty
                                        ? null
                                        : contactCtrl.text.trim()),
                                email: Value(emailCtrl.text.trim().isEmpty
                                    ? null
                                    : emailCtrl.text.trim()),
                                phone: Value(phoneCtrl.text.trim().isEmpty
                                    ? null
                                    : phoneCtrl.text.trim()),
                                address: Value(addressCtrl.text.trim().isEmpty
                                    ? null
                                    : addressCtrl.text.trim()),
                                city: Value(cityCtrl.text.trim().isEmpty
                                    ? null
                                    : cityCtrl.text.trim()),
                                notes: Value(notesCtrl.text.trim().isEmpty
                                    ? null
                                    : notesCtrl.text.trim()),
                              ),
                            );
                          } else {
                            await db.purchasesDao.updateSupplier(
                              SuppliersCompanion(
                                id: Value(supplier.id),
                                name: Value(nameCtrl.text.trim()),
                                ruc: Value(rucCtrl.text.trim().isEmpty
                                    ? null
                                    : rucCtrl.text.trim()),
                                contactPerson: Value(
                                    contactCtrl.text.trim().isEmpty
                                        ? null
                                        : contactCtrl.text.trim()),
                                email: Value(emailCtrl.text.trim().isEmpty
                                    ? null
                                    : emailCtrl.text.trim()),
                                phone: Value(phoneCtrl.text.trim().isEmpty
                                    ? null
                                    : phoneCtrl.text.trim()),
                                address: Value(addressCtrl.text.trim().isEmpty
                                    ? null
                                    : addressCtrl.text.trim()),
                                city: Value(cityCtrl.text.trim().isEmpty
                                    ? null
                                    : cityCtrl.text.trim()),
                                notes: Value(notesCtrl.text.trim().isEmpty
                                    ? null
                                    : notesCtrl.text.trim()),
                                updatedAt: Value(now),
                              ),
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Guardar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _createPurchaseOrder(
      BuildContext context, AppDatabase db, Supplier supplier) {
    // Navegar a compras con el proveedor preseleccionado
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Crear orden de compra para ${supplier.name}'),
        action: SnackBarAction(
          label: 'Ir a Compras',
          onPressed: () {
            // TODO: Navigate with supplier context
          },
        ),
      ),
    );
  }

  Color _rankColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFFFD700); // Gold
      case 1:
        return const Color(0xFFC0C0C0); // Silver
      case 2:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return AppColors.secondary;
    }
  }
}

class _SupplierStatusBadge extends StatelessWidget {
  final bool isActive;
  const _SupplierStatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (isActive ? AppColors.success : AppColors.error)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Activo' : 'Inactivo',
        style: TextStyle(
          fontSize: 12,
          color: isActive ? AppColors.success : AppColors.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OrderStatusIcon extends StatelessWidget {
  final String status;
  const _OrderStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (status) {
      'draft' => (Icons.edit_note, Colors.grey),
      'ordered' => (Icons.schedule, AppColors.info),
      'received' => (Icons.check_circle, AppColors.success),
      'cancelled' => (Icons.cancel, AppColors.error),
      _ => (Icons.help_outline, Colors.grey),
    };

    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  final String status;
  const _OrderStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      'draft' => ('Borrador', Colors.grey),
      'ordered' => ('Ordenado', AppColors.info),
      'received' => ('Recibido', AppColors.success),
      'cancelled' => ('Cancelado', AppColors.error),
      _ => ('Desconocido', Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
