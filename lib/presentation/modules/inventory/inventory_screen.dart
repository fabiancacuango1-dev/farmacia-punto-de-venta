import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/daos/inventory_dao.dart';
import '../../../services/auth/auth_service.dart';
import '../../../services/inventory/inventory_service.dart';

// ══════════════════════════════════════════════════
// ── MAIN INVENTORY SCREEN ──
// ══════════════════════════════════════════════════

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Column(
        children: [
          // ── Top Header Bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                const Icon(Icons.inventory_2,
                    color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Inventario Inteligente',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _AlertBadge(),
                const SizedBox(width: 8),
                _ActionButtons(tabController: _tabController),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Tab Bar ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor:
                  isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(
                    icon: Icon(Icons.dashboard_outlined, size: 18),
                    text: 'Dashboard'),
                Tab(
                    icon: Icon(Icons.swap_vert, size: 18),
                    text: 'Movimientos'),
                Tab(
                    icon: Icon(Icons.fact_check_outlined, size: 18),
                    text: 'Conteo Físico'),
                Tab(
                    icon: Icon(Icons.view_timeline_outlined, size: 18),
                    text: 'Lotes & FIFO'),
                Tab(
                    icon: Icon(Icons.notifications_active_outlined, size: 18),
                    text: 'Alertas'),
                Tab(
                    icon: Icon(Icons.auto_awesome_outlined, size: 18),
                    text: 'Sugerencias IA'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Tab Content ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _DashboardTab(),
                _MovementsTab(),
                _PhysicalCountTab(),
                _BatchesFifoTab(),
                _AlertsTab(),
                _SuggestionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// ── ALERT BADGE (top bar) ──
// ══════════════════════════════════════════════════

class _AlertBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<int>(
      stream: db.inventoryDao.watchUnreadAlertCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Alertas de inventario',
            onPressed: () {},
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════
// ── ACTION BUTTONS (top bar) ──
// ══════════════════════════════════════════════════

class _ActionButtons extends ConsumerWidget {
  final TabController tabController;
  const _ActionButtons({required this.tabController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () => _generateAlerts(context, ref),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Escanear'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => _takeSnapshot(context, ref),
          icon: const Icon(Icons.camera_alt_outlined, size: 16),
          label: const Text('Snapshot'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  Future<void> _generateAlerts(BuildContext context, WidgetRef ref) async {
    final service = ref.read(inventoryServiceProvider);
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final count = await service.generateAlerts(user.id);
    final sugCount = await service.generatePurchaseSuggestions();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Escaneo completo: $count alertas, $sugCount sugerencias generadas'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Future<void> _takeSnapshot(BuildContext context, WidgetRef ref) async {
    final service = ref.read(inventoryServiceProvider);
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    await service.takeSnapshot(userId: user.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Snapshot de inventario creado exitosamente'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

// ══════════════════════════════════════════════════
// ── TAB 1: DASHBOARD ──
// ══════════════════════════════════════════════════

class _DashboardTab extends ConsumerStatefulWidget {
  const _DashboardTab();

  @override
  ConsumerState<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<_DashboardTab> {
  late Future<Map<String, dynamic>> _kpiFuture;

  @override
  void initState() {
    super.initState();
    _kpiFuture = ref.read(inventoryServiceProvider).getDashboardKPIs();
  }

  void _refresh() {
    setState(() {
      _kpiFuture = ref.read(inventoryServiceProvider).getDashboardKPIs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(appDatabaseProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<Map<String, dynamic>>(
      future: _kpiFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final valuation = data['valuation'] as InventoryValuation;
        final stockStatus = data['stockStatus'] as Map<String, int>;
        final categories =
            data['categories'] as List<Map<String, dynamic>>;
        final movements =
            data['movementsThisMonth'] as Map<String, int>;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── KPI Cards Row ──
              Row(
                children: [
                  Expanded(
                      child: _KpiCard(
                    icon: Icons.inventory_2,
                    title: 'Total Productos',
                    value: '${valuation.totalProducts}',
                    color: AppColors.primary,
                    isDark: isDark,
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _KpiCard(
                    icon: Icons.all_inbox,
                    title: 'Total Unidades',
                    value: NumberFormat('#,##0').format(valuation.totalUnits),
                    color: AppColors.info,
                    isDark: isDark,
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _KpiCard(
                    icon: Icons.attach_money,
                    title: 'Valor Costo',
                    value: valuation.totalCostValue.currency,
                    color: AppColors.secondary,
                    isDark: isDark,
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _KpiCard(
                    icon: Icons.trending_up,
                    title: 'Valor Venta',
                    value: valuation.totalSaleValue.currency,
                    color: AppColors.success,
                    isDark: isDark,
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _KpiCard(
                    icon: Icons.savings,
                    title: 'Ganancia Potencial',
                    value: valuation.potentialProfit.currency,
                    subtitle:
                        '${((valuation.potentialProfit / (valuation.totalCostValue == 0 ? 1 : valuation.totalCostValue)) * 100).toStringAsFixed(1)}% margen',
                    color: AppColors.accent,
                    isDark: isDark,
                  )),
                ],
              ),
              const SizedBox(height: 16),

              // ── Stock Status + Category Breakdown ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stock Status
                  Expanded(
                    flex: 2,
                    child: _DashboardCard(
                      title: 'Estado del Stock',
                      isDark: isDark,
                      child: Column(
                        children: [
                          _StockStatusRow(
                            label: 'Sin Stock',
                            count: stockStatus['out_of_stock'] ?? 0,
                            color: AppColors.error,
                            icon: Icons.dangerous,
                          ),
                          _StockStatusRow(
                            label: 'Stock Bajo',
                            count: stockStatus['low_stock'] ?? 0,
                            color: AppColors.warning,
                            icon: Icons.warning_amber,
                          ),
                          _StockStatusRow(
                            label: 'Normal',
                            count: stockStatus['normal'] ?? 0,
                            color: AppColors.success,
                            icon: Icons.check_circle,
                          ),
                          _StockStatusRow(
                            label: 'Sobrestock',
                            count: stockStatus['overstock'] ?? 0,
                            color: AppColors.info,
                            icon: Icons.arrow_upward,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Movements this month
                  Expanded(
                    flex: 2,
                    child: _DashboardCard(
                      title: 'Movimientos del Mes',
                      isDark: isDark,
                      child: Column(
                        children: [
                          _MovementRow('Ventas', movements['sale'] ?? 0,
                              AppColors.success),
                          _MovementRow('Compras', movements['purchase'] ?? 0,
                              AppColors.info),
                          _MovementRow('Ajustes', movements['adjustment'] ?? 0,
                              AppColors.warning),
                          _MovementRow('Devoluciones',
                              movements['return'] ?? 0, AppColors.secondary),
                          _MovementRow('Pérdidas', movements['loss'] ?? 0,
                              AppColors.error),
                          _MovementRow('Transferencias',
                              movements['transfer'] ?? 0, AppColors.accent),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Category breakdown
                  Expanded(
                    flex: 3,
                    child: _DashboardCard(
                      title: 'Inventario por Categoría',
                      isDark: isDark,
                      child: Column(
                        children: categories.take(8).map((cat) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    cat['category'] as String,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    '${cat['count']} prod',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    (cat['value'] as double).currency,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Recent Movements Stream ──
              _DashboardCard(
                title: 'Últimos Movimientos',
                isDark: isDark,
                child: StreamBuilder<List<InventoryMovement>>(
                  stream: db.inventoryDao.watchRecentMovements(limit: 10),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No hay movimientos recientes'),
                      );
                    }
                    return DataTable(
                      columnSpacing: 24,
                      headingRowHeight: 36,
                      dataRowMinHeight: 32,
                      dataRowMaxHeight: 40,
                      columns: const [
                        DataColumn(label: Text('Fecha', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        DataColumn(label: Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)), numeric: true),
                        DataColumn(label: Text('Stock Ant.', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)), numeric: true),
                        DataColumn(label: Text('Stock Nuevo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)), numeric: true),
                        DataColumn(label: Text('Razón', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                      ],
                      rows: snapshot.data!.map((m) {
                        return DataRow(cells: [
                          DataCell(Text(m.createdAt.formattedWithTime, style: const TextStyle(fontSize: 12))),
                          DataCell(_MovementTypeBadge(type: m.type)),
                          DataCell(Text(
                            m.quantity > 0 ? '+${m.quantity.toInt()}' : '${m.quantity.toInt()}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: m.quantity > 0 ? AppColors.success : AppColors.error,
                            ),
                          )),
                          DataCell(Text('${m.previousStock.toInt()}', style: const TextStyle(fontSize: 12))),
                          DataCell(Text('${m.newStock.toInt()}', style: const TextStyle(fontSize: 12))),
                          DataCell(Text(m.reason ?? '-', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                        ]);
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════
// ── TAB 2: MOVEMENTS ──
// ══════════════════════════════════════════════════

class _MovementsTab extends ConsumerStatefulWidget {
  const _MovementsTab();

  @override
  ConsumerState<_MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends ConsumerState<_MovementsTab> {
  String? _filterType;
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  List<InventoryMovement> _movements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  Future<void> _loadMovements() async {
    setState(() => _loading = true);
    final db = ref.read(appDatabaseProvider);
    final movements = await db.inventoryDao.getMovementsByDateRange(
      _dateRange.start,
      _dateRange.end,
      type: _filterType,
      limit: 200,
    );
    setState(() {
      _movements = movements;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          // ── Filters Row ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Date Range
                  OutlinedButton.icon(
                    icon: const Icon(Icons.date_range, size: 16),
                    label: Text(
                      '${_dateRange.start.formatted} - ${_dateRange.end.formatted}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: _dateRange,
                      );
                      if (picked != null) {
                        setState(() => _dateRange = picked);
                        _loadMovements();
                      }
                    },
                  ),
                  const SizedBox(width: 12),

                  // Type Filter
                  ..._buildTypeChips(),

                  const Spacer(),

                  // New Movement
                  FilledButton.icon(
                    onPressed: () => _showNewMovementDialog(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Nuevo Movimiento'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Movements Table ──
          Expanded(
            child: Card(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _movements.isEmpty
                      ? const Center(child: Text('No hay movimientos en el rango seleccionado'))
                      : SingleChildScrollView(
                          child: SizedBox(
                            width: double.infinity,
                            child: DataTable(
                              columnSpacing: 20,
                              headingRowHeight: 40,
                              dataRowMinHeight: 36,
                              dataRowMaxHeight: 44,
                              columns: const [
                                DataColumn(label: Text('Fecha', style: TextStyle(fontWeight: FontWeight.w600))),
                                DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.w600))),
                                DataColumn(label: Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                                DataColumn(label: Text('Stock Ant.', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                                DataColumn(label: Text('Stock Nuevo', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                                DataColumn(label: Text('Referencia', style: TextStyle(fontWeight: FontWeight.w600))),
                                DataColumn(label: Text('Razón', style: TextStyle(fontWeight: FontWeight.w600))),
                              ],
                              rows: _movements.map((m) {
                                return DataRow(cells: [
                                  DataCell(Text(m.createdAt.formattedWithTime, style: const TextStyle(fontSize: 13))),
                                  DataCell(_MovementTypeBadge(type: m.type)),
                                  DataCell(Text(
                                    m.quantity > 0 ? '+${m.quantity.toInt()}' : '${m.quantity.toInt()}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: m.quantity > 0 ? AppColors.success : AppColors.error,
                                    ),
                                  )),
                                  DataCell(Text('${m.previousStock.toInt()}')),
                                  DataCell(Text('${m.newStock.toInt()}')),
                                  DataCell(Text(m.reference ?? '-', style: const TextStyle(fontSize: 12))),
                                  DataCell(Text(m.reason ?? '-', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTypeChips() {
    const types = [
      (null, 'Todos', Icons.list),
      ('sale', 'Ventas', Icons.shopping_bag),
      ('purchase', 'Compras', Icons.add_shopping_cart),
      ('adjustment', 'Ajustes', Icons.tune),
      ('return', 'Devoluciones', Icons.undo),
      ('loss', 'Pérdidas', Icons.remove_circle),
      ('transfer', 'Transferencias', Icons.swap_horiz),
    ];

    return types.map((t) {
      final isSelected = _filterType == t.$1;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: FilterChip(
          selected: isSelected,
          label: Text(t.$2, style: TextStyle(
            fontSize: 12,
            color: isSelected ? AppColors.primary : const Color(0xFF475569),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          )),
          avatar: Icon(t.$3, size: 14,
              color: isSelected ? AppColors.primary : const Color(0xFF64748B)),
          onSelected: (_) {
            setState(() => _filterType = t.$1);
            _loadMovements();
          },
          selectedColor: AppColors.primary.withValues(alpha: 0.12),
          backgroundColor: const Color(0xFFF1F5F9),
          checkmarkColor: AppColors.primary,
          side: BorderSide(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
        ),
      );
    }).toList();
  }

  void _showNewMovementDialog(BuildContext context) {
    final typeCtrl = ValueNotifier<String>('adjustment');
    final qtyCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    Product? selectedProduct;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nuevo Movimiento de Inventario'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Product search
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Buscar Producto',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: selectedProduct != null
                        ? const Icon(Icons.check_circle, color: AppColors.success)
                        : null,
                  ),
                  onChanged: (val) => setDialogState(() {}),
                ),
                if (searchCtrl.text.length >= 2 && selectedProduct == null)
                  FutureBuilder<List<Product>>(
                    future: ref
                        .read(appDatabaseProvider)
                        .productsDao
                        .searchProducts(searchCtrl.text),
                    builder: (_, snap) {
                      if (!snap.hasData) return const SizedBox.shrink();
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView(
                          shrinkWrap: true,
                          children: snap.data!.take(5).map((p) {
                            return ListTile(
                              dense: true,
                              title: Text(p.name),
                              subtitle: Text(
                                  'Stock: ${p.currentStock.toInt()} | ${p.barcode ?? "Sin código"}'),
                              onTap: () {
                                selectedProduct = p;
                                searchCtrl.text = p.name;
                                setDialogState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 12),

                // Type
                ValueListenableBuilder<String>(
                  valueListenable: typeCtrl,
                  builder: (_, type, __) => Row(
                    children: [
                      const Text('Tipo: ', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      ...['adjustment', 'loss', 'return'].map((t) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_movementTypeLabel(t), style: TextStyle(
                              color: type == t ? AppColors.primary : const Color(0xFF475569),
                              fontWeight: type == t ? FontWeight.w600 : FontWeight.w500,
                            )),
                            selected: type == t,
                            onSelected: (_) => typeCtrl.value = t,
                            selectedColor: AppColors.primary.withValues(alpha: 0.12),
                            backgroundColor: const Color(0xFFF1F5F9),
                            side: BorderSide(
                              color: type == t ? AppColors.primary.withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Quantity
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))],
                  decoration: const InputDecoration(
                    labelText: 'Cantidad (+entrada / -salida)',
                    border: OutlineInputBorder(),
                    helperText: 'Positivo = entrada, Negativo = salida',
                  ),
                ),
                const SizedBox(height: 12),

                // Reason
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Razón / Nota',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (selectedProduct == null ||
                    qtyCtrl.text.isEmpty) return;
                final qty = double.tryParse(qtyCtrl.text);
                if (qty == null || qty == 0) return;

                final user = ref.read(currentUserProvider);
                if (user == null) return;

                final ts = DateTime.now().millisecondsSinceEpoch;
                await ref
                    .read(appDatabaseProvider)
                    .inventoryDao
                    .recordMovement(
                  id: 'mov_${ts}_${selectedProduct!.id}',
                  productId: selectedProduct!.id,
                  userId: user.id,
                  type: typeCtrl.value,
                  quantity: qty,
                  reason: reasonCtrl.text.isEmpty
                      ? null
                      : reasonCtrl.text,
                );

                if (ctx.mounted) Navigator.pop(ctx);
                _loadMovements();
              },
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// ── TAB 3: PHYSICAL COUNT ──
// ══════════════════════════════════════════════════

class _PhysicalCountTab extends ConsumerStatefulWidget {
  const _PhysicalCountTab();

  @override
  ConsumerState<_PhysicalCountTab> createState() => _PhysicalCountTabState();
}

class _PhysicalCountTabState extends ConsumerState<_PhysicalCountTab> {
  List<InventoryCount> _counts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    setState(() => _loading = true);
    final db = ref.read(appDatabaseProvider);
    final counts = await db.inventoryDao.getInventoryCounts();
    setState(() {
      _counts = counts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          // ── Top Actions ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.fact_check, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Sesiones de Conteo Físico',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _startNewCount(context),
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('Nuevo Conteo'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Counts List ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _counts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fact_check_outlined, size: 64,
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                            const SizedBox(height: 12),
                            const Text('No hay conteos de inventario',
                                style: TextStyle(fontSize: 16)),
                            const SizedBox(height: 8),
                            const Text('Inicia un nuevo conteo físico para verificar tu inventario'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _counts.length,
                        itemBuilder: (context, index) {
                          final count = _counts[index];
                          return _CountCard(
                            count: count,
                            onTap: () => _openCountDetail(count),
                            onComplete: count.status == 'in_progress'
                                ? () => _completeCount(count)
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _startNewCount(BuildContext context) async {
    final db = ref.read(appDatabaseProvider);
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final typeCtrl = ValueNotifier<String>('full');
    String? selectedCategory;
    final notesCtrl = TextEditingController();

    // Get categories for partial count
    final categories = await db.productsDao.getAllCategories();

    if (!context.mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Nuevo Conteo Físico'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tipo de conteo:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable: typeCtrl,
                  builder: (_, type, __) => Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Completo'),
                          subtitle: const Text('Todos los productos'),
                          value: 'full',
                          groupValue: type,
                          onChanged: (v) {
                            typeCtrl.value = v!;
                            selectedCategory = null;
                            setDlgState(() {});
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Parcial'),
                          subtitle: const Text('Por categoría'),
                          value: 'partial',
                          groupValue: type,
                          onChanged: (v) {
                            typeCtrl.value = v!;
                            setDlgState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (typeCtrl.value == 'partial') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                    items: categories.map((c) {
                      return DropdownMenuItem(value: c.id, child: Text(c.name));
                    }).toList(),
                    onChanged: (val) => selectedCategory = val,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Iniciar Conteo'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    final countNumber = await db.inventoryDao.getNextCountNumber();
    final ts = DateTime.now().millisecondsSinceEpoch;

    await db.inventoryDao.startInventoryCount(
      id: 'count_$ts',
      countNumber: countNumber,
      type: typeCtrl.value,
      startedBy: user.id,
      categoryFilter: selectedCategory,
      notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
    );

    _loadCounts();
  }

  void _openCountDetail(InventoryCount count) {
    showDialog(
      context: context,
      builder: (ctx) => _CountDetailDialog(count: count, onSaved: _loadCounts),
    );
  }

  Future<void> _completeCount(InventoryCount count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Completar Conteo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Conteo: ${count.countNumber}'),
            Text('Contados: ${count.countedItems}/${count.totalItems}'),
            Text('Discrepancias: ${count.discrepancies}'),
            const SizedBox(height: 12),
            const Text('¿Desea aplicar los ajustes automáticamente?',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          OutlinedButton(
            onPressed: () async {
              final user = ref.read(currentUserProvider);
              if (user == null) return;
              await ref.read(appDatabaseProvider).inventoryDao.completeInventoryCount(
                countId: count.id,
                completedBy: user.id,
                applyAdjustments: false,
              );
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Sin Ajustes'),
          ),
          FilledButton(
            onPressed: () async {
              final user = ref.read(currentUserProvider);
              if (user == null) return;
              await ref.read(appDatabaseProvider).inventoryDao.completeInventoryCount(
                countId: count.id,
                completedBy: user.id,
                applyAdjustments: true,
              );
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Aplicar Ajustes'),
          ),
        ],
      ),
    );
    if (ok == true) _loadCounts();
  }
}

class _CountCard extends StatelessWidget {
  final InventoryCount count;
  final VoidCallback onTap;
  final VoidCallback? onComplete;

  const _CountCard({
    required this.count,
    required this.onTap,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final progress = count.totalItems > 0
        ? count.countedItems / count.totalItems
        : 0.0;
    final statusColor = switch (count.status) {
      'completed' => AppColors.success,
      'cancelled' => AppColors.error,
      _ => AppColors.warning,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  count.status == 'completed'
                      ? Icons.check_circle
                      : count.status == 'cancelled'
                          ? Icons.cancel
                          : Icons.pending,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(count.countNumber,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                      '${count.type == 'full' ? 'Completo' : 'Parcial'} · ${count.startedAt.formattedWithTime}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),

              // Progress
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${count.countedItems}/${count.totalItems} items',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[200],
                      color: statusColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Discrepancies badge
              if (count.discrepancies > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${count.discrepancies} disc.',
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(width: 8),

              // Actions
              if (onComplete != null)
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
                  tooltip: 'Completar conteo',
                  onPressed: onComplete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountDetailDialog extends ConsumerStatefulWidget {
  final InventoryCount count;
  final VoidCallback onSaved;

  const _CountDetailDialog({required this.count, required this.onSaved});

  @override
  ConsumerState<_CountDetailDialog> createState() => _CountDetailDialogState();
}

class _CountDetailDialogState extends ConsumerState<_CountDetailDialog> {
  List<InventoryCountItem> _items = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final db = ref.read(appDatabaseProvider);
    final items = await db.inventoryDao.getCountItems(widget.count.id);
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  List<InventoryCountItem> get _filteredItems {
    if (_searchCtrl.text.isEmpty) return _items;
    final q = _searchCtrl.text.toLowerCase();
    return _items.where((i) => i.productId.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fact_check, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Conteo ${widget.count.countNumber}',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Buscar producto...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            // Items table
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 16,
                        headingRowHeight: 36,
                        dataRowMinHeight: 40,
                        dataRowMaxHeight: 48,
                        columns: const [
                          DataColumn(label: Text('Producto')),
                          DataColumn(label: Text('Esperado'), numeric: true),
                          DataColumn(label: Text('Contado'), numeric: true),
                          DataColumn(label: Text('Diferencia'), numeric: true),
                          DataColumn(label: Text('Estado')),
                          DataColumn(label: Text('Acción')),
                        ],
                        rows: _filteredItems.map((item) {
                          final diff = item.difference ?? 0;
                          return DataRow(
                            color: item.status == 'counted' && diff != 0
                                ? WidgetStateProperty.all(AppColors.error.withValues(alpha: 0.05))
                                : null,
                            cells: [
                              DataCell(Text(item.productId, style: const TextStyle(fontSize: 12))),
                              DataCell(Text('${item.expectedQty.toInt()}')),
                              DataCell(Text(
                                item.countedQty != null ? '${item.countedQty!.toInt()}' : '-',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: item.status == 'counted'
                                      ? (diff == 0 ? AppColors.success : AppColors.error)
                                      : null,
                                ),
                              )),
                              DataCell(Text(
                                item.status == 'counted' ? '${diff.toInt()}' : '-',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: diff > 0
                                      ? AppColors.success
                                      : diff < 0
                                          ? AppColors.error
                                          : null,
                                ),
                              )),
                              DataCell(_CountStatusBadge(status: item.status)),
                              DataCell(
                                widget.count.status == 'in_progress' && item.status != 'counted'
                                    ? IconButton(
                                        icon: const Icon(Icons.edit, size: 18),
                                        onPressed: () => _countItem(item),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _countItem(InventoryCountItem item) async {
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Contar: ${item.productId}'),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Stock esperado: ${item.expectedQty.toInt()}'),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Cantidad Contada',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok != true || qtyCtrl.text.isEmpty) return;
    final qty = double.tryParse(qtyCtrl.text);
    if (qty == null) return;

    await ref.read(appDatabaseProvider).inventoryDao.recordCountItem(
      countItemId: item.id,
      countedQty: qty,
      notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
    );

    _loadItems();
    widget.onSaved();
  }
}

// ══════════════════════════════════════════════════
// ── TAB 4: BATCHES & FIFO ──
// ══════════════════════════════════════════════════

class _BatchesFifoTab extends ConsumerStatefulWidget {
  const _BatchesFifoTab();

  @override
  ConsumerState<_BatchesFifoTab> createState() => _BatchesFifoTabState();
}

class _BatchesFifoTabState extends ConsumerState<_BatchesFifoTab> {
  int _expiryDays = 90;
  String _view = 'expiring'; // expiring, expired, all

  @override
  Widget build(BuildContext context) {
    final db = ref.read(appDatabaseProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          // ── Filter Row ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // View toggle
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'expiring', label: Text('Próximos a caducar'), icon: Icon(Icons.hourglass_bottom, size: 16)),
                      ButtonSegment(value: 'expired', label: Text('Caducados'), icon: Icon(Icons.dangerous, size: 16)),
                    ],
                    selected: {_view},
                    onSelectionChanged: (vals) => setState(() => _view = vals.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_view == 'expiring') ...[
                    const Text('Días: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    ...[30, 60, 90, 180].map((d) {
                      final isActive = _expiryDays == d;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text('$d', style: TextStyle(
                            fontSize: 12,
                            color: isActive ? AppColors.primary : const Color(0xFF475569),
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          )),
                          selected: isActive,
                          onSelected: (_) => setState(() => _expiryDays = d),
                          selectedColor: AppColors.primary.withValues(alpha: 0.12),
                          backgroundColor: const Color(0xFFF1F5F9),
                          side: BorderSide(
                            color: isActive ? AppColors.primary.withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Batches Table ──
          Expanded(
            child: Card(
              child: FutureBuilder<List<ProductBatche>>(
                future: _view == 'expired'
                    ? db.inventoryDao.getExpiredBatches()
                    : db.inventoryDao.getExpiringBatches(_expiryDays),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final batches = snapshot.data!;
                  if (batches.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 48,
                              color: _view == 'expired' ? AppColors.success : AppColors.success),
                          const SizedBox(height: 12),
                          Text(_view == 'expired'
                              ? 'No hay lotes caducados con stock'
                              : 'No hay lotes próximos a caducar ($_expiryDays días)'),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: SizedBox(
                      width: double.infinity,
                      child: DataTable(
                        columnSpacing: 20,
                        headingRowHeight: 40,
                        columns: const [
                          DataColumn(label: Text('Lote', style: TextStyle(fontWeight: FontWeight.w600))),
                          DataColumn(label: Text('Producto', style: TextStyle(fontWeight: FontWeight.w600))),
                          DataColumn(label: Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                          DataColumn(label: Text('Costo Unit.', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                          DataColumn(label: Text('Valor Total', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                          DataColumn(label: Text('Caducidad', style: TextStyle(fontWeight: FontWeight.w600))),
                          DataColumn(label: Text('Días', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                          DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.w600))),
                        ],
                        rows: batches.map((b) {
                          final daysLeft = b.expirationDate.difference(DateTime.now()).inDays;
                          final isExpired = daysLeft < 0;
                          return DataRow(
                            color: isExpired
                                ? WidgetStateProperty.all(AppColors.error.withValues(alpha: 0.05))
                                : daysLeft < 30
                                    ? WidgetStateProperty.all(AppColors.warning.withValues(alpha: 0.05))
                                    : null,
                            cells: [
                              DataCell(Text(b.batchNumber, style: const TextStyle(fontWeight: FontWeight.w500))),
                              DataCell(Text(b.productId, style: const TextStyle(fontSize: 12))),
                              DataCell(Text('${b.quantity.toInt()}')),
                              DataCell(Text(b.costPrice.currency)),
                              DataCell(Text((b.quantity * b.costPrice).currency, style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(b.expirationDate.formatted)),
                              DataCell(Text(
                                isExpired ? '${daysLeft}d' : '+${daysLeft}d',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isExpired
                                      ? AppColors.error
                                      : daysLeft < 30
                                          ? AppColors.warning
                                          : AppColors.success,
                                ),
                              )),
                              DataCell(_ExpiryBadge(daysLeft: daysLeft)),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// ── TAB 5: ALERTS ──
// ══════════════════════════════════════════════════

class _AlertsTab extends ConsumerWidget {
  const _AlertsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          // ── Header ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active, color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  const Text('Alertas de Inventario',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      await db.inventoryDao.markAllAlertsRead();
                    },
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('Marcar todas leídas'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Alerts Stream ──
          Expanded(
            child: StreamBuilder<List<StockAlert>>(
              stream: db.inventoryDao.watchActiveAlerts(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final alerts = snapshot.data!;
                if (alerts.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_off, size: 48, color: AppColors.success),
                        SizedBox(height: 12),
                        Text('No hay alertas activas'),
                        Text('Pulse "Escanear" para generar alertas basadas en el inventario actual'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: alerts.length,
                  itemBuilder: (context, index) {
                    final alert = alerts[index];
                    return _AlertCard(
                      alert: alert,
                      onDismiss: () => db.inventoryDao.resolveAlert(alert.id),
                      onMarkRead: () => db.inventoryDao.markAlertRead(alert.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final StockAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback onMarkRead;

  const _AlertCard({
    required this.alert,
    required this.onDismiss,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final config = _alertConfig(alert.severity);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: config.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(config.icon, color: config.color, size: 18),
        ),
        title: Text(
          alert.message ?? alert.alertType,
          style: TextStyle(
            fontWeight: alert.isRead ? FontWeight.w400 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          '${_alertTypeLabel(alert.alertType)} · ${alert.triggeredAt.formattedWithTime}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!alert.isRead)
              IconButton(
                icon: const Icon(Icons.mark_email_read, size: 18),
                tooltip: 'Marcar leída',
                onPressed: onMarkRead,
              ),
            IconButton(
              icon: const Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
              tooltip: 'Resolver',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }

  ({Color color, IconData icon}) _alertConfig(String severity) {
    return switch (severity) {
      'critical' => (color: AppColors.error, icon: Icons.error),
      'warning' => (color: AppColors.warning, icon: Icons.warning_amber),
      _ => (color: AppColors.info, icon: Icons.info_outline),
    };
  }

  String _alertTypeLabel(String type) {
    return switch (type) {
      'low_stock' => 'Stock Bajo',
      'overstock' => 'Sobrestock',
      'expiring_soon' => 'Próximo a caducar',
      'expired' => 'Caducado',
      'stagnant' => 'Producto estancado',
      'high_demand' => 'Alta demanda',
      _ => type,
    };
  }
}

// ══════════════════════════════════════════════════
// ── TAB 6: AI PURCHASE SUGGESTIONS ──
// ══════════════════════════════════════════════════

class _SuggestionsTab extends ConsumerWidget {
  const _SuggestionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          // ── Header ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  const Text('Sugerencias de Compra Inteligentes',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const Spacer(),
                  const Text('Basado en velocidad de venta y stock actual',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Suggestions Stream ──
          Expanded(
            child: StreamBuilder<List<PurchaseSuggestion>>(
              stream: db.inventoryDao.watchPurchaseSuggestions(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final suggestions = snapshot.data!;
                if (suggestions.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lightbulb_outline, size: 48, color: AppColors.accent),
                        SizedBox(height: 12),
                        Text('No hay sugerencias de compra pendientes'),
                        Text('Pulse "Escanear" para analizar inventario y generar sugerencias'),
                      ],
                    ),
                  );
                }

                return Card(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: double.infinity,
                      child: DataTable(
                        columnSpacing: 16,
                        headingRowHeight: 40,
                        columns: const [
                          DataColumn(label: Text('Prioridad', style: TextStyle(fontWeight: FontWeight.w600))),
                          DataColumn(label: Text('Producto', style: TextStyle(fontWeight: FontWeight.w600))),
                          DataColumn(label: Text('Cant. Sugerida', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                          DataColumn(label: Text('Costo Est.', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                          DataColumn(label: Text('Venta/día', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                          DataColumn(label: Text('Días Stockout', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                          DataColumn(label: Text('Razón', style: TextStyle(fontWeight: FontWeight.w600))),
                          DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.w600))),
                        ],
                        rows: suggestions.map((s) {
                          return DataRow(
                            color: s.priority >= 3
                                ? WidgetStateProperty.all(AppColors.error.withValues(alpha: 0.05))
                                : s.priority >= 2
                                    ? WidgetStateProperty.all(AppColors.warning.withValues(alpha: 0.05))
                                    : null,
                            cells: [
                              DataCell(_PriorityBadge(priority: s.priority)),
                              DataCell(Text(s.productId, style: const TextStyle(fontSize: 12))),
                              DataCell(Text('${s.suggestedQty.toInt()}', style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(s.estimatedCost.currency)),
                              DataCell(Text(s.avgDailySales.toStringAsFixed(1))),
                              DataCell(Text(
                                s.daysUntilStockout <= 0
                                    ? 'SIN STOCK'
                                    : '${s.daysUntilStockout.toStringAsFixed(0)}d',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: s.daysUntilStockout <= 3
                                      ? AppColors.error
                                      : s.daysUntilStockout <= 7
                                          ? AppColors.warning
                                          : null,
                                ),
                              )),
                              DataCell(Text(s.reason ?? '', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check, size: 18, color: AppColors.success),
                                    tooltip: 'Aprobar',
                                    onPressed: () => db.inventoryDao.updateSuggestionStatus(s.id, 'approved'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18, color: AppColors.error),
                                    tooltip: 'Descartar',
                                    onPressed: () => db.inventoryDao.updateSuggestionStatus(s.id, 'dismissed'),
                                  ),
                                ],
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// ── SHARED WIDGETS ──
// ══════════════════════════════════════════════════

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final Color color;
  final bool isDark;

  const _KpiCard({
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Text(subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  )),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isDark;

  const _DashboardCard({
    required this.title,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            const Divider(),
            child,
          ],
        ),
      ),
    );
  }
}

class _StockStatusRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _StockStatusRow({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _MovementRow(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text('$count',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class _MovementTypeBadge extends StatelessWidget {
  final String type;
  const _MovementTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final config = _typeConfig[type] ?? ('Otro', Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: config.$2.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        config.$1,
        style: TextStyle(
          fontSize: 11,
          color: config.$2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static const Map<String, (String, Color)> _typeConfig = {
    'sale': ('Venta', AppColors.success),
    'purchase': ('Compra', AppColors.info),
    'adjustment': ('Ajuste', AppColors.warning),
    'return': ('Devolución', AppColors.secondary),
    'loss': ('Pérdida', AppColors.error),
    'transfer': ('Transfer', AppColors.accent),
  };
}

class _CountStatusBadge extends StatelessWidget {
  final String status;
  const _CountStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'counted' => ('Contado', AppColors.success),
      'skipped' => ('Omitido', Colors.grey),
      _ => ('Pendiente', AppColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _ExpiryBadge extends StatelessWidget {
  final int daysLeft;
  const _ExpiryBadge({required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final (label, color) = daysLeft < 0
        ? ('CADUCADO', AppColors.error)
        : daysLeft < 30
            ? ('URGENTE', AppColors.warning)
            : ('Próximo', AppColors.info);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final int priority;
  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (priority) {
      3 => ('CRÍTICO', AppColors.error),
      2 => ('ALTO', AppColors.warning),
      1 => ('MEDIO', AppColors.info),
      _ => ('BAJO', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

String _movementTypeLabel(String type) {
  return switch (type) {
    'adjustment' => 'Ajuste',
    'loss' => 'Pérdida',
    'return' => 'Devolución',
    _ => type,
  };
}
