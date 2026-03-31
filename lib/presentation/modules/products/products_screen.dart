import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../utils/platform_io.dart'
    if (dart.library.js_interop) '../../../utils/platform_io_web.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';
import '../../../services/ai/smart_import_service.dart';
import '../../../services/import_export/excel_import_service.dart';
import '../../../services/import_export/pdf_invoice_preview.dart';
import '../../../services/import_export/xml_invoice_preview.dart';
import 'xml_invoice_preview_dialog.dart';

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
          // Quick return to POS
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.go('/'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Volver al POS',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
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
            color: const Color(0xFF7C3AED),
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
                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B)),
                decoration: InputDecoration(
                  hintText:
                      'Buscar por nombre, código, genérico, laboratorio...',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                  prefixIcon:
                      const Icon(LucideIcons.search, size: 18, color: Color(0xFF64748B)),
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
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B)),
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
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF334155))),
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
                                    color: const Color(0xFF475569)),
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
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1E293B),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (p.genericName != null &&
                                      p.genericName!.isNotEmpty)
                                    Text(
                                      '${p.genericName}${p.concentration != null ? ' • ${p.concentration}' : ''}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: const Color(0xFF64748B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Text(
                                p.laboratory ?? '-',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF475569),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              child: Text(
                                p.costPrice.currency,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF334155),
                                ),
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
                  : const Color(0xFF334155),
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
                            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B))),
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
                        style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1E293B))),
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
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
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
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
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
// ── IMPORT DIALOG (Restructured with Smart Import + AI) ──
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
  late SmartImportService _smartService;
  bool _isLoading = false;
  String? _resultMessage;
  bool _isError = false;
  List<String> _errorDetails = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _smartService = SmartImportService(widget.db);
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
        width: 660,
        height: 600,
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.fileUp, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Importar Productos',
                          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                        ),
                        Text(
                          'Importación desde Excel y XML',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Tabs ──
            TabBar(
              controller: _tabController,
              labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(icon: Icon(LucideIcons.fileSpreadsheet, size: 18), text: 'Excel'),
                Tab(icon: Icon(LucideIcons.fileCode, size: 18), text: 'XML Facturas'),
              ],
            ),
            const Divider(height: 1),

            // ── Tab Content ──
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildExcelTab(),
                  _buildXmlTab(),
                ],
              ),
            ),

            // ── Result Banner ──
            if (_resultMessage != null)
              _buildResultBanner(),

            if (_isLoading)
              const LinearProgressIndicator(),

            // ── Bottom ──
            Container(
              padding: const EdgeInsets.all(14),
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

  // ══════════════════════════════════════════════════════════════
  // ── RESULT BANNER ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildResultBanner() {
    final bgColor = (_isError ? AppColors.error : AppColors.success).withValues(alpha: 0.08);
    final fgColor = _isError ? AppColors.error : AppColors.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _isError ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
                size: 18,
                color: fgColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _resultMessage!,
                  style: GoogleFonts.inter(fontSize: 13, color: fgColor, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          if (_errorDetails.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...(_errorDetails.take(5).map((e) => Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text('• $e',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.error),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ))),
            if (_errorDetails.length > 5)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text('... y ${_errorDetails.length - 5} errores más',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiaryLight)),
              ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── EXCEL TAB ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildExcelTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepCard(
            step: '1',
            title: 'Descargar Plantilla',
            description: 'Descarga la plantilla Excel con columnas correctas. Incluye stock inicial.',
            icon: LucideIcons.download,
            color: AppColors.primary,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _downloadTemplate,
              icon: const Icon(LucideIcons.fileSpreadsheet, size: 16),
              label: const Text('Descargar Plantilla'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _stepCard(
            step: '2',
            title: 'Importar Productos',
            description: 'Sube un .xlsx con tus productos. Se actualiza por código de barras, código interno, o nombre exacto.',
            icon: LucideIcons.upload,
            color: AppColors.secondary,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _importExcel,
              icon: const Icon(LucideIcons.fileUp, size: 16),
              label: const Text('Seleccionar Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _stepCard(
            step: '3',
            title: 'Exportar Productos',
            description: 'Exporta todos tus productos con stock a un archivo Excel.',
            icon: LucideIcons.fileOutput,
            color: AppColors.info,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _exportExcel,
              icon: const Icon(LucideIcons.fileOutput, size: 16),
              label: const Text('Exportar a Excel'),
            ),
          ),
          const SizedBox(height: 10),
          _featureBox([
            _ft(LucideIcons.search, 'Busca por código de barras, código interno o nombre exacto'),
            _ft(LucideIcons.refreshCw, 'Actualiza precio, stock y datos si el producto ya existe'),
            _ft(LucideIcons.layers, 'Crea lotes automáticamente si incluyes lote y caducidad'),
            _ft(LucideIcons.folderPlus, 'Crea categorías automáticamente si no existen'),
          ]),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── XML TAB ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildXmlTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    'Sube facturas electrónicas XML (SRI Ecuador, CFDI México, UBL). '
                    'Extrae productos, precios, cantidades y datos del proveedor.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.info),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _stepCard(
            step: '1',
            title: 'Subir Facturas XML',
            description: 'Selecciona uno o varios archivos .xml de facturas electrónicas.',
            icon: LucideIcons.fileCode,
            color: const Color(0xFFE65100),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _importXml,
              icon: const Icon(LucideIcons.fileUp, size: 16),
              label: const Text('Seleccionar XML'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100), foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _featureBox([
            _ft(LucideIcons.scanLine, 'Soporta SRI Ecuador, CFDI México, UBL, y formatos genéricos'),
            _ft(LucideIcons.dollarSign, 'Importa precio de costo y calcula venta con 30% margen'),
            _ft(LucideIcons.package, 'Suma stock si el producto ya existe'),
            _ft(LucideIcons.building2, 'Identifica datos del proveedor (RUC/RFC)'),
            _ft(LucideIcons.search, 'Busca por código, código interno o nombre exacto'),
          ]),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── PDF TAB ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildPdfTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.info, size: 18, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sube facturas en PDF (RIDE SRI Ecuador, facturas genéricas). '
                    'Extrae productos, precios, cantidades y datos del proveedor usando análisis de texto.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _stepCard(
            step: '1',
            title: 'Subir Facturas PDF',
            description: 'Selecciona uno o varios archivos .pdf de facturas. Deben tener texto seleccionable.',
            icon: LucideIcons.fileText,
            color: AppColors.accent,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _importPdf,
              icon: const Icon(LucideIcons.fileUp, size: 16),
              label: const Text('Seleccionar PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _featureBox([
            _ft(LucideIcons.scanLine, 'Extrae texto del PDF y detecta tabla de productos'),
            _ft(LucideIcons.dollarSign, 'Importa precio de costo y calcula venta con 30% margen'),
            _ft(LucideIcons.package, 'Suma stock si el producto ya existe'),
            _ft(LucideIcons.building2, 'Identifica datos del proveedor (RUC, dirección, teléfono)'),
            _ft(LucideIcons.search, 'Busca por código, código interno o nombre exacto'),
            _ft(LucideIcons.eye, 'Vista previa completa antes de confirmar la importación'),
          ]),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── SHARED WIDGETS ──
  // ══════════════════════════════════════════════════════════════
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
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(description, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryLight)),
                const SizedBox(height: 10),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureBox(List<Widget> features) {
    return Container(
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
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
          const SizedBox(height: 6),
          ...features,
        ],
      ),
    );
  }

  Widget _ft(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryLight)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── IMPORT ACTIONS ──
  // ══════════════════════════════════════════════════════════════
  void _showResult(SmartImportResult r) {
    final msg = StringBuffer();

    if (r.source.isNotEmpty) msg.write('[${r.source}] ');
    msg.write('Nuevos: ${r.imported}');
    if (r.updated > 0) msg.write(' | Actualizados: ${r.updated}');
    if (r.skipped > 0) msg.write(' | Omitidos: ${r.skipped}');
    if (r.batches > 0) msg.write(' | Lotes: ${r.batches}');
    if (r.supplierCreated && r.supplierName != null) {
      msg.write(' | Proveedor creado: ${r.supplierName}');
    } else if (r.supplierName != null) {
      msg.write(' | Proveedor: ${r.supplierName}');
    }
    if (r.invoiceNumber != null && r.invoiceNumber!.isNotEmpty) {
      msg.write(' | Factura: ${r.invoiceNumber}');
    }
    if (r.hasErrors) msg.write(' | Errores: ${r.errors.length}');

    setState(() {
      _resultMessage = msg.toString();
      _isError = r.hasErrors && r.totalProducts == 0;
      _errorDetails = r.errors;
    });
  }

  // ── Download Template ──
  Future<void> _downloadTemplate() async {
    setState(() { _isLoading = true; _resultMessage = null; });
    try {
      final service = ExcelImportService(widget.db);
      final bytes = await service.generateTemplateBytes();

      if (kIsWeb) {
        // On web, saveFile triggers browser download directly
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar plantilla de productos',
          fileName: 'plantilla_productos.xlsx',
          bytes: Uint8List.fromList(bytes),
        );
        setState(() {
          _resultMessage = savePath != null ? 'Plantilla descargada' : 'Descarga cancelada';
          _isError = savePath == null;
        });
      } else {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar plantilla de productos',
          fileName: 'plantilla_productos.xlsx',
          type: FileType.any,
        );
        if (savePath == null) {
          setState(() => _isLoading = false);
          return;
        }
        final finalPath = savePath.endsWith('.xlsx') ? savePath : '$savePath.xlsx';
        await File(finalPath).writeAsBytes(bytes);
        setState(() {
          _resultMessage = 'Plantilla guardada en: $finalPath';
          _isError = false;
        });
      }
    } catch (e) {
      setState(() { _resultMessage = 'Error: $e'; _isError = true; });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Import Excel ──
  Future<void> _importExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Seleccionar archivo Excel de productos',
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (!file.name.toLowerCase().endsWith('.xlsx') && !file.name.toLowerCase().endsWith('.xls')) {
        setState(() {
          _resultMessage = 'Selecciona un archivo Excel (.xlsx o .xls)';
          _isError = true;
        });
        return;
      }

      List<int>? bytes;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _resultMessage = 'No se pudo leer el archivo';
          _isError = true;
        });
        return;
      }

      setState(() { _isLoading = true; _resultMessage = null; _errorDetails = []; });
      final importResult = await _smartService.importExcel(bytes);
      _showResult(importResult);
    } catch (e) {
      setState(() {
        _resultMessage = 'Error al importar';
        _isError = true;
        _errorDetails = [e.toString()];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Export Excel ──
  Future<void> _exportExcel() async {
    setState(() { _isLoading = true; _resultMessage = null; });
    try {
      final service = ExcelImportService(widget.db);
      final path = await service.exportToExcel();
      setState(() { _resultMessage = 'Exportado en: $path'; _isError = false; });
    } catch (e) {
      setState(() { _resultMessage = 'Error: $e'; _isError = true; });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Import PDF ──
  Future<void> _importPdf() async {
    try {
      // Use FileType.any because FileType.custom has issues on macOS
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
        dialogTitle: 'Seleccionar facturas PDF',
      );
      if (result == null || result.files.isEmpty) return;

      final fileBytes = <List<int>>[];
      final names = <String>[];
      for (final file in result.files) {
        // Filter: only accept .pdf files
        if (!file.name.toLowerCase().endsWith('.pdf')) continue;

        List<int>? bytes;
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          bytes = file.bytes!;
        } else if (file.path != null) {
          try { bytes = await File(file.path!).readAsBytes(); } catch (_) {}
        }
        if (bytes != null && bytes.isNotEmpty) {
          fileBytes.add(bytes);
          names.add(file.name);
        }
      }

      if (fileBytes.isEmpty) {
        setState(() {
          _resultMessage = 'No se seleccionaron archivos PDF válidos (.pdf)';
          _isError = true;
        });
        return;
      }

      setState(() { _isLoading = true; _resultMessage = null; _errorDetails = []; });

      final pdfService = PdfInvoicePreviewService(widget.db);
      var totalImported = 0;
      var totalUpdated = 0;
      final allErrors = <String>[];

      for (var i = 0; i < fileBytes.length; i++) {
        final preview = await pdfService.parsePdf(
          Uint8List.fromList(fileBytes[i]),
          fileName: names[i],
        );

        setState(() => _isLoading = false);

        if (!mounted) return;
        final confirmResult = await XmlInvoicePreviewDialog.show(
          context,
          preview: preview,
          service: pdfService,
        );

        if (confirmResult == null) {
          if (fileBytes.length == 1) {
            setState(() { _resultMessage = 'Importación cancelada'; _isError = false; });
            return;
          }
          continue;
        }

        totalImported += confirmResult.imported;
        totalUpdated += confirmResult.updated;
        allErrors.addAll(confirmResult.errors);

        setState(() => _isLoading = true);
      }

      setState(() => _isLoading = false);

      final msg = StringBuffer('[PDF] ');
      msg.write('Nuevos: $totalImported');
      if (totalUpdated > 0) msg.write(' | Actualizados: $totalUpdated');
      if (allErrors.isNotEmpty) msg.write(' | Errores: ${allErrors.length}');

      setState(() {
        _resultMessage = msg.toString();
        _isError = allErrors.isNotEmpty && (totalImported + totalUpdated) == 0;
        _errorDetails = allErrors;
      });
    } catch (e) {
      setState(() {
        _resultMessage = 'Error al importar PDF';
        _isError = true;
        _errorDetails = [e.toString()];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Import XML ──
  Future<void> _importXml() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
        dialogTitle: 'Seleccionar facturas XML',
      );
      if (result == null || result.files.isEmpty) return;

      final contents = <String>[];
      final names = <String>[];
      for (final file in result.files) {
        if (!file.name.toLowerCase().endsWith('.xml')) continue;
        String? content;
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          content = utf8.decode(file.bytes!, allowMalformed: true);
        } else if (file.path != null) {
          try { content = await File(file.path!).readAsString(); } catch (_) {}
        }
        if (content != null && content.trim().isNotEmpty) {
          contents.add(content);
          names.add(file.name);
        }
      }

      if (contents.isEmpty) {
        setState(() {
          _resultMessage = 'No se seleccionaron archivos XML válidos (.xml)';
          _isError = true;
        });
        return;
      }

      setState(() { _isLoading = true; _resultMessage = null; _errorDetails = []; });

      // Use preview service for each XML
      final previewService = XmlInvoicePreviewService(widget.db);
      var totalImported = 0;
      var totalUpdated = 0;
      final allErrors = <String>[];

      for (var i = 0; i < contents.length; i++) {
        final preview = await previewService.parseXml(contents[i], fileName: names[i]);

        setState(() => _isLoading = false);

        // Show preview dialog
        if (!mounted) return;
        final confirmResult = await XmlInvoicePreviewDialog.show(
          context,
          preview: preview,
          service: previewService,
        );

        if (confirmResult == null) {
          // User cancelled this file
          if (contents.length == 1) {
            setState(() { _resultMessage = 'Importación cancelada'; _isError = false; });
            return;
          }
          continue;
        }

        totalImported += confirmResult.imported;
        totalUpdated += confirmResult.updated;
        allErrors.addAll(confirmResult.errors);

        setState(() => _isLoading = true);
      }

      setState(() => _isLoading = false);

      // Show final result
      final msg = StringBuffer('[XML] ');
      msg.write('Nuevos: $totalImported');
      if (totalUpdated > 0) msg.write(' | Actualizados: $totalUpdated');
      if (allErrors.isNotEmpty) msg.write(' | Errores: ${allErrors.length}');

      setState(() {
        _resultMessage = msg.toString();
        _isError = allErrors.isNotEmpty && (totalImported + totalUpdated) == 0;
        _errorDetails = allErrors;
      });
    } catch (e) {
      setState(() {
        _resultMessage = 'Error al importar XML';
        _isError = true;
        _errorDetails = [e.toString()];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

}
