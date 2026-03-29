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
  }

  void _calculateSalePrice() {
    final cost = double.tryParse(_costPriceCtrl.text) ?? 0;
    final margin = double.tryParse(_marginCtrl.text) ?? 0;
    if (cost > 0) {
      final sale = cost * (1 + margin / 100);
      _salePriceCtrl.text = sale.toStringAsFixed(2);
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

    // Calculate margin from cost/sale
    if (product.costPrice > 0) {
      final margin =
          ((product.salePrice - product.costPrice) / product.costPrice) * 100;
      _marginCtrl.text = margin.toStringAsFixed(2);
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
              color: AppColors.surfaceLight,
              child: TabBar(
                controller: _tabController,
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
            const Divider(height: 1),

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
      height: 52,
      decoration: const BoxDecoration(gradient: AppGradients.golden),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
            onPressed: () => context.go('/products'),
            tooltip: 'Volver',
          ),
          const SizedBox(width: 8),
          Icon(
            _isEditing ? LucideIcons.pencil : LucideIcons.plusCircle,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            _isEditing ? 'EDITAR PRODUCTO' : 'NUEVO PRODUCTO',
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          if (_isEditing)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'ID: ${widget.productId!.substring(0, 8)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: Colors.white,
                ),
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
                            decoration: InputDecoration(
                              labelText: 'Categoría / Departamento',
                              prefixIcon: const Icon(LucideIcons.folderOpen,
                                  size: 18),
                              labelStyle: GoogleFonts.inter(fontSize: 14),
                            ),
                            isExpanded: true,
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppColors.textPrimaryLight),
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
                  decoration: InputDecoration(
                    labelText: 'Unidad de Medida',
                    prefixIcon: const Icon(LucideIcons.ruler, size: 18),
                    labelStyle: GoogleFonts.inter(fontSize: 14),
                  ),
                  isExpanded: true,
                  style: GoogleFonts.inter(
                      fontSize: 14, color: AppColors.textPrimaryLight),
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
    final marginPct = cost > 0 ? ((sale - cost) / cost * 100) : 0.0;
    final profit = sale - cost;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              // Pricing
              _section('Precios', LucideIcons.dollarSign, [
                // Cost + Margin row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        controller: _costPriceCtrl,
                        label: 'Precio de Costo *',
                        prefix: r'$ ',
                        isNumeric: true,
                        validator: (v) =>
                            v?.isEmpty ?? true ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        controller: _marginCtrl,
                        label: 'Ganancia %',
                        suffix: '%',
                        isNumeric: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        controller: _salePriceCtrl,
                        label: 'Precio de Venta *',
                        prefix: r'$ ',
                        isNumeric: true,
                        validator: (v) =>
                            v?.isEmpty ?? true ? 'Requerido' : null,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _wholesalePriceCtrl,
                        label: 'Precio Mayoreo',
                        prefix: r'$ ',
                        isNumeric: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(child: SizedBox()),
                    const SizedBox(width: 16),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ]),
              const SizedBox(height: 16),

              // Profit summary card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.05),
                      AppColors.primaryLight.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    _profitItem('Costo', cost.currency, LucideIcons.arrowDown,
                        AppColors.error),
                    _profitDivider(),
                    _profitItem('Venta', sale.currency, LucideIcons.arrowUp,
                        AppColors.primary),
                    _profitDivider(),
                    _profitItem(
                        'Ganancia',
                        profit.currency,
                        LucideIcons.trendingUp,
                        profit > 0 ? AppColors.success : AppColors.error),
                    _profitDivider(),
                    _profitItem(
                        'Margen',
                        '${marginPct.toStringAsFixed(1)}%',
                        LucideIcons.percent,
                        AppColors.secondary),
                  ],
                ),
              ),
              const SizedBox(height: 16),

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
                            'IVA 15% se aplicará al precio de venta. PVP con IVA: ${(sale * 1.15).currency}',
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
                        decoration: InputDecoration(
                          labelText: 'Presentación',
                          prefixIcon:
                              const Icon(LucideIcons.pill, size: 18),
                          labelStyle: GoogleFonts.inter(fontSize: 14),
                        ),
                        isExpanded: true,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppColors.textPrimaryLight),
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
                        decoration: InputDecoration(
                          labelText: 'Vía de Administración',
                          prefixIcon: const Icon(LucideIcons.syringe,
                              size: 18),
                          labelStyle: GoogleFonts.inter(fontSize: 14),
                        ),
                        isExpanded: true,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppColors.textPrimaryLight),
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
                  decoration: InputDecoration(
                    labelText: 'Condiciones de Almacenamiento',
                    prefixIcon:
                        const Icon(LucideIcons.thermometer, size: 18),
                    labelStyle: GoogleFonts.inter(fontSize: 14),
                  ),
                  isExpanded: true,
                  style: GoogleFonts.inter(
                      fontSize: 14, color: AppColors.textPrimaryLight),
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
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        border:
            const Border(top: BorderSide(color: AppColors.borderLight)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Tab navigation
          TextButton.icon(
            onPressed: () {
              if (_tabController.index > 0) {
                _tabController.animateTo(_tabController.index - 1);
              }
            },
            icon: const Icon(LucideIcons.arrowLeft, size: 16),
            label: const Text('Anterior'),
          ),
          TextButton.icon(
            onPressed: () {
              if (_tabController.index < 3) {
                _tabController.animateTo(_tabController.index + 1);
              }
            },
            icon: const Icon(LucideIcons.arrowRight, size: 16),
            label: const Text('Siguiente'),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => context.go('/products'),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── HELPERS ──
  // ══════════════════════════════════════════════════════════════
  Widget _section(String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: c,
                )),
          ],
        ),
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
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        labelStyle: GoogleFonts.inter(fontSize: 14),
      ),
      style: GoogleFonts.inter(fontSize: 14),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: value ? c.withValues(alpha: 0.04) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value ? c.withValues(alpha: 0.3) : AppColors.borderLight,
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 20, color: value ? c : AppColors.textTertiaryLight),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textSecondaryLight)),
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
