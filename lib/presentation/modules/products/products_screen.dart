import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';
import '../../../services/import_export/excel_import_service.dart';
import '../../../services/import_export/xml_invoice_import_service.dart';

// ── Filter State ──
final _searchProvider = StateProvider.autoDispose<String>((ref) => '');
final _categoryFilterProvider =
    StateProvider.autoDispose<String>((ref) => 'all');
final _stockFilterProvider =
    StateProvider.autoDispose<String>((ref) => 'all'); // all, low, out, ok
final _prescriptionFilterProvider =
    StateProvider.autoDispose<bool?>((ref) => null);
final _sortColumnProvider = StateProvider.autoDispose<String>((ref) => 'name');
final _sortAscProvider = StateProvider.autoDispose<bool>((ref) => true);

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Column(
        children: [
          _buildGoldenHeader(context),
          _buildToolbar(context),
          _buildStatsRow(db),
          _buildSearchBar(),
          Expanded(child: _buildProductsTable(db)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── GOLDEN HEADER (SICAR-Style) ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildGoldenHeader(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF2C5282), Color(0xFF3B6BA5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Icon(LucideIcons.pill, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Text(
            'PRODUCTOS',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          StreamBuilder<List<Product>>(
            stream: db.productsDao.watchAllProducts(),
            builder: (context, snap) {
              final count = snap.data?.length ?? 0;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count productos',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  late final db = ref.read(appDatabaseProvider);

  // ══════════════════════════════════════════════════════════════
  // ── TOOLBAR BUTTONS ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildToolbar(BuildContext context) {
    return Container(
      height: 48,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _toolBtn(
            icon: LucideIcons.plus,
            label: 'Nuevo',
            color: AppColors.primary,
            onTap: () => context.go('/products/new'),
          ),
          _toolBtn(
            icon: LucideIcons.folderOpen,
            label: 'Departamentos',
            color: AppColors.secondary,
            onTap: () => _showCategoryManager(context),
          ),
          _toolBtn(
            icon: LucideIcons.alertTriangle,
            label: 'Stock Bajo',
            color: const Color(0xFFD97706),
            onTap: () =>
                ref.read(_stockFilterProvider.notifier).state = 'low',
          ),
          _toolBtn(
            icon: LucideIcons.clock,
            label: 'Por Vencer',
            color: const Color(0xFFDC2626),
            onTap: () => _showExpiringBatches(context),
          ),
          const Spacer(),
          _toolBtn(
            icon: LucideIcons.download,
            label: 'Importar',
            color: AppColors.textSecondaryLight,
            onTap: () => _showImportDialog(context),
          ),
          _toolBtn(
            icon: LucideIcons.printer,
            label: 'Imprimir',
            color: AppColors.textSecondaryLight,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── STATS ROW ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildStatsRow(AppDatabase db) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: FutureBuilder<int>(
              future: db.productsDao.countActiveProducts(),
              builder: (ctx, snap) => _statCard(
                'Total Activos',
                '${snap.data ?? 0}',
                LucideIcons.package,
                const Color(0xFF2563EB),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: db.productsDao.watchLowStockProducts(),
              builder: (ctx, snap) => _statCard(
                'Stock Bajo',
                '${snap.data?.length ?? 0}',
                LucideIcons.alertTriangle,
                (snap.data?.isNotEmpty ?? false)
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF059669),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FutureBuilder<double>(
              future: db.productsDao.totalInventoryValue(),
              builder: (ctx, snap) => _statCard(
                'Valor Inventario',
                (snap.data ?? 0.0).currency,
                LucideIcons.dollarSign,
                const Color(0xFF059669),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StreamBuilder<List<ProductBatche>>(
              stream: db.productsDao.watchExpiringBatches(90),
              builder: (ctx, snap) => _statCard(
                'Por Vencer (90d)',
                '${snap.data?.length ?? 0} lotes',
                LucideIcons.clock,
                (snap.data?.isNotEmpty ?? false)
                    ? const Color(0xFFD97706)
                    : const Color(0xFF059669),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── SEARCH & FILTERS ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildSearchBar() {
    final stockFilter = ref.watch(_stockFilterProvider);
    final prescFilter = ref.watch(_prescriptionFilterProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          // Search
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText:
                      'Buscar por nombre, código, genérico, laboratorio...',
                  hintStyle: GoogleFonts.inter(fontSize: 13),
                  prefixIcon:
                      const Icon(LucideIcons.search, size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(_searchProvider.notifier).state = '';
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                ),
                onChanged: (v) =>
                    ref.read(_searchProvider.notifier).state = v,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Category dropdown
          Expanded(
            flex: 1,
            child: SizedBox(
              height: 40,
              child: StreamBuilder<List<Category>>(
                stream: db.productsDao.watchCategories(),
                builder: (context, snapshot) {
                  final categories = snapshot.data ?? [];
                  return DropdownButtonFormField<String>(
                    value: ref.watch(_categoryFilterProvider),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    isExpanded: true,
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimaryLight),
                    items: [
                      const DropdownMenuItem(
                          value: 'all', child: Text('Todas las categorías')),
                      ...categories.map((c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.name))),
                    ],
                    onChanged: (v) =>
                        ref.read(_categoryFilterProvider.notifier).state =
                            v ?? 'all',
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Quick filter chips
          _filterChip('Bajo Stock', stockFilter == 'low', () {
            ref.read(_stockFilterProvider.notifier).state =
                stockFilter == 'low' ? 'all' : 'low';
          }, AppColors.error),
          const SizedBox(width: 6),
          _filterChip('Receta', prescFilter == true, () {
            ref.read(_prescriptionFilterProvider.notifier).state =
                prescFilter == true ? null : true;
          }, AppColors.warning),
        ],
      ),
    );
  }

  Widget _filterChip(
      String label, bool active, VoidCallback onTap, Color color) {
    return Material(
      color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? color : AppColors.borderLight,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? color : AppColors.textSecondaryLight,
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── PRODUCTS TABLE ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildProductsTable(AppDatabase db) {
    final search = ref.watch(_searchProvider);
    final categoryFilter = ref.watch(_categoryFilterProvider);
    final stockFilter = ref.watch(_stockFilterProvider);
    final prescFilter = ref.watch(_prescriptionFilterProvider);
    final sortCol = ref.watch(_sortColumnProvider);
    final sortAsc = ref.watch(_sortAscProvider);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: StreamBuilder<List<Product>>(
        stream: db.productsDao.watchAllProducts(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var products = snapshot.data!;

          // Search filter
          if (search.isNotEmpty) {
            final q = search.toLowerCase();
            products = products.where((p) {
              return p.name.toLowerCase().contains(q) ||
                  (p.barcode?.toLowerCase().contains(q) ?? false) ||
                  (p.genericName?.toLowerCase().contains(q) ?? false) ||
                  (p.laboratory?.toLowerCase().contains(q) ?? false) ||
                  (p.internalCode?.toLowerCase().contains(q) ?? false);
            }).toList();
          }

          // Category filter
          if (categoryFilter != 'all') {
            products =
                products.where((p) => p.categoryId == categoryFilter).toList();
          }

          // Stock filter
          if (stockFilter == 'low') {
            products = products
                .where((p) => p.currentStock <= p.minStock)
                .toList();
          } else if (stockFilter == 'out') {
            products =
                products.where((p) => p.currentStock <= 0).toList();
          }

          // Prescription filter
          if (prescFilter != null) {
            products = products
                .where((p) => p.requiresPrescription == prescFilter)
                .toList();
          }

          // Sort
          products.sort((a, b) {
            int cmp;
            switch (sortCol) {
              case 'barcode':
                cmp = (a.barcode ?? '').compareTo(b.barcode ?? '');
              case 'name':
                cmp = a.name.compareTo(b.name);
              case 'laboratory':
                cmp = (a.laboratory ?? '').compareTo(b.laboratory ?? '');
              case 'costPrice':
                cmp = a.costPrice.compareTo(b.costPrice);
              case 'salePrice':
                cmp = a.salePrice.compareTo(b.salePrice);
              case 'stock':
                cmp = a.currentStock.compareTo(b.currentStock);
              default:
                cmp = a.name.compareTo(b.name);
            }
            return sortAsc ? cmp : -cmp;
          });

          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.packageX,
                      size: 48, color: AppColors.textTertiaryLight),
                  const SizedBox(height: 12),
                  Text(
                    'No se encontraron productos',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondaryLight,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => context.go('/products/new'),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Crear producto'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Table header
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(12)),
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    _sortHeader('Código', 'barcode', 100),
                    _sortHeader('Producto', 'name', 0, flex: 3),
                    _sortHeader('Laboratorio', 'laboratory', 0, flex: 1),
                    _sortHeader('P. Costo', 'costPrice', 90),
                    _sortHeader('P. Venta', 'salePrice', 90),
                    _sortHeader('Stock', 'stock', 80),
                    SizedBox(
                      width: 70,
                      child: Text('Estado',
                          style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 90), // Actions
                  ],
                ),
              ),
              const Divider(height: 1),

              // Table body
              Expanded(
                child: ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final p = products[index];
                    final lowStock = p.currentStock <= p.minStock;
                    final outOfStock = p.currentStock <= 0;

                    return InkWell(
                      onTap: () =>
                          context.go('/products/edit/${p.id}'),
                      onSecondaryTapDown: (d) =>
                          _showContextMenu(context, d, p),
                      child: Container(
                        height: 48,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        color: index.isEven
                            ? Colors.transparent
                            : AppColors.backgroundLight
                                .withValues(alpha: 0.5),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 100,
                              child: Text(
                                p.barcode ?? p.id.substring(0, 8),
                                style: GoogleFonts.jetBrainsMono(
                                    fontSize: 12,
                                    color: AppColors.textSecondaryLight),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text(
                                    p.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (p.genericName != null &&
                                      p.genericName!.isNotEmpty)
                                    Text(
                                      '${p.genericName}${p.concentration != null ? ' • ${p.concentration}' : ''}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color:
                                            AppColors.textTertiaryLight,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Text(
                                p.laboratory ?? '-',
                                style: GoogleFonts.inter(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              child: Text(
                                p.costPrice.currency,
                                style: GoogleFonts.inter(fontSize: 12),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              child: Text(
                                p.salePrice.currency,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1E293B),
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: _stockBadge(
                                  p.currentStock, lowStock, outOfStock),
                            ),
                            SizedBox(
                              width: 70,
                              child: Row(
                                children: [
                                  if (p.requiresPrescription)
                                    Tooltip(
                                      message: 'Requiere receta',
                                      child: Icon(LucideIcons.fileText,
                                          size: 14,
                                          color: AppColors.warning),
                                    ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: p.isActive
                                          ? AppColors.success
                                              .withValues(alpha: 0.1)
                                          : AppColors.error
                                              .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      p.isActive ? 'Activo' : 'Inactivo',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: p.isActive
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Actions
                            SizedBox(
                              width: 90,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(LucideIcons.pencil,
                                        size: 16),
                                    onPressed: () => context
                                        .go('/products/edit/${p.id}'),
                                    tooltip: 'Editar',
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    icon: Icon(LucideIcons.trash2,
                                        size: 16,
                                        color: AppColors.error
                                            .withValues(alpha: 0.7)),
                                    onPressed: () =>
                                        _confirmDelete(context, p),
                                    tooltip: 'Desactivar',
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Bottom bar
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Text(
                      '${products.length} producto(s) encontrado(s)',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Click para editar • Click derecho para opciones',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textTertiaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sortHeader(String label, String column, double width,
      {int flex = 0}) {
    final sortCol = ref.watch(_sortColumnProvider);
    final sortAsc = ref.watch(_sortAscProvider);
    final isActive = sortCol == column;

    final child = InkWell(
      onTap: () {
        if (isActive) {
          ref.read(_sortAscProvider.notifier).state = !sortAsc;
        } else {
          ref.read(_sortColumnProvider.notifier).state = column;
          ref.read(_sortAscProvider.notifier).state = true;
        }
      },
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              color: isActive
                  ? AppColors.primary
                  : AppColors.textPrimaryLight,
            ),
          ),
          if (isActive)
            Icon(
              sortAsc ? LucideIcons.arrowUp : LucideIcons.arrowDown,
              size: 12,
              color: AppColors.primary,
            ),
        ],
      ),
    );

    return flex > 0 ? Expanded(flex: flex, child: child) : SizedBox(width: width, child: child);
  }

  Widget _stockBadge(double stock, bool low, bool out) {
    final color = out
        ? const Color(0xFFDC2626)
        : low
            ? const Color(0xFFD97706)
            : const Color(0xFF059669);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        stock.toInt().toString(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── CONTEXT MENU ──
  // ══════════════════════════════════════════════════════════════
  void _showContextMenu(
      BuildContext context, TapDownDetails details, Product p) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem(value: 'edit', child: _menuItem(LucideIcons.pencil, 'Editar producto')),
        PopupMenuItem(value: 'duplicate', child: _menuItem(LucideIcons.copy, 'Duplicar')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'batches', child: _menuItem(LucideIcons.layers, 'Ver lotes')),
        PopupMenuItem(value: 'history', child: _menuItem(LucideIcons.history, 'Historial de ventas')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: _menuItem(LucideIcons.trash2, 'Desactivar', color: AppColors.error),
        ),
      ],
    );

    if (!mounted) return;
    switch (result) {
      case 'edit':
        context.go('/products/edit/${p.id}');
      case 'duplicate':
        context.go('/products/new');
      case 'batches':
        _showBatchesDialog(context, p);
      case 'delete':
        _confirmDelete(context, p);
    }
  }

  Widget _menuItem(IconData icon, String label, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textSecondaryLight),
        const SizedBox(width: 10),
        Text(label,
            style: GoogleFonts.inter(fontSize: 13, color: color)),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── DIALOGS ──
  // ══════════════════════════════════════════════════════════════
  void _confirmDelete(BuildContext context, Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desactivar Producto',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
                color: AppColors.textPrimaryLight, fontSize: 14),
            children: [
              const TextSpan(text: '¿Desactivar '),
              TextSpan(
                text: product.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(
                  text:
                      '?\n\nEl producto no aparecerá en el POS ni en búsquedas.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await db.productsDao.softDeleteProduct(product.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} desactivado'),
            backgroundColor: AppColors.warning,
            action: SnackBarAction(
              label: 'Deshacer',
              textColor: Colors.white,
              onPressed: () async {
                await (db.update(db.products)
                      ..where((p) => p.id.equals(product.id)))
                    .write(const ProductsCompanion(isActive: Value(true)));
              },
            ),
          ),
        );
      }
    }
  }

  void _showCategoryManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _CategoryManagerDialog(db: db),
    );
  }

  void _showExpiringBatches(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ExpiringBatchesDialog(db: db),
    );
  }

  void _showBatchesDialog(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (ctx) => _ProductBatchesDialog(db: db, product: product),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ImportDialog(db: db),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ── CATEGORY MANAGER DIALOG ──
// ══════════════════════════════════════════════════════════════
class _CategoryManagerDialog extends StatefulWidget {
  final AppDatabase db;
  const _CategoryManagerDialog({required this.db});

  @override
  State<_CategoryManagerDialog> createState() =>
      _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<_CategoryManagerDialog> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.folderOpen,
              color: AppColors.secondary, size: 22),
          const SizedBox(width: 10),
          Text('Departamentos / Categorías',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            // Add new
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Nueva categoría...',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _addCategory(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addCategory,
                  child: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            // List
            Expanded(
              child: StreamBuilder<List<Category>>(
                stream: widget.db.productsDao.watchCategories(),
                builder: (context, snap) {
                  final cats = snap.data ?? [];
                  if (cats.isEmpty) {
                    return Center(
                      child: Text('Sin categorías',
                          style: GoogleFonts.inter(
                              color: AppColors.textSecondaryLight)),
                    );
                  }
                  return ListView.builder(
                    itemCount: cats.length,
                    itemBuilder: (ctx, i) {
                      final c = cats[i];
                      return ListTile(
                        leading: const Icon(LucideIcons.folder, size: 18),
                        title: Text(c.name,
                            style: GoogleFonts.inter(fontSize: 14)),
                        dense: true,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Future<void> _addCategory() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await widget.db.productsDao.insertCategory(
      CategoriesCompanion(
        id: Value(DateTime.now().millisecondsSinceEpoch.toString()),
        name: Value(name),
      ),
    );
    _nameController.clear();
  }
}

// ══════════════════════════════════════════════════════════════
// ── EXPIRING BATCHES DIALOG ──
// ══════════════════════════════════════════════════════════════
class _ExpiringBatchesDialog extends StatelessWidget {
  final AppDatabase db;
  const _ExpiringBatchesDialog({required this.db});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.clock, color: AppColors.warning, size: 22),
          const SizedBox(width: 10),
          Text('Lotes por Vencer (90 días)',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: StreamBuilder<List<ProductBatche>>(
          stream: db.productsDao.watchExpiringBatches(90),
          builder: (context, snap) {
            final batches = snap.data ?? [];
            if (batches.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.checkCircle,
                        size: 48, color: AppColors.success),
                    const SizedBox(height: 12),
                    Text('No hay lotes por vencer',
                        style: GoogleFonts.inter(fontSize: 15)),
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: batches.length,
              itemBuilder: (ctx, i) {
                final b = batches[i];
                final expired = b.expirationDate.isBefore(DateTime.now());
                return ListTile(
                  leading: Icon(
                    expired ? LucideIcons.alertOctagon : LucideIcons.clock,
                    color: expired ? AppColors.error : AppColors.warning,
                    size: 20,
                  ),
                  title: Text('Lote: ${b.batchNumber}',
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Vence: ${b.expirationDate.formatted} • Cant: ${b.quantity.toInt()}',
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                  trailing: expired
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('VENCIDO',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w700)),
                        )
                      : null,
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ── PRODUCT BATCHES DIALOG ──
// ══════════════════════════════════════════════════════════════
class _ProductBatchesDialog extends StatelessWidget {
  final AppDatabase db;
  final Product product;
  const _ProductBatchesDialog({required this.db, required this.product});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.layers, color: AppColors.secondary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Lotes: ${product.name}',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        height: 300,
        child: FutureBuilder<List<ProductBatche>>(
          future: db.productsDao.getBatchesForProduct(product.id),
          builder: (context, snap) {
            final batches = snap.data ?? [];
            if (batches.isEmpty) {
              return Center(
                child: Text('Sin lotes registrados',
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondaryLight)),
              );
            }
            return ListView.builder(
              itemCount: batches.length,
              itemBuilder: (ctx, i) {
                final b = batches[i];
                return ListTile(
                  leading: const Icon(LucideIcons.package, size: 18),
                  title: Text('Lote ${b.batchNumber}',
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Vence: ${b.expirationDate.formatted} • Cant: ${b.quantity.toInt()}',
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                  dense: true,
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ── IMPORT DIALOG ──
// ══════════════════════════════════════════════════════════════
class _ImportDialog extends StatefulWidget {
  final AppDatabase db;
  const _ImportDialog({required this.db});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String? _resultMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 580,
        height: 520,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Icon(LucideIcons.download, color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Importar Productos',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(
                  icon: Icon(LucideIcons.fileSpreadsheet, size: 18),
                  text: 'Excel',
                ),
                Tab(
                  icon: Icon(LucideIcons.fileCode, size: 18),
                  text: 'Facturas XML',
                ),
              ],
            ),
            const Divider(height: 1),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildExcelTab(),
                  _buildXmlTab(),
                ],
              ),
            ),

            // Result banner
            if (_resultMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: (_isError ? AppColors.error : AppColors.success).withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Icon(
                      _isError ? LucideIcons.alertCircle : LucideIcons.checkCircle,
                      size: 18,
                      color: _isError ? AppColors.error : AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _resultMessage!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: _isError ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Loading
            if (_isLoading) const LinearProgressIndicator(),

            // Bottom actions
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── EXCEL TAB ──
  Widget _buildExcelTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step 1: Download template
          _stepCard(
            step: '1',
            title: 'Descargar Plantilla',
            description: 'Descarga la plantilla Excel con las columnas correctas, llénala con tus productos.',
            icon: LucideIcons.download,
            color: AppColors.primary,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _downloadTemplate,
              icon: const Icon(LucideIcons.fileSpreadsheet, size: 16),
              label: const Text('Descargar Plantilla Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Step 2: Upload file
          _stepCard(
            step: '2',
            title: 'Subir Archivo Excel',
            description: 'Selecciona el archivo .xlsx con tus productos. Se actualizarán por código de barras si ya existen.',
            icon: LucideIcons.upload,
            color: AppColors.secondary,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _importExcel,
              icon: const Icon(LucideIcons.fileUp, size: 16),
              label: const Text('Seleccionar Archivo Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Step 3: Export
          _stepCard(
            step: '3',
            title: 'Exportar Productos',
            description: 'Exporta todos los productos actuales a Excel para respaldo o edición.',
            icon: LucideIcons.fileOutput,
            color: AppColors.info,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _exportExcel,
              icon: const Icon(LucideIcons.fileOutput, size: 16),
              label: const Text('Exportar a Excel'),
            ),
          ),
        ],
      ),
    );
  }

  // ── XML TAB ──
  Widget _buildXmlTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.info, size: 18, color: AppColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sube archivos XML de facturas electrónicas (CFDI). '
                    'El sistema extraerá automáticamente los productos, precios y cantidades.',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.info),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Upload XML
          _stepCard(
            step: '1',
            title: 'Subir Facturas XML',
            description: 'Selecciona uno o varios archivos XML. Se importarán los productos con precios del proveedor.',
            icon: LucideIcons.fileCode,
            color: const Color(0xFFE65100),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _importXml,
              icon: const Icon(LucideIcons.fileUp, size: 16),
              label: const Text('Seleccionar Archivos XML'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Features list
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Funciones automáticas:',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _featureRow(LucideIcons.scanLine, 'Extrae códigos de producto del XML'),
                _featureRow(LucideIcons.dollarSign, 'Importa precio de costo del proveedor'),
                _featureRow(LucideIcons.calculator, 'Calcula precio de venta con 30% margen'),
                _featureRow(LucideIcons.package, 'Suma stock si el producto ya existe'),
                _featureRow(LucideIcons.building2, 'Identifica datos del proveedor (RFC)'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryLight)),
          ),
        ],
      ),
    );
  }

  Widget _stepCard({
    required String step,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(step,
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700, color: color)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(description,
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryLight)),
                const SizedBox(height: 10),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ACTIONS ──
  Future<void> _downloadTemplate() async {
    setState(() { _isLoading = true; _resultMessage = null; });
    try {
      final service = ExcelImportService(widget.db);
      final path = await service.generateTemplate();
      setState(() {
        _resultMessage = 'Plantilla guardada en: $path';
        _isError = false;
      });
    } catch (e) {
      setState(() { _resultMessage = 'Error: $e'; _isError = true; });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      dialogTitle: 'Seleccionar archivo Excel de productos',
    );
    if (result == null || result.files.single.path == null) return;

    setState(() { _isLoading = true; _resultMessage = null; });
    try {
      final service = ExcelImportService(widget.db);
      final importResult = await service.importFromExcel(result.files.single.path!);
      final msg = StringBuffer()
        ..write('Importados: ${importResult.imported}')
        ..write(' | Actualizados: ${importResult.updated}')
        ..write(' | Omitidos: ${importResult.skipped}');
      if (importResult.hasErrors) {
        msg.write(' | Errores: ${importResult.errors.length}');
      }
      setState(() {
        _resultMessage = msg.toString();
        _isError = importResult.hasErrors && importResult.total == 0;
      });
    } catch (e) {
      setState(() { _resultMessage = 'Error: $e'; _isError = true; });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() { _isLoading = true; _resultMessage = null; });
    try {
      final service = ExcelImportService(widget.db);
      final path = await service.exportToExcel();
      setState(() {
        _resultMessage = 'Exportado en: $path';
        _isError = false;
      });
    } catch (e) {
      setState(() { _resultMessage = 'Error: $e'; _isError = true; });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importXml() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
      allowMultiple: true,
      dialogTitle: 'Seleccionar facturas XML',
    );
    if (result == null || result.files.isEmpty) return;

    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();
    if (paths.isEmpty) return;

    setState(() { _isLoading = true; _resultMessage = null; });
    try {
      final service = XmlInvoiceImportService(widget.db);
      final importResult = await service.importMultipleXml(paths);
      final msg = StringBuffer()
        ..write('${paths.length} archivo(s) procesados')
        ..write(' | Importados: ${importResult.imported}')
        ..write(' | Actualizados: ${importResult.updated}');
      if (importResult.invoiceInfo.isNotEmpty) {
        final prov = importResult.invoiceInfo['Proveedor'];
        if (prov != null) msg.write(' | Proveedor: $prov');
      }
      if (importResult.hasErrors) {
        msg.write(' | Errores: ${importResult.errors.length}');
      }
      setState(() {
        _resultMessage = msg.toString();
        _isError = importResult.hasErrors && importResult.total == 0;
      });
    } catch (e) {
      setState(() { _resultMessage = 'Error: $e'; _isError = true; });
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
