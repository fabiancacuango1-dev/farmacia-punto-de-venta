import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';
import '../../../services/auth/auth_service.dart';

/// Modelo local para items de la orden en construcción
class _OrderItem {
  final Product product;
  double quantity;
  double unitCost;
  String? batchNumber;
  DateTime? expirationDate;

  _OrderItem({
    required this.product,
    this.quantity = 1,
    double? unitCost,
  }) : unitCost = unitCost ?? product.costPrice;

  double get total => quantity * unitCost;
}

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _filterStatus = 'all';

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
            // Header
            Row(
              children: [
                Icon(Icons.shopping_cart, color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Gestión de Compras',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                // KPIs rápidos
                _QuickKPIs(db: db),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => context.go('/suppliers'),
                  icon: const Icon(Icons.local_shipping, size: 18),
                  label: const Text('Proveedores'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showNewOrderWizard(context, db),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nueva Orden de Compra'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Tabs
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.list_alt), text: 'Órdenes'),
                Tab(icon: Icon(Icons.pending_actions), text: 'Pendientes'),
                Tab(icon: Icon(Icons.analytics_outlined), text: 'Resumen'),
              ],
            ),
            const SizedBox(height: 12),
            // Filtros
            Row(
              children: [
                Text('Filtrar: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    )),
                const SizedBox(width: 8),
                ...[
                  ('all', 'Todas', Icons.clear_all, const Color(0xFF2563EB)),
                  ('draft', 'Borrador', Icons.edit_note, const Color(0xFF6366F1)),
                  ('ordered', 'Ordenadas', Icons.schedule, const Color(0xFFD97706)),
                  ('received', 'Recibidas', Icons.check_circle, const Color(0xFF059669)),
                  ('cancelled', 'Canceladas', Icons.cancel, const Color(0xFFDC2626)),
                ].map((f) {
                  final isSelected = _filterStatus == f.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(
                        f.$2,
                        style: TextStyle(
                          color: isSelected ? Colors.white : f.$4,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      avatar: Icon(f.$3, size: 16,
                          color: isSelected ? Colors.white : f.$4),
                      backgroundColor: f.$4.withValues(alpha: 0.08),
                      selectedColor: f.$4,
                      checkmarkColor: Colors.white,
                      side: BorderSide(
                        color: isSelected ? f.$4 : f.$4.withValues(alpha: 0.25),
                      ),
                      onSelected: (selected) =>
                          setState(() => _filterStatus = selected ? f.$1 : 'all'),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 12),
            // Contenido
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOrdersList(db),
                  _buildPendingOrders(db),
                  _buildPurchaseSummary(db),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Lista de todas las órdenes ──
  Widget _buildOrdersList(AppDatabase db) {
    return Card(
      child: FutureBuilder<List<PurchaseOrder>>(
        future: _filterStatus == 'all'
            ? db.purchasesDao.getPurchaseOrders()
            : db.purchasesDao.getPurchaseOrders(status: _filterStatus),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  const Text('No hay órdenes de compra',
                      style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showNewOrderWizard(context, db),
                    icon: const Icon(Icons.add),
                    label: const Text('Crear primera orden'),
                  ),
                ],
              ),
            );
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

              return SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('# Orden')),
                    DataColumn(label: Text('Proveedor')),
                    DataColumn(label: Text('Fecha')),
                    DataColumn(label: Text('Entrega Esperada')),
                    DataColumn(label: Text('Total'), numeric: true),
                    DataColumn(label: Text('Estado')),
                    DataColumn(label: Text('Acciones')),
                  ],
                  rows: orders.map((order) {
                    final supplier = supplierMap[order.supplierId];
                    return DataRow(cells: [
                      DataCell(Text(order.orderNumber,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(supplier?.name ?? 'Desconocido')),
                      DataCell(Text(order.createdAt.formatted)),
                      DataCell(Text(
                          order.expectedDate?.formatted ?? 'Sin fecha')),
                      DataCell(Text(order.total.currency,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(_StatusBadge(status: order.status)),
                      DataCell(_buildOrderActions(order, db)),
                    ]);
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderActions(PurchaseOrder order, AppDatabase db) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ver detalle
        IconButton(
          icon: const Icon(Icons.visibility, size: 18),
          tooltip: 'Ver detalle',
          onPressed: () => _showOrderDetail(context, db, order),
        ),
        // Marcar recibido
        if (order.status == 'ordered')
          IconButton(
            icon: const Icon(Icons.check_circle_outline,
                size: 18, color: AppColors.success),
            tooltip: 'Recibir mercadería',
            onPressed: () => _showReceiveDialog(context, db, order),
          ),
        // Cancelar
        if (order.status == 'draft' || order.status == 'ordered')
          IconButton(
            icon: const Icon(Icons.cancel_outlined,
                size: 18, color: AppColors.error),
            tooltip: 'Cancelar orden',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cancelar Orden'),
                  content: Text(
                      '¿Está seguro de cancelar la orden ${order.orderNumber}?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('No'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error),
                      child: const Text('Sí, cancelar'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await (db.update(db.purchaseOrders)
                      ..where((o) => o.id.equals(order.id)))
                    .write(PurchaseOrdersCompanion(
                  status: const Value('cancelled'),
                  updatedAt: Value(DateTime.now()),
                ));
                setState(() {});
              }
            },
          ),
      ],
    );
  }

  // ── Tab 2: Órdenes pendientes ──
  Widget _buildPendingOrders(AppDatabase db) {
    return Card(
      child: FutureBuilder<List<PurchaseOrder>>(
        future: db.purchasesDao.getPurchaseOrders(status: 'ordered'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: AppColors.success),
                  SizedBox(height: 16),
                  Text('No hay órdenes pendientes de recepción',
                      style: TextStyle(fontSize: 16)),
                ],
              ),
            );
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
                  final isLate = order.expectedDate != null &&
                      order.expectedDate!.isBefore(DateTime.now());

                  return Card(
                    color: isLate
                        ? AppColors.error.withValues(alpha: 0.05)
                        : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isLate
                            ? AppColors.error.withValues(alpha: 0.1)
                            : AppColors.info.withValues(alpha: 0.1),
                        child: Icon(
                          isLate ? Icons.warning : Icons.local_shipping,
                          color: isLate ? AppColors.error : AppColors.info,
                        ),
                      ),
                      title: Text(
                        'Orden ${order.orderNumber} - ${supplier?.name ?? ""}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        isLate
                            ? 'RETRASADA - Esperada: ${order.expectedDate!.formatted}'
                            : 'Esperada: ${order.expectedDate?.formatted ?? "Sin fecha"}',
                        style: TextStyle(
                            color: isLate ? AppColors.error : null),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(order.total.currency,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _showReceiveDialog(context, db, order),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Recibir'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                            ),
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

  // ── Tab 3: Resumen de compras ──
  Widget _buildPurchaseSummary(AppDatabase db) {
    return Card(
      child: FutureBuilder<List<PurchaseOrder>>(
        future: db.purchasesDao.getPurchaseOrders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!;
          final now = DateTime.now();
          final thisMonth = orders.where((o) =>
              o.createdAt.month == now.month && o.createdAt.year == now.year);
          final received =
              orders.where((o) => o.status == 'received');
          final pending =
              orders.where((o) => o.status == 'ordered');

          final totalThisMonth =
              thisMonth.fold<double>(0, (sum, o) => sum + o.total);
          final totalReceived =
              received.fold<double>(0, (sum, o) => sum + o.total);

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Resumen de Compras',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                // KPIs
                Row(
                  children: [
                    _SummaryCard(
                      icon: Icons.calendar_today,
                      color: AppColors.primary,
                      title: 'Este Mes',
                      value: totalThisMonth.currency,
                      subtitle: '${thisMonth.length} órdenes',
                    ),
                    const SizedBox(width: 16),
                    _SummaryCard(
                      icon: Icons.check_circle,
                      color: AppColors.success,
                      title: 'Total Recibido',
                      value: totalReceived.currency,
                      subtitle: '${received.length} órdenes',
                    ),
                    const SizedBox(width: 16),
                    _SummaryCard(
                      icon: Icons.pending,
                      color: AppColors.warning,
                      title: 'Pendientes',
                      value: pending
                          .fold<double>(0, (sum, o) => sum + o.total)
                          .currency,
                      subtitle: '${pending.length} órdenes',
                    ),
                    const SizedBox(width: 16),
                    _SummaryCard(
                      icon: Icons.inventory_2,
                      color: AppColors.info,
                      title: 'Total Histórico',
                      value: orders
                          .fold<double>(0, (sum, o) => sum + o.total)
                          .currency,
                      subtitle: '${orders.length} órdenes totales',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Wizard para crear nueva orden ──
  void _showNewOrderWizard(BuildContext context, AppDatabase db) {
    Supplier? selectedSupplier;
    final items = <_OrderItem>[];
    final notesCtrl = TextEditingController();
    DateTime? expectedDate;
    final productSearchCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add_shopping_cart,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      const Text('Nueva Orden de Compra',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  // Paso 1: Seleccionar proveedor
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: FutureBuilder<List<Supplier>>(
                          future: db.purchasesDao.getAllSuppliers(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const LinearProgressIndicator();
                            }
                            return DropdownButtonFormField<Supplier>(
                              value: selectedSupplier,
                              decoration: const InputDecoration(
                                labelText: 'Proveedor *',
                                prefixIcon: Icon(Icons.local_shipping),
                              ),
                              items: snapshot.data!
                                  .map((s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s.name),
                                      ))
                                  .toList(),
                              onChanged: (s) =>
                                  setDialogState(() => selectedSupplier = s),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: ctx,
                              initialDate:
                                  DateTime.now().add(const Duration(days: 3)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              setDialogState(() => expectedDate = date);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Fecha entrega esperada',
                              prefixIcon: Icon(Icons.calendar_today),
                            ),
                            child: Text(
                                expectedDate?.formatted ?? 'Seleccionar'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Búsqueda de productos
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: productSearchCtrl,
                          decoration: const InputDecoration(
                            hintText:
                                'Buscar producto por nombre o código de barras...',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onSubmitted: (query) async {
                            if (query.trim().isEmpty) return;
                            final results =
                                await db.productsDao.searchProducts(query);
                            if (!ctx.mounted) return;
                            if (results.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('No se encontraron productos')),
                              );
                              return;
                            }
                            // Mostrar selector de producto
                            final selected = await showDialog<Product>(
                              context: ctx,
                              builder: (dialogCtx) => AlertDialog(
                                title: const Text('Seleccionar Producto'),
                                content: SizedBox(
                                  width: 500,
                                  height: 300,
                                  child: ListView.builder(
                                    itemCount: results.length,
                                    itemBuilder: (_, i) {
                                      final p = results[i];
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: AppColors.primary
                                              .withValues(alpha: 0.1),
                                          child: const Icon(Icons.medication,
                                              color: AppColors.primary,
                                              size: 20),
                                        ),
                                        title: Text(p.name),
                                        subtitle: Text(
                                            '${p.barcode ?? "Sin código"} | Stock: ${p.currentStock.toStringAsFixed(0)} | Costo: ${p.costPrice.currency}'),
                                        onTap: () =>
                                            Navigator.pop(dialogCtx, p),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                            if (selected != null) {
                              setDialogState(() {
                                // Verificar si ya existe en la lista
                                final existing = items.indexWhere(
                                    (i) => i.product.id == selected.id);
                                if (existing >= 0) {
                                  items[existing].quantity += 1;
                                } else {
                                  items.add(_OrderItem(product: selected));
                                }
                              });
                              productSearchCtrl.clear();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Lista de items
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_box_outlined,
                                    size: 48,
                                    color: Theme.of(ctx)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withValues(alpha: 0.3)),
                                const SizedBox(height: 12),
                                const Text(
                                  'Busca productos para agregarlos a la orden',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: DataTable(
                              columnSpacing: 12,
                              columns: const [
                                DataColumn(label: Text('Producto')),
                                DataColumn(
                                    label: Text('Cantidad'), numeric: true),
                                DataColumn(
                                    label: Text('Costo Unit.'), numeric: true),
                                DataColumn(
                                    label: Text('Subtotal'), numeric: true),
                                DataColumn(label: Text('Lote')),
                                DataColumn(label: Text('Vencimiento')),
                                DataColumn(label: Text('')),
                              ],
                              rows: items.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final item = entry.value;
                                return DataRow(cells: [
                                  DataCell(SizedBox(
                                    width: 180,
                                    child: Text(item.product.name,
                                        overflow: TextOverflow.ellipsis),
                                  )),
                                  DataCell(SizedBox(
                                    width: 60,
                                    child: TextFormField(
                                      initialValue:
                                          item.quantity.toStringAsFixed(0),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      onChanged: (v) => setDialogState(() {
                                        item.quantity =
                                            double.tryParse(v) ?? 1;
                                      }),
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                      ),
                                    ),
                                  )),
                                  DataCell(SizedBox(
                                    width: 80,
                                    child: TextFormField(
                                      initialValue:
                                          item.unitCost.toStringAsFixed(2),
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) => setDialogState(() {
                                        item.unitCost =
                                            double.tryParse(v) ?? 0;
                                      }),
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                        prefixText: r'$',
                                      ),
                                    ),
                                  )),
                                  DataCell(Text(item.total.currency,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600))),
                                  DataCell(SizedBox(
                                    width: 90,
                                    child: TextFormField(
                                      initialValue: item.batchNumber ?? '',
                                      onChanged: (v) =>
                                          item.batchNumber = v.isEmpty ? null : v,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        hintText: 'Lote',
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                      ),
                                    ),
                                  )),
                                  DataCell(InkWell(
                                    onTap: () async {
                                      final date = await showDatePicker(
                                        context: ctx,
                                        initialDate: item.expirationDate ??
                                            DateTime.now().add(
                                                const Duration(days: 365)),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now()
                                            .add(const Duration(days: 3650)),
                                      );
                                      if (date != null) {
                                        setDialogState(() =>
                                            item.expirationDate = date);
                                      }
                                    },
                                    child: Text(
                                      item.expirationDate?.formatted ??
                                          'Seleccionar',
                                      style: TextStyle(
                                        color: item.expirationDate == null
                                            ? Colors.grey
                                            : null,
                                      ),
                                    ),
                                  )),
                                  DataCell(IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18, color: AppColors.error),
                                    onPressed: () => setDialogState(
                                        () => items.removeAt(idx)),
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                  ),
                  // Notas
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Notas de la orden (opcional)',
                      prefixIcon: Icon(Icons.note),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Footer con totales y acciones
                  Row(
                    children: [
                      // Totales
                      Card(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Text(
                                '${items.length} productos',
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(width: 24),
                              Text(
                                'Subtotal: ${items.fold<double>(0, (sum, i) => sum + i.total).currency}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'IVA 15%: ${(items.fold<double>(0, (sum, i) => sum + i.total) * 0.15).currency}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'TOTAL: ${(items.fold<double>(0, (sum, i) => sum + i.total) * 1.15).currency}',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      // Guardar como borrador
                      OutlinedButton.icon(
                        onPressed: selectedSupplier == null || items.isEmpty
                            ? null
                            : () async {
                                await _saveOrder(
                                  db: db,
                                  supplier: selectedSupplier!,
                                  items: items,
                                  notes: notesCtrl.text,
                                  expectedDate: expectedDate,
                                  status: 'draft',
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                setState(() {});
                              },
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Guardar Borrador'),
                      ),
                      const SizedBox(width: 8),
                      // Confirmar orden
                      ElevatedButton.icon(
                        onPressed: selectedSupplier == null || items.isEmpty
                            ? null
                            : () async {
                                await _saveOrder(
                                  db: db,
                                  supplier: selectedSupplier!,
                                  items: items,
                                  notes: notesCtrl.text,
                                  expectedDate: expectedDate,
                                  status: 'ordered',
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                setState(() {});
                              },
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Confirmar Orden'),
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

  Future<void> _saveOrder({
    required AppDatabase db,
    required Supplier supplier,
    required List<_OrderItem> items,
    required String notes,
    required DateTime? expectedDate,
    required String status,
  }) async {
    final now = DateTime.now();
    final orderId = 'po_${now.millisecondsSinceEpoch}';
    final orderNumber =
        'OC-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch % 10000}';

    final subtotal = items.fold<double>(0, (sum, i) => sum + i.total);
    final tax = subtotal * 0.15;
    final total = subtotal + tax;

    final currentUser = ref.read(currentUserProvider);

    final orderCompanion = PurchaseOrdersCompanion.insert(
      id: orderId,
      orderNumber: orderNumber,
      supplierId: supplier.id,
      createdBy: currentUser?.id ?? 'admin',
      subtotal: Value(subtotal),
      taxAmount: Value(tax),
      total: Value(total),
      status: Value(status),
      notes: Value(notes.isEmpty ? null : notes),
      expectedDate: Value(expectedDate),
    );

    final itemCompanions = items.asMap().entries.map((entry) {
      final item = entry.value;
      return PurchaseOrderItemsCompanion.insert(
        id: '${orderId}_item_${entry.key}',
        purchaseOrderId: orderId,
        productId: item.product.id,
        productName: Value(item.product.name),
        quantity: item.quantity,
        unitCost: item.unitCost,
        total: item.total,
        batchNumber: Value(item.batchNumber),
        expirationDate: Value(item.expirationDate),
      );
    }).toList();

    await db.purchasesDao.createPurchaseOrder(
      order: orderCompanion,
      items: itemCompanions,
    );
  }

  void _showOrderDetail(
      BuildContext context, AppDatabase db, PurchaseOrder order) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Text('Orden ${order.orderNumber}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    _StatusBadge(status: order.status),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Text('Fecha: ${order.createdAt.formatted}'),
                    const SizedBox(width: 24),
                    Text(
                        'Entrega: ${order.expectedDate?.formatted ?? "Sin fecha"}'),
                    const Spacer(),
                    Text('Total: ${order.total.currency}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: FutureBuilder<List<PurchaseOrderItem>>(
                    future: db.purchasesDao.getOrderItems(order.id),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final items = snapshot.data!;
                      return SingleChildScrollView(
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Producto')),
                            DataColumn(
                                label: Text('Cantidad'), numeric: true),
                            DataColumn(
                                label: Text('Costo Unit.'), numeric: true),
                            DataColumn(
                                label: Text('Total'), numeric: true),
                            DataColumn(label: Text('Lote')),
                            DataColumn(label: Text('Recibido'),
                                numeric: true),
                          ],
                          rows: items.map((item) {
                            return DataRow(cells: [
                              DataCell(Text(item.productName)),
                              DataCell(Text(
                                  item.quantity.toStringAsFixed(0))),
                              DataCell(Text(item.unitCost.currency)),
                              DataCell(Text(item.total.currency)),
                              DataCell(
                                  Text(item.batchNumber ?? '-')),
                              DataCell(Text(
                                  item.receivedQuantity.toStringAsFixed(0))),
                            ]);
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
                if (order.notes != null && order.notes!.isNotEmpty) ...[
                  const Divider(),
                  Text('Notas: ${order.notes}',
                      style: const TextStyle(fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReceiveDialog(
      BuildContext context, AppDatabase db, PurchaseOrder order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recibir Orden ${order.orderNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: ${order.total.currency}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text(
              'Al confirmar la recepción:\n'
              '• Se actualizará el stock de cada producto\n'
              '• Se crearán lotes con fechas de vencimiento\n'
              '• Se actualizarán los precios de costo',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await db.purchasesDao.receivePurchaseOrder(order.id);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {});
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Orden ${order.orderNumber} recibida exitosamente'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Confirmar Recepción'),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          ),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ──

class _QuickKPIs extends StatelessWidget {
  final AppDatabase db;
  const _QuickKPIs({required this.db});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PurchaseOrder>>(
      future: db.purchasesDao.getPurchaseOrders(status: 'ordered'),
      builder: (context, snapshot) {
        final pending = snapshot.data?.length ?? 0;
        if (pending == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pending_actions,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 6),
              Text(
                '$pending pendientes',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;

  const _SummaryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 12),
              Text(value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: color,
                  )),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
