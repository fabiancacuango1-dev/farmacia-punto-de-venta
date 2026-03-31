import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';
import '../../../services/auth/auth_service.dart';

// ── Pharmacy constants ──
const _presentations = [
  'Tableta', 'Cápsula', 'Gragea', 'Comprimido',
  'Jarabe', 'Suspensión', 'Solución Oral', 'Gotas Orales',
  'Inyectable', 'Ampolla', 'Vial',
  'Crema', 'Pomada', 'Ungüento', 'Gel', 'Loción',
  'Gotas Oftálmicas', 'Gotas Óticas',
  'Supositorio', 'Óvulo',
  'Aerosol', 'Inhalador', 'Nebulización',
  'Polvo', 'Granulado', 'Sobre',
  'Parche Transdérmico', 'Spray Nasal',
  'Otro',
];

const _adminRoutes = [
  'Oral', 'Tópica', 'Intramuscular', 'Intravenosa',
  'Subcutánea', 'Oftálmica', 'Ótica', 'Nasal',
  'Rectal', 'Vaginal', 'Inhalatoria', 'Sublingual',
  'Transdérmica', 'Otra',
];

const _storageConditions = [
  'Temperatura ambiente (15-25°C)',
  'Refrigerado (2-8°C)',
  'Congelado (-20°C)',
  'Proteger de la luz',
  'Ambiente seco',
  'No requiere condiciones especiales',
];

const _units = [
  'unidad', 'caja', 'frasco', 'tubo', 'sobre',
  'ampolla', 'vial', 'blíster', 'tira', 'rollo',
  'litro', 'galón', 'gramo', 'kilogramo',
];

const _saleTypes = ['Unidad/Pieza', 'A Granel (Decimales)', 'Paquete/Kit'];

class ProductFormScreen extends ConsumerStatefulWidget {
  final String? productId;
  const ProductFormScreen({super.key, this.productId});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;

  // ── Basic ──
  final _barcodeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _genericNameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _laboratoryCtrl = TextEditingController();
  final _internalCodeCtrl = TextEditingController();

  // ── Prices ──
  final _costPriceCtrl = TextEditingController(text: '0.00');
  final _marginCtrl = TextEditingController(text: '30.00');
  final _salePriceCtrl = TextEditingController(text: '0.00');
  final _wholesalePriceCtrl = TextEditingController();
  final _price2Ctrl = TextEditingController();
  final _price3Ctrl = TextEditingController();
  final _margin2Ctrl = TextEditingController();
  final _margin3Ctrl = TextEditingController();
  final _marginWholesaleCtrl = TextEditingController();
  final _costPerBoxCtrl = TextEditingController(text: '0.00');
  final _unitsPerBoxCtrl = TextEditingController(text: '1');

  // ── Pharmacy ──
  final _concentrationCtrl = TextEditingController();
  final _registroSanitarioCtrl = TextEditingController();
  final _storageNotesCtrl = TextEditingController();

  // ── Stock ──
  final _minStockCtrl = TextEditingController(text: '10');
  final _maxStockCtrl = TextEditingController(text: '100');
  final _currentStockCtrl = TextEditingController(text: '0');

  // ── Location ──
  final _locationCtrl = TextEditingController();
  final _shelfCtrl = TextEditingController();

  // ── Batch ──
  final _batchNumberCtrl = TextEditingController();
  final _batchQtyCtrl = TextEditingController();

  // ── State ──
  String? _selectedCategoryId;
  String _unit = 'unidad';
  String _saleType = 'Unidad/Pieza';
  String? _selectedPresentation;
  String? _selectedAdminRoute;
  String _storageCondition = 'No requiere condiciones especiales';
  bool _requiresPrescription = false;
  bool _isControlled = false;
  bool _isTaxExempt = false;
  bool _usesInventory = true;
  bool _allowFractions = false;
  bool _isLoading = false;
  DateTime? _batchExpiry;

  bool get _isEditing => widget.productId != null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    if (_isEditing) _loadProduct();

    // Auto-calculate sale price when cost or margin changes
    _costPriceCtrl.addListener(_calculateSalePrice);
    _marginCtrl.addListener(_calculateSalePrice);
    _costPerBoxCtrl.addListener(_calculateFromBox);
    _unitsPerBoxCtrl.addListener(_calculateFromBox);
    _margin2Ctrl.addListener(_calculatePrice2);
    _margin3Ctrl.addListener(_calculatePrice3);
    _marginWholesaleCtrl.addListener(_calculateWholesalePrice);
  }

  void _calculateSalePrice() {
    final cost = double.tryParse(_costPriceCtrl.text) ?? 0;
    final margin = double.tryParse(_marginCtrl.text) ?? 0;
    if (cost > 0) {
      final sale = cost * (1 + margin / 100);
      _salePriceCtrl.text = sale.toStringAsFixed(2);
    }
  }

  void _calculateFromBox() {
    final costBox = double.tryParse(_costPerBoxCtrl.text) ?? 0;
    final units = int.tryParse(_unitsPerBoxCtrl.text) ?? 1;
    if (costBox > 0 && units > 0) {
      final costUnit = costBox / units;
      _costPriceCtrl.removeListener(_calculateSalePrice);
      _costPriceCtrl.text = costUnit.toStringAsFixed(2);
      _costPriceCtrl.addListener(_calculateSalePrice);
      _calculateSalePrice();
    }
  }

  void _calculatePrice2() {
    final cost = double.tryParse(_costPriceCtrl.text) ?? 0;
    final margin = double.tryParse(_margin2Ctrl.text) ?? 0;
    if (cost > 0 && margin > 0) {
      _price2Ctrl.text = (cost * (1 + margin / 100)).toStringAsFixed(2);
    }
  }

  void _calculatePrice3() {
    final cost = double.tryParse(_costPriceCtrl.text) ?? 0;
    final margin = double.tryParse(_margin3Ctrl.text) ?? 0;
    if (cost > 0 && margin > 0) {
      _price3Ctrl.text = (cost * (1 + margin / 100)).toStringAsFixed(2);
    }
  }

  void _calculateWholesalePrice() {
    final cost = double.tryParse(_costPriceCtrl.text) ?? 0;
    final margin = double.tryParse(_marginWholesaleCtrl.text) ?? 0;
    if (cost > 0 && margin > 0) {
      _wholesalePriceCtrl.text = (cost * (1 + margin / 100)).toStringAsFixed(2);
    }
  }

  Future<void> _loadProduct() async {
    final db = ref.read(appDatabaseProvider);
    final product = await db.productsDao.getProductById(widget.productId!);
    if (product == null) return;

    _barcodeCtrl.text = product.barcode ?? '';
    _nameCtrl.text = product.name;
    _genericNameCtrl.text = product.genericName ?? '';
    _descriptionCtrl.text = product.description ?? '';
    _laboratoryCtrl.text = product.laboratory ?? '';
    _internalCodeCtrl.text = product.internalCode ?? '';
    _costPriceCtrl.text = product.costPrice.toStringAsFixed(2);
    _salePriceCtrl.text = product.salePrice.toStringAsFixed(2);
    _wholesalePriceCtrl.text = product.wholesalePrice?.toStringAsFixed(2) ?? '';
    _price2Ctrl.text = product.price2?.toStringAsFixed(2) ?? '';
    _price3Ctrl.text = product.price3?.toStringAsFixed(2) ?? '';
    _unitsPerBoxCtrl.text = product.unitsPerBox.toString();
    _costPerBoxCtrl.text = product.costPerBox.toStringAsFixed(2);
    _allowFractions = product.allowFractions;
    _concentrationCtrl.text = product.concentration ?? '';
    _minStockCtrl.text = product.minStock.toStringAsFixed(0);
    _maxStockCtrl.text = product.maxStock?.toStringAsFixed(0) ?? '100';
    _currentStockCtrl.text = product.currentStock.toStringAsFixed(0);
    _selectedCategoryId = product.categoryId;
    _unit = product.unit;
    _selectedPresentation = product.presentation;
    _requiresPrescription = product.requiresPrescription;
    _isTaxExempt = product.isTaxExempt;
    _isControlled = product.isControlled;
    _selectedAdminRoute = product.adminRoute;
    _saleType = product.saleType;
    _storageCondition = product.storageCondition ?? 'No requiere condiciones especiales';
    _storageNotesCtrl.text = product.storageNotes ?? '';
    _registroSanitarioCtrl.text = product.registroSanitario ?? '';
    _usesInventory = product.usesInventory;
    _locationCtrl.text = product.location ?? '';
    _shelfCtrl.text = product.shelf ?? '';

    // Calculate margins from cost and prices
    if (product.costPrice > 0) {
      final margin =
          ((product.salePrice - product.costPrice) / product.costPrice) * 100;
      _marginCtrl.text = margin.toStringAsFixed(2);

      if (product.wholesalePrice != null && product.wholesalePrice! > 0) {
        final mW = ((product.wholesalePrice! - product.costPrice) / product.costPrice) * 100;
        _marginWholesaleCtrl.text = mW.toStringAsFixed(2);
      }
      if (product.price2 != null && product.price2! > 0) {
        final m2 = ((product.price2! - product.costPrice) / product.costPrice) * 100;
        _margin2Ctrl.text = m2.toStringAsFixed(2);
      }
      if (product.price3 != null && product.price3! > 0) {
        final m3 = ((product.price3! - product.costPrice) / product.costPrice) * 100;
        _margin3Ctrl.text = m3.toStringAsFixed(2);
      }
    }

    setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _barcodeCtrl.dispose();
    _nameCtrl.dispose();
    _genericNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _laboratoryCtrl.dispose();
    _internalCodeCtrl.dispose();
    _costPriceCtrl.dispose();
    _marginCtrl.dispose();
    _salePriceCtrl.dispose();
    _wholesalePriceCtrl.dispose();
    _price2Ctrl.dispose();
    _price3Ctrl.dispose();
    _margin2Ctrl.dispose();
    _margin3Ctrl.dispose();
    _marginWholesaleCtrl.dispose();
    _costPerBoxCtrl.dispose();
    _unitsPerBoxCtrl.dispose();
    _concentrationCtrl.dispose();
    _registroSanitarioCtrl.dispose();
    _storageNotesCtrl.dispose();
    _minStockCtrl.dispose();
    _maxStockCtrl.dispose();
    _currentStockCtrl.dispose();
    _locationCtrl.dispose();
    _shelfCtrl.dispose();
    _batchNumberCtrl.dispose();
    _batchQtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // ── Golden Header ──
            _buildHeader(),

            // ── Tab Bar ──
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TabBar(
                controller: _tabController,
                labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
                labelColor: AppColors.primary,
                unselectedLabelColor: const Color(0xFF94A3B8),
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                tabs: const [
                  Tab(
                    icon: Icon(LucideIcons.package, size: 16),
                    text: 'Producto',
                  ),
                  Tab(
                    icon: Icon(LucideIcons.dollarSign, size: 16),
                    text: 'Precios y Venta',
                  ),
                  Tab(
                    icon: Icon(LucideIcons.heartPulse, size: 16),
                    text: 'Farmacología',
                  ),
                  Tab(
                    icon: Icon(LucideIcons.warehouse, size: 16),
                    text: 'Inventario',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // ── Tab Content ──
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildProductTab(db),
                  _buildPricingTab(),
                  _buildPharmacyTab(),
                  _buildInventoryTab(db),
                ],
              ),
            ),

            // ── Action Bar ──
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── HEADER ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF2563EB), Color(0xFF3B82F6)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.go('/products'),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(LucideIcons.arrowLeft, color: Colors.white, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isEditing ? LucideIcons.pencil : LucideIcons.plusCircle,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _isEditing ? 'EDITAR PRODUCTO' : 'NUEVO PRODUCTO',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_isEditing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.fingerprint, color: Colors.white70, size: 13),
                  const SizedBox(width: 6),
                  Text(
                    'ID: ${widget.productId!.substring(0, 8)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── TAB 1: PRODUCTO ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildProductTab(AppDatabase db) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              // Barcode + Internal Code
              _section('Identificación', LucideIcons.scanLine, [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _field(
                        controller: _barcodeCtrl,
                        label: 'Código de Barras',
                        icon: LucideIcons.scanLine,
                        hint: 'Escanear o escribir...',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        controller: _internalCodeCtrl,
                        label: 'Código Interno',
                        icon: LucideIcons.hash,
                      ),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 16),

              // Description
              _section('Información del Producto', LucideIcons.info, [
                _field(
                  controller: _nameCtrl,
                  label: 'Nombre Comercial *',
                  icon: LucideIcons.tag,
                  validator: (v) =>
                      v?.isEmpty ?? true ? 'Campo requerido' : null,
                ),
                _field(
                  controller: _genericNameCtrl,
                  label: 'Nombre Genérico / Principio Activo',
                  icon: LucideIcons.testTubes,
                  hint: 'Ej: Paracetamol, Ibuprofeno, Amoxicilina',
                ),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _laboratoryCtrl,
                        label: 'Laboratorio / Fabricante',
                        icon: LucideIcons.building2,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: StreamBuilder<List<Category>>(
                        stream: db.productsDao.watchCategories(),
                        builder: (context, snap) {
                          final cats = snap.data ?? [];
                          return DropdownButtonFormField<String>(
                            value: _selectedCategoryId,
                            decoration: _dropdownDecoration(
                              'Categoría / Departamento',
                              LucideIcons.folderOpen,
                            ),
                            isExpanded: true,
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF1E293B)),
                            items: [
                              const DropdownMenuItem(
                                  value: null,
                                  child: Text('Sin categoría')),
                              ...cats.map((c) => DropdownMenuItem(
                                  value: c.id, child: Text(c.name))),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedCategoryId = v),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                _field(
                  controller: _descriptionCtrl,
                  label: 'Descripción / Notas',
                  maxLines: 2,
                ),
              ]),
              const SizedBox(height: 16),

              // Sale Type
              _section('Tipo de Venta', LucideIcons.shoppingBag, [
                Row(
                  children: [
                    ..._saleTypes.map((type) {
                      final selected = _saleType == type;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () =>
                                setState(() => _saleType = type),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primary
                                        .withValues(alpha: 0.1)
                                    : AppColors.backgroundLight,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.borderLight,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    type.contains('Unidad')
                                        ? LucideIcons.box
                                        : type.contains('Granel')
                                            ? LucideIcons.scale
                                            : LucideIcons.packageCheck,
                                    size: 22,
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.textSecondaryLight,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    type,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.textSecondaryLight,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _unit,
                  decoration: _dropdownDecoration(
                    'Unidad de Medida',
                    LucideIcons.ruler,
                  ),
                  isExpanded: true,
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)),
                  items: _units
                      .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(u[0].toUpperCase() + u.substring(1))))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _unit = v ?? 'unidad'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── TAB 2: PRECIOS Y VENTA ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildPricingTab() {
    final cost = double.tryParse(_costPriceCtrl.text) ?? 0;
    final sale = double.tryParse(_salePriceCtrl.text) ?? 0;
    final costBox = double.tryParse(_costPerBoxCtrl.text) ?? 0;
    final units = int.tryParse(_unitsPerBoxCtrl.text) ?? 1;
    final marginPct = cost > 0 ? ((sale - cost) / cost * 100) : 0.0;
    final profit = sale - cost;
    final profitBox = units > 1 ? (sale * units) - costBox : profit;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              // ── Empaque / Caja ──
              _section('Empaque y Unidades', LucideIcons.package, [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _field(
                        controller: _costPerBoxCtrl,
                        label: 'Costo Total de Caja/Empaque *',
                        prefix: r'$ ',
                        isNumeric: true,
                        hint: 'Ej: 8.80 (lo que pagas por la caja)',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        controller: _unitsPerBoxCtrl,
                        label: 'Unidades por Caja',
                        icon: LucideIcons.layers,
                        isNumeric: true,
                        hint: 'Ej: 20',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Costo por Unidad',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF475569))),
                            const SizedBox(height: 4),
                            Text(
                              cost > 0 ? '\$ ${cost.toStringAsFixed(4)}' : '\$ 0.00',
                              style: GoogleFonts.poppins(
                                  fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                            ),
                            if (units > 1)
                              Text(
                                '${costBox.toStringAsFixed(2)} ÷ $units = ${cost.toStringAsFixed(4)}',
                                style: GoogleFonts.jetBrainsMono(fontSize: 10, color: const Color(0xFF64748B)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _switchTile(
                  'Venta Fraccionada',
                  'Permite vender por unidad individual y por caja completa',
                  _allowFractions,
                  (v) => setState(() => _allowFractions = v),
                  icon: LucideIcons.scissors,
                ),
                if (_allowFractions && units > 1)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.info, size: 16, color: AppColors.info),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'En el POS se podrá vender 1 unidad a \$${sale.toStringAsFixed(2)} '
                            'o la caja de $units unidades a \$${(sale * units).toStringAsFixed(2)}',
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.info),
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // ── Precios por Nivel de Utilidad ──
              _section('Precios por Nivel de Utilidad', LucideIcons.trendingUp, [
                // Precio 1 (Principal)
                _priceTierRow(
                  tierLabel: 'Precio Principal',
                  tierColor: const Color(0xFF2563EB),
                  tierIcon: LucideIcons.star,
                  marginCtrl: _marginCtrl,
                  priceCtrl: _salePriceCtrl,
                  cost: cost,
                  hint: 'Precio al público / regular',
                ),
                const Divider(height: 24),

                // Precio Mayoreo (Caja completa)
                _priceTierRow(
                  tierLabel: 'Precio Mayoreo / Caja',
                  tierColor: const Color(0xFF059669),
                  tierIcon: LucideIcons.packageCheck,
                  marginCtrl: _marginWholesaleCtrl,
                  priceCtrl: _wholesalePriceCtrl,
                  cost: cost,
                  hint: 'Precio por caja completa o mayoreo',
                ),
                const Divider(height: 24),

                // Precio 2 (Descuento)
                _priceTierRow(
                  tierLabel: 'Precio Descuento (Nivel 2)',
                  tierColor: const Color(0xFFD97706),
                  tierIcon: LucideIcons.tag,
                  marginCtrl: _margin2Ctrl,
                  priceCtrl: _price2Ctrl,
                  cost: cost,
                  hint: 'Ej: clientes frecuentes, 20% desc.',
                ),
                const Divider(height: 24),

                // Precio 3 (Descuento máximo)
                _priceTierRow(
                  tierLabel: 'Precio Mínimo (Nivel 3)',
                  tierColor: const Color(0xFFDC2626),
                  tierIcon: LucideIcons.arrowDownCircle,
                  marginCtrl: _margin3Ctrl,
                  priceCtrl: _price3Ctrl,
                  cost: cost,
                  hint: 'Ej: descuento máximo permitido',
                ),
              ]),
              const SizedBox(height: 16),

              // ── Resumen de Utilidad ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF2563EB).withValues(alpha: 0.04),
                      const Color(0xFF7C3AED).withValues(alpha: 0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.barChart3, size: 16, color: const Color(0xFF2563EB)),
                        const SizedBox(width: 8),
                        Text('Resumen de Rentabilidad',
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _profitItem('Costo Unit.', cost > 0 ? cost.currency : '\$0.00',
                            LucideIcons.arrowDown, AppColors.error),
                        _profitDivider(),
                        _profitItem('Venta', sale > 0 ? sale.currency : '\$0.00',
                            LucideIcons.arrowUp, AppColors.primary),
                        _profitDivider(),
                        _profitItem(
                            'Ganancia',
                            profit > 0 ? profit.currency : '\$0.00',
                            LucideIcons.trendingUp,
                            profit > 0 ? AppColors.success : AppColors.error),
                        _profitDivider(),
                        _profitItem(
                            'Utilidad',
                            '${marginPct.toStringAsFixed(1)}%',
                            LucideIcons.percent,
                            AppColors.secondary),
                      ],
                    ),
                    if (units > 1) ...[
                      const Divider(height: 20),
                      Row(
                        children: [
                          _profitItem('Costo Caja',
                              costBox > 0 ? costBox.currency : '\$0.00',
                              LucideIcons.package, const Color(0xFF475569)),
                          _profitDivider(),
                          _profitItem('Venta Caja',
                              (sale * units).currency,
                              LucideIcons.packageCheck, AppColors.primary),
                          _profitDivider(),
                          _profitItem('Ganancia Caja',
                              profitBox > 0 ? profitBox.currency : '\$0.00',
                              LucideIcons.trendingUp,
                              profitBox > 0 ? AppColors.success : AppColors.error),
                          _profitDivider(),
                          _profitItem(
                              '$units unidades',
                              'por caja',
                              LucideIcons.layers,
                              const Color(0xFF7C3AED)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Stock Inicial (solo al crear) ──
              if (!_isEditing)
                _section('Stock Inicial', LucideIcons.packagePlus, [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _field(
                          controller: _currentStockCtrl,
                          label: '¿Cuántas unidades ingresan?',
                          icon: LucideIcons.package,
                          isNumeric: true,
                          hint: 'Ej: 50',
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Quick-fill buttons
                      ...([1, 10, 50, 100]).map((n) => Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 2),
                        child: _QuickStockChip(
                          label: n.toString(),
                          onTap: () => setState(() => _currentStockCtrl.text = n.toString()),
                          isSelected: _currentStockCtrl.text == n.toString(),
                        ),
                      )),
                    ],
                  ),
                  if (units > 1) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.calculator, size: 16, color: Color(0xFF7C3AED)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_currentStockCtrl.text.isEmpty ? "0" : _currentStockCtrl.text} unidades = '
                              '${((int.tryParse(_currentStockCtrl.text) ?? 0) / units).toStringAsFixed(1)} cajas '
                              'de $units unidades',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF7C3AED)),
                            ),
                          ),
                          // Quick fill by boxes
                          TextButton.icon(
                            onPressed: () {
                              final boxes = int.tryParse(_currentStockCtrl.text) ?? 0;
                              setState(() => _currentStockCtrl.text = (boxes > 0 ? boxes * units : units).toString());
                            },
                            icon: const Icon(LucideIcons.package, size: 14),
                            label: Text('× Caja', style: GoogleFonts.inter(fontSize: 11)),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF7C3AED),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: _minStockCtrl,
                          label: 'Stock Mínimo (alerta)',
                          icon: LucideIcons.bellRing,
                          isNumeric: true,
                          hint: '10',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _field(
                          controller: _maxStockCtrl,
                          label: 'Stock Máximo',
                          icon: LucideIcons.arrowUp,
                          isNumeric: true,
                          hint: '100',
                        ),
                      ),
                    ],
                  ),
                ]),
              if (!_isEditing) const SizedBox(height: 16),

              // Tax settings
              _section('Impuestos', LucideIcons.receipt, [
                Row(
                  children: [
                    Expanded(
                      child: _switchTile(
                        'Exento de IVA',
                        'Producto no grava IVA (15%)',
                        _isTaxExempt,
                        (v) => setState(() => _isTaxExempt = v),
                        icon: LucideIcons.percent,
                      ),
                    ),
                  ],
                ),
                if (!_isTaxExempt)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.info,
                            size: 16, color: AppColors.info),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'IVA 15% se aplicará al precio de venta. PVP con IVA: ${(sale * 1.15).currency}'
                            '${units > 1 ? " | Caja con IVA: ${(sale * units * 1.15).currency}" : ""}',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: AppColors.info),
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// Row for each price tier: [Badge] [Margin %] → [Price $] [Utility info]
  Widget _priceTierRow({
    required String tierLabel,
    required Color tierColor,
    required IconData tierIcon,
    required TextEditingController marginCtrl,
    required TextEditingController priceCtrl,
    required double cost,
    String? hint,
  }) {
    final price = double.tryParse(priceCtrl.text) ?? 0;
    final marginPct = cost > 0 && price > 0 ? ((price - cost) / cost * 100) : 0.0;
    final profitUnit = price - cost;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tierIcon, size: 13, color: tierColor),
                  const SizedBox(width: 4),
                  Text(tierLabel,
                      style: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w600, color: tierColor)),
                ],
              ),
            ),
            if (hint != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(hint,
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: _field(
                controller: marginCtrl,
                label: 'Utilidad %',
                suffix: '%',
                isNumeric: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Icon(LucideIcons.arrowRight, size: 18, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 140,
              child: _field(
                controller: priceCtrl,
                label: 'Precio \$',
                prefix: r'$ ',
                isNumeric: true,
              ),
            ),
            const SizedBox(width: 12),
            if (cost > 0 && price > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: profitUnit > 0
                          ? const Color(0xFF059669).withValues(alpha: 0.06)
                          : const Color(0xFFDC2626).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          profitUnit > 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                          size: 14,
                          color: profitUnit > 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Ganancia: \$${profitUnit.toStringAsFixed(2)} (${marginPct.toStringAsFixed(1)}%)',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: profitUnit > 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _profitItem(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w700, color: color),
          ),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.textSecondaryLight)),
        ],
      ),
    );
  }

  Widget _profitDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.borderLight,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── TAB 3: FARMACOLOGÍA ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildPharmacyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              // Pharmaceutical Info
              _section(
                  'Datos Farmacéuticos', LucideIcons.heartPulse, [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedPresentation,
                        decoration: _dropdownDecoration('Presentación', LucideIcons.pill),
                        isExpanded: true,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1E293B)),
                        items: _presentations
                            .map((p) =>
                                DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedPresentation = v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        controller: _concentrationCtrl,
                        label: 'Concentración / Dosis',
                        icon: LucideIcons.beaker,
                        hint: 'Ej: 500mg, 10ml/5ml, 20mg/ml',
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedAdminRoute,
                        decoration: _dropdownDecoration('Vía de Administración', LucideIcons.syringe),
                        isExpanded: true,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1E293B)),
                        items: _adminRoutes
                            .map((r) =>
                                DropdownMenuItem(value: r, child: Text(r)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedAdminRoute = v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        controller: _registroSanitarioCtrl,
                        label: 'Registro Sanitario (ARCSA)',
                        icon: LucideIcons.shield,
                        hint: 'Ej: ARCSA-2024-XXXX',
                      ),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 16),

              // Control & Prescription
              _section('Control y Receta', LucideIcons.fileText, [
                Row(
                  children: [
                    Expanded(
                      child: _switchTile(
                        'Requiere Receta Médica',
                        'Venta solo con prescripción',
                        _requiresPrescription,
                        (v) =>
                            setState(() => _requiresPrescription = v),
                        icon: LucideIcons.fileText,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _switchTile(
                        'Sustancia Controlada',
                        'Bajo control estricto del MSP',
                        _isControlled,
                        (v) => setState(() => _isControlled = v),
                        icon: LucideIcons.alertTriangle,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
                if (_isControlled)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.alertOctagon,
                            color: AppColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'SUSTANCIA CONTROLADA: Requiere registro especial, '
                            'receta valorada y registro de dispensación según '
                            'normativa del MSP/ARCSA.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_requiresPrescription && !_isControlled)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              AppColors.warning.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.info,
                            color: AppColors.warning, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Este producto requiere receta médica para su dispensación. '
                            'El sistema solicitará el número de receta al venderlo.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // Storage
              _section(
                  'Almacenamiento', LucideIcons.thermometer, [
                DropdownButtonFormField<String>(
                  value: _storageCondition,
                  decoration: _dropdownDecoration('Condiciones de Almacenamiento', LucideIcons.thermometer),
                  isExpanded: true,
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)),
                  items: _storageConditions
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(
                      () => _storageCondition = v ?? _storageCondition),
                ),
                if (_storageCondition.contains('Refrigerado'))
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.snowflake,
                            size: 16, color: AppColors.info),
                        const SizedBox(width: 8),
                        Text(
                          'Cadena de frío: Mantener entre 2°C y 8°C',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.info),
                        ),
                      ],
                    ),
                  ),
                _field(
                  controller: _storageNotesCtrl,
                  label: 'Notas de Almacenamiento',
                  maxLines: 2,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── TAB 4: INVENTARIO ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildInventoryTab(AppDatabase db) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              // Inventory toggle
              _section('Control de Inventario', LucideIcons.warehouse, [
                _switchTile(
                  'Este producto utiliza inventario',
                  'Controlar existencias y alertas de stock',
                  _usesInventory,
                  (v) => setState(() => _usesInventory = v),
                  icon: LucideIcons.packageCheck,
                  color: AppColors.primary,
                ),
              ]),
              const SizedBox(height: 16),

              // Location
              _section('Ubicación en Farmacia', LucideIcons.mapPin, [
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _locationCtrl,
                        label: 'Ubicación',
                        icon: LucideIcons.mapPin,
                        hint: 'Ej: Estante A, Vitrina 3, Refrigerador',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        controller: _shelfCtrl,
                        label: 'Pasillo / Anaquel / Gaveta',
                        icon: LucideIcons.layoutGrid,
                        hint: 'Ej: Pasillo 2, Anaquel B, Gaveta 5',
                      ),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 16),

              if (_usesInventory) ...[
                // Stock levels
                _section('Niveles de Stock', LucideIcons.barChart3, [
                  Row(
                    children: [
                      Expanded(
                        child: _stockField(
                          controller: _currentStockCtrl,
                          label: 'Stock Actual',
                          color: AppColors.primary,
                          icon: LucideIcons.package,
                          enabled: !_isEditing,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _stockField(
                          controller: _minStockCtrl,
                          label: 'Stock Mínimo',
                          color: AppColors.warning,
                          icon: LucideIcons.arrowDown,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _stockField(
                          controller: _maxStockCtrl,
                          label: 'Stock Máximo',
                          color: AppColors.info,
                          icon: LucideIcons.arrowUp,
                        ),
                      ),
                    ],
                  ),
                  // Visual stock bar
                  _buildStockIndicator(),
                ]),
                const SizedBox(height: 16),

                // Batch management
                if (_isEditing)
                  _section('Lotes y Caducidad', LucideIcons.layers, [
                    // Existing batches
                    FutureBuilder<List<ProductBatche>>(
                      future: db.productsDao
                          .getBatchesForProduct(widget.productId!),
                      builder: (ctx, snap) {
                        final batches = snap.data ?? [];
                        if (batches.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(LucideIcons.info,
                                    size: 16,
                                    color: AppColors.textTertiaryLight),
                                const SizedBox(width: 8),
                                Text(
                                  'Sin lotes registrados para este producto',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.textSecondaryLight,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return Column(
                          children: batches.map((b) {
                            final expired = b.expirationDate
                                .isBefore(DateTime.now());
                            final expiringSoon = b.expirationDate
                                .isExpiringWithin(90);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: expired
                                    ? AppColors.error
                                        .withValues(alpha: 0.05)
                                    : expiringSoon
                                        ? AppColors.warning
                                            .withValues(alpha: 0.05)
                                        : AppColors.backgroundLight,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: expired
                                      ? AppColors.error
                                          .withValues(alpha: 0.2)
                                      : expiringSoon
                                          ? AppColors.warning
                                              .withValues(alpha: 0.2)
                                          : AppColors.borderLight,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    expired
                                        ? LucideIcons.alertOctagon
                                        : LucideIcons.package,
                                    size: 18,
                                    color: expired
                                        ? AppColors.error
                                        : expiringSoon
                                            ? AppColors.warning
                                            : AppColors
                                                .textSecondaryLight,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Lote: ${b.batchNumber}',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Vence: ${b.expirationDate.formatted} • Cantidad: ${b.quantity.toInt()}',
                                          style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: AppColors
                                                  .textSecondaryLight),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (expired)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.error
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'VENCIDO',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const Divider(height: 24),
                    // Add new batch
                    Text(
                      'Agregar Nuevo Lote',
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            controller: _batchNumberCtrl,
                            label: 'Número de Lote',
                            icon: LucideIcons.hash,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: _pickBatchExpiry,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Fecha de Vencimiento',
                                prefixIcon: const Icon(
                                    LucideIcons.calendar, size: 18),
                                labelStyle:
                                    GoogleFonts.inter(fontSize: 14),
                              ),
                              child: Text(
                                _batchExpiry?.formatted ??
                                    'Seleccionar...',
                                style: GoogleFonts.inter(fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            controller: _batchQtyCtrl,
                            label: 'Cantidad',
                            icon: LucideIcons.hash,
                            isNumeric: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _addBatch,
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                  ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockIndicator() {
    final current = double.tryParse(_currentStockCtrl.text) ?? 0;
    final min = double.tryParse(_minStockCtrl.text) ?? 10;
    final max = double.tryParse(_maxStockCtrl.text) ?? 100;
    final pct = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;
    final color = current <= 0
        ? AppColors.error
        : current <= min
            ? AppColors.warning
            : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Nivel de Stock',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textSecondaryLight)),
              Text(
                current <= 0
                    ? 'SIN STOCK'
                    : current <= min
                        ? 'BAJO'
                        : 'NORMAL',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: AppColors.borderLight,
              color: color,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Mín: ${min.toInt()}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.textTertiaryLight)),
              Text('Actual: ${current.toInt()}',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color)),
              Text('Máx: ${max.toInt()}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.textTertiaryLight)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stockField({
    required TextEditingController controller,
    required String label,
    required Color color,
    required IconData icon,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color)),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
              fontSize: 24, fontWeight: FontWeight.w700, color: color),
          decoration: InputDecoration(
            filled: true,
            fillColor: color.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color, width: 2),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── ACTION BAR ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildActionBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.primary.withValues(alpha: 0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Tab navigation
          _navButton(
            icon: LucideIcons.arrowLeft,
            label: 'Anterior',
            onTap: () {
              if (_tabController.index > 0) {
                _tabController.animateTo(_tabController.index - 1);
              }
            },
          ),
          const SizedBox(width: 4),
          _navButton(
            icon: LucideIcons.arrowRight,
            label: 'Siguiente',
            iconRight: true,
            onTap: () {
              if (_tabController.index < 3) {
                _tabController.animateTo(_tabController.index + 1);
              }
            },
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => context.go('/products'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF64748B),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _save,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    _isEditing ? LucideIcons.save : LucideIcons.plus,
                    size: 18,
                  ),
            label: Text(_isEditing ? 'Guardar Cambios' : 'Crear Producto'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool iconRight = false,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF475569),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!iconRight) Icon(icon, size: 15),
          if (!iconRight) const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
          if (iconRight) const SizedBox(width: 6),
          if (iconRight) Icon(icon, size: 15),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── HELPERS ──
  // ══════════════════════════════════════════════════════════════

  InputDecoration _dropdownDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18, color: AppColors.primary.withValues(alpha: 0.6)),
      labelStyle: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF475569),
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with accent
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.06),
                  AppColors.primary.withValues(alpha: 0.02),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              border: Border(
                bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.12)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          // Section content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: children.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: c,
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? prefix,
    String? suffix,
    IconData? icon,
    bool isNumeric = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        suffixText: suffix,
        prefixIcon: icon != null
            ? Icon(icon, size: 18, color: AppColors.primary.withValues(alpha: 0.6))
            : null,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF475569),
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 13,
          color: const Color(0xFF94A3B8),
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF1E293B),
      ),
      keyboardType: isNumeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: isNumeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))]
          : null,
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _switchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged, {
    IconData? icon,
    Color? color,
  }) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value ? c.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value ? c.withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
          width: value ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: value ? c.withValues(alpha: 0.1) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: value ? c : const Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B))),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF64748B))),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: c,
          ),
        ],
      ),
    );
  }

  Future<void> _pickBatchExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _batchExpiry = picked);
  }

  Future<void> _addBatch() async {
    if (!_isEditing) return;
    final num = _batchNumberCtrl.text.trim();
    final qty = double.tryParse(_batchQtyCtrl.text);
    if (num.isEmpty || qty == null || _batchExpiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete todos los campos del lote'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final db = ref.read(appDatabaseProvider);
    await db.productsDao.insertBatch(ProductBatchesCompanion(
      id: Value(const Uuid().v4()),
      productId: Value(widget.productId!),
      batchNumber: Value(num),
      expirationDate: Value(_batchExpiry!),
      quantity: Value(qty),
    ));

    _batchNumberCtrl.clear();
    _batchQtyCtrl.clear();
    setState(() => _batchExpiry = null);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lote $num agregado'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── SAVE ──
  // ══════════════════════════════════════════════════════════════
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      _tabController.animateTo(0);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = ref.read(appDatabaseProvider);
      final user = ref.read(currentUserProvider)!;

      final product = ProductsCompanion(
        id: Value(_isEditing ? widget.productId! : const Uuid().v4()),
        barcode: Value(_barcodeCtrl.text.isEmpty ? null : _barcodeCtrl.text),
        internalCode: Value(
            _internalCodeCtrl.text.isEmpty ? null : _internalCodeCtrl.text),
        name: Value(_nameCtrl.text),
        genericName: Value(
            _genericNameCtrl.text.isEmpty ? null : _genericNameCtrl.text),
        description: Value(
            _descriptionCtrl.text.isEmpty ? null : _descriptionCtrl.text),
        categoryId: Value(_selectedCategoryId),
        presentation: Value(_selectedPresentation),
        concentration: Value(
            _concentrationCtrl.text.isEmpty
                ? null
                : _concentrationCtrl.text),
        laboratory: Value(
            _laboratoryCtrl.text.isEmpty ? null : _laboratoryCtrl.text),
        costPrice: Value(double.tryParse(_costPriceCtrl.text) ?? 0),
        salePrice: Value(double.tryParse(_salePriceCtrl.text) ?? 0),
        wholesalePrice:
            Value(double.tryParse(_wholesalePriceCtrl.text)),
        price2: Value(double.tryParse(_price2Ctrl.text)),
        price3: Value(double.tryParse(_price3Ctrl.text)),
        unitsPerBox: Value(int.tryParse(_unitsPerBoxCtrl.text) ?? 1),
        costPerBox: Value(double.tryParse(_costPerBoxCtrl.text) ?? 0),
        allowFractions: Value(_allowFractions),
        isTaxExempt: Value(_isTaxExempt),
        minStock: Value(double.tryParse(_minStockCtrl.text) ?? 10),
        maxStock: Value(double.tryParse(_maxStockCtrl.text)),
        unit: Value(_unit),
        requiresPrescription: Value(_requiresPrescription),
        isControlled: Value(_isControlled),
        adminRoute: Value(_selectedAdminRoute),
        saleType: Value(_saleType),
        storageCondition: Value(_storageCondition),
        storageNotes: Value(
            _storageNotesCtrl.text.isEmpty ? null : _storageNotesCtrl.text),
        registroSanitario: Value(
            _registroSanitarioCtrl.text.isEmpty ? null : _registroSanitarioCtrl.text),
        usesInventory: Value(_usesInventory),
        location: Value(_locationCtrl.text.isEmpty ? null : _locationCtrl.text),
        shelf: Value(_shelfCtrl.text.isEmpty ? null : _shelfCtrl.text),
        currentStock: _isEditing
            ? const Value.absent()
            : Value(double.tryParse(_currentStockCtrl.text) ?? 0),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      );

      if (_isEditing) {
        await db.productsDao.updateProduct(product);
      } else {
        await db.productsDao.insertProduct(product);
      }

      // Audit log
      await db.usersDao.logAction(
        userId: user.id,
        action: _isEditing ? 'edit_product' : 'create_product',
        targetTable: 'products',
        recordId: product.id.value,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Producto actualizado correctamente'
                  : 'Producto creado exitosamente',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: AppColors.success,
          ),
        );
        context.go('/products');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// ── Quick Stock Chip ──
class _QuickStockChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isSelected;
  const _QuickStockChip({required this.label, required this.onTap, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2563EB).withValues(alpha: 0.12)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2563EB).withValues(alpha: 0.4)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
