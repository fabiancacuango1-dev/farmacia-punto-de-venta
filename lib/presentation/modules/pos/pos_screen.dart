import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';
import '../../../services/auth/auth_service.dart';
import 'pos_providers.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.f2:
        _showSearchDialog();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f3:
        _showPriceDialog();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f4:
        _showEditItemDialog();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f5:
        _showQuantityDialog();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f6:
        _removeSelectedItem();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f7:
        _showDiscountDialog();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f8:
        _openCashDrawer();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f9:
        _holdCurrentSale();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f10:
        _showImportDialog();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f11:
        _showPaymentDialog();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
        _removeSelectedItem();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _barcodeFocusNode.requestFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.add:
      case LogicalKeyboardKey.numpadAdd:
        _incrementSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        _decrementSelected();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _incrementSelected() {
    final index = ref.read(selectedCartIndexProvider);
    final cart = ref.read(cartProvider);
    if (index == null || index >= cart.length) return;
    final item = cart[index];
    if (item.quantity + 1 <= item.product.currentStock) {
      ref.read(cartProvider.notifier).updateQuantity(item.product.id, item.quantity + 1);
    }
  }

  void _decrementSelected() {
    final index = ref.read(selectedCartIndexProvider);
    final cart = ref.read(cartProvider);
    if (index == null || index >= cart.length) return;
    final item = cart[index];
    ref.read(cartProvider.notifier).updateQuantity(item.product.id, item.quantity - 1);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final docType = ref.watch(documentTypeProvider);
    final customer = ref.watch(selectedCustomerProvider);
    final seller = ref.watch(selectedSellerProvider);
    final heldSales = ref.watch(heldSalesProvider);

    final subtotal = cart.fold<double>(0, (s, i) => s + i.subtotal);
    final taxTotal = cart.fold<double>(0, (s, i) => s + i.taxAmount);
    final discountTotal = cart.fold<double>(0, (s, i) => s + i.discountAmount);
    final grandTotal = cart.fold<double>(0, (s, i) => s + i.total);
    final totalItems = cart.fold<double>(0, (s, i) => s + i.quantity);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        backgroundColor: const Color(0xFFECEFF4),
        body: Column(
          children: [
            // 1) Top nav bar (brand + module tabs + user + salir)
            _buildTopNavBar(heldSales),
            // 2) Green title bar "VENTA DE PRODUCTOS - Ticket 1"
            _buildTitleBar(docType),
            // 3) Barcode input row
            _buildBarcodeInput(),
            // 4) Quick action buttons row
            _buildActionButtons(heldSales),
            // 5) Sales table (header + rows)
            Expanded(child: _buildSalesTable(cart)),
            // 6) Bottom bar: product count + F5/F6/Eliminar + F12 Cobrar + TOTAL
            _buildBottomBar(
              totalItems: totalItems,
              subtotal: subtotal,
              discountTotal: discountTotal,
              taxTotal: taxTotal,
              grandTotal: grandTotal,
            ),
            // 7) Footer: Total/Pagó Con/Cambio + utility buttons + timestamp
            _buildFooter(grandTotal: grandTotal),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 1) TOP NAV BAR — Brand + Module Tabs + User + Salir
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTopNavBar(List<HeldSale> heldSales) {
    final user = ref.watch(currentUserProvider);

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFDDE1E7), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Brand
          const Icon(Icons.local_pharmacy_rounded, color: Color(0xFF2563EB), size: 20),
          const SizedBox(width: 6),
          const Text('FarmaPos',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: -0.3,
              )),
          const SizedBox(width: 14),

          // Module tabs
          _navTab('F1 Ventas', true, () {}, icon: LucideIcons.receipt, iconColor: const Color(0xFF059669)),
          _navTab('F2 Clientes', false, _showCustomerLookup, icon: LucideIcons.users, iconColor: const Color(0xFFE67E22)),
          _navTab('F3 Productos', false, _showSearchDialog, icon: LucideIcons.box, iconColor: const Color(0xFF2563EB)),
          _navTab('F4 Inventario', false, () => context.go('/inventory'), icon: LucideIcons.clipboardList, iconColor: const Color(0xFF7C3AED)),
          _popupMenu('Configuración', [
            _popItem(LucideIcons.userCircle2, 'Seleccionar vendedor', _showSellerSelect),
            _popItem(LucideIcons.monitor, 'Abrir/cerrar caja', _showCashRegisterDialog),
            _popDivider(),
            _popItem(LucideIcons.layoutDashboard, 'Ir al sistema', () => context.go('/dashboard')),
          ], icon: LucideIcons.settings, iconColor: const Color(0xFF64748B)),
          _navTab('Corte', false, _showTodaySalesDialog, icon: LucideIcons.scissors, iconColor: const Color(0xFFDC2626)),

          const Spacer(),

          // Held sales indicator
          if (heldSales.isNotEmpty)
            _headerChip(
              LucideIcons.pauseCircle,
              '${heldSales.length} pendiente${heldSales.length > 1 ? 's' : ''}',
              const Color(0xFFD97706),
              () => _showRecoverSaleDialog(heldSales),
            ),

          // "Le atiende:"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFD1D5DB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Le atiende:  ',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                const Icon(Icons.person, size: 15, color: Color(0xFF059669)),
                const SizedBox(width: 4),
                Text(user?.fullName ?? user?.username ?? 'Admin',
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF0F172A), fontWeight: FontWeight.w700)),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Salir button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _confirmLogout,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.logOut, size: 14, color: Color(0xFFDC2626)),
                    SizedBox(width: 4),
                    Text('Salir',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navTab(String label, bool active, VoidCallback onTap, {IconData? icon, Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFEFF6FF) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: active ? Border.all(color: const Color(0xFFBFDBFE)) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: active ? iconColor ?? const Color(0xFF2563EB) : (iconColor ?? const Color(0xFF64748B)).withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? const Color(0xFF1E40AF) : const Color(0xFF475569),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _popupMenu(String label, List<PopupMenuEntry<VoidCallback>> items, {IconData? icon, Color? iconColor}) {
    return PopupMenuButton<VoidCallback>(
      onSelected: (fn) => fn(),
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (_) => items,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: iconColor ?? const Color(0xFF64748B)),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF475569), fontSize: 12.5, fontWeight: FontWeight.w500)),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<VoidCallback> _popItem(
      IconData icon, String label, VoidCallback action) {
    return PopupMenuItem<VoidCallback>(
      value: action,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondaryLight),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  PopupMenuDivider _popDivider() => const PopupMenuDivider(height: 8);

  Widget _headerInfo(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _headerChip(IconData icon, String text, Color color, VoidCallback onTap) {
    return Tooltip(
      message: 'Ver ventas en espera',
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 2) TITLE BAR — Green gradient "VENTA DE PRODUCTOS - Ticket 1"
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTitleBar(DocumentType docType) {
    final docLabel = switch (docType) {
      DocumentType.ticket => 'Ticket',
      DocumentType.invoice => 'Factura',
      DocumentType.saleNote => 'Nota de Venta',
      DocumentType.remission => 'Remisión',
    };
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF059669), Color(0xFF10B981)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(LucideIcons.shoppingBag, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text('VENTA DE PRODUCTOS  —  $docLabel',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              )),
          const Spacer(),
          // Doc type selector
          _titleDocChip(DocumentType.ticket, 'Ticket', docType),
          _titleDocChip(DocumentType.invoice, 'Factura', docType),
          _titleDocChip(DocumentType.saleNote, 'Nota', docType),
        ],
      ),
    );
  }

  Widget _titleDocChip(DocumentType type, String label, DocumentType current) {
    final isActive = type == current;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: GestureDetector(
        onTap: () => ref.read(documentTypeProvider.notifier).state = type,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withValues(alpha: 0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withValues(alpha: isActive ? 0.5 : 0.2)),
          ),
          child: Text(label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: isActive ? 1 : 0.7),
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              )),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 3) BARCODE INPUT — "Código del Producto:" + field + "ENTER"
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBarcodeInput() {
    return Container(
      height: 50,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text('Código del Producto:',
              style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          const SizedBox(width: 12),
          // Barcode icon
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Icon(LucideIcons.scanLine, size: 17, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 8),
          // Input field
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFF0),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
              ),
              child: TextField(
                controller: _barcodeController,
                focusNode: _barcodeFocusNode,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                decoration: const InputDecoration(
                  hintText: 'Escanear o escribir código...',
                  hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w400),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  filled: true,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                ),
                onSubmitted: _onBarcodeSubmitted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // "ENTER - Agregar" button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _onBarcodeSubmitted(_barcodeController.text),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 17, color: Color(0xFF059669)),
                    SizedBox(width: 6),
                    Text('ENTER - Agregar Producto',
                        style: TextStyle(
                            fontSize: 12.5, color: Color(0xFF059669), fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 4) ACTION BUTTONS — F-Key shortcuts row
  // ═══════════════════════════════════════════════════════════════

  Widget _buildActionButtons(List<HeldSale> heldSales) {
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _actionBtn(LucideIcons.filePlus, 'INS Varios', _startNewSale,
              iconColor: const Color(0xFF2563EB)),
          _actionBtn(LucideIcons.fileText, 'CTRL+P Art. Común', () {},
              iconColor: const Color(0xFF7C3AED)),
          _actionBtn(LucideIcons.search, 'F10 Buscar', _showSearchDialog,
              iconColor: const Color(0xFFD97706)),
          _actionBtn(LucideIcons.tags, 'F11 Mayoreo', _showPriceDialog,
              iconColor: const Color(0xFFDC2626)),
          _actionBtn(LucideIcons.packagePlus, 'F7 Entradas', _showDiscountDialog,
              iconColor: const Color(0xFF059669)),
          _actionBtn(LucideIcons.packageMinus, 'F8 Salidas', _openCashDrawer,
              iconColor: const Color(0xFFE67E22)),
          _actionBtn(LucideIcons.trash2, 'DEL Borrar Art.', _removeSelectedItem,
              iconColor: const Color(0xFFDC2626)),
          const Spacer(),
          // Customer & seller pills
          _compactPill(LucideIcons.user, ref.watch(selectedCustomerProvider)?.name ?? 'Consumidor Final',
              _showCustomerLookup, pillColor: const Color(0xFF2563EB)),
          const SizedBox(width: 6),
          _compactPill(LucideIcons.briefcase, ref.watch(selectedSellerProvider)?.fullName ?? 'Vendedor',
              _showSellerSelect, pillColor: const Color(0xFF059669)),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, {Color? color, Color? iconColor}) {
    final textColor = color ?? const Color(0xFF334155);
    final ic = iconColor ?? textColor;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFD1D5DB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: ic),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 11.5, color: textColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactPill(IconData icon, String label, VoidCallback onTap, {Color? pillColor}) {
    final c = pillColor ?? const Color(0xFF64748B);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 5) SALES TABLE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSalesTable(List<CartItem> cart) {
    final selectedIndex = ref.watch(selectedCartIndexProvider);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Table header — Gray like eleventa
          Container(
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFF64748B),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: const Row(
              children: [
                _ColHeader('#', width: 32),
                _ColHeader('Código de Barras', width: 120),
                Expanded(child: _ColHeader('Descripción del Producto')),
                _ColHeader('Precio Venta', width: 95),
                _ColHeader('Cant.', width: 55),
                _ColHeader('Importe', width: 95),
                _ColHeader('Exist.', width: 60),
              ],
            ),
          ),

          // Rows or Empty state
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.shoppingCart, size: 48, color: const Color(0xFFCBD5E1)),
                        const SizedBox(height: 14),
                        const Text('Escanee un código de barras o presione F10 para buscar',
                            style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _hintChip('F10 Buscar'),
                            SizedBox(width: 6),
                            _hintChip('F12 Cobrar'),
                            SizedBox(width: 6),
                            _hintChip('+ / -'),
                            SizedBox(width: 6),
                            _hintChip('DEL'),
                          ],
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      final isSelected = selectedIndex == index;
                      final isEven = index.isEven;

                      return GestureDetector(
                        onTap: () => ref.read(selectedCartIndexProvider.notifier).state =
                            isSelected ? null : index,
                        onDoubleTap: () {
                          ref.read(selectedCartIndexProvider.notifier).state = index;
                          _showQuantityDialog();
                        },
                        onSecondaryTapDown: (details) {
                          ref.read(selectedCartIndexProvider.notifier).state = index;
                          _showRowContextMenu(details.globalPosition, item, index);
                        },
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFDBEAFE)
                                : isEven
                                    ? Colors.white
                                    : const Color(0xFFF8FAFC),
                            border: Border(
                              left: isSelected
                                  ? const BorderSide(color: Color(0xFF2563EB), width: 3)
                                  : BorderSide.none,
                              bottom: const BorderSide(color: Color(0xFFF1F5F9), width: 1),
                            ),
                          ),
                          child: Row(
                            children: [
                              _CellText('${index + 1}', width: 32, align: TextAlign.center),
                              _CellText(
                                item.product.barcode ?? item.product.internalCode ?? '-',
                                width: 120,
                              ),
                              Expanded(
                                child: Text(item.displayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              _CellText(item.effectivePrice.currency,
                                  width: 95, align: TextAlign.right),
                              _CellText(
                                item.quantity % 1 == 0
                                    ? item.quantity.toInt().toString()
                                    : item.quantity.toStringAsFixed(2),
                                width: 55,
                                align: TextAlign.center,
                                bold: true,
                              ),
                              _CellText(item.total.currency,
                                  width: 95, align: TextAlign.right, bold: true),
                              _CellText(
                                item.product.currentStock.toStringAsFixed(0),
                                width: 60,
                                align: TextAlign.center,
                                color: item.product.currentStock <= item.product.minStock
                                    ? AppColors.error
                                    : null,
                              ),
                            ],
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

  Widget _hintChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w600)),
    );
  }

  void _showRowContextMenu(Offset position, CartItem item, int index) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(value: 'qty', child: _ctxItem(LucideIcons.hash, 'Cambiar cantidad (F5)')),
        PopupMenuItem(value: 'price', child: _ctxItem(LucideIcons.dollarSign, 'Cambiar precio (F3)')),
        PopupMenuItem(value: 'discount', child: _ctxItem(LucideIcons.percent, 'Aplicar descuento (F7)')),
        PopupMenuItem(value: 'edit', child: _ctxItem(LucideIcons.pencil, 'Editar artículo (F4)')),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: 'remove',
            child: _ctxItem(LucideIcons.trash2, 'Eliminar (Del)', color: AppColors.error)),
      ],
    ).then((action) {
      if (action == null) return;
      ref.read(selectedCartIndexProvider.notifier).state = index;
      switch (action) {
        case 'qty':
          _showQuantityDialog();
        case 'price':
          _showPriceDialog();
        case 'discount':
          _showDiscountDialog();
        case 'edit':
          _showEditItemDialog();
        case 'remove':
          _removeSelectedItem();
      }
    });
  }

  Widget _ctxItem(IconData icon, String label, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textSecondaryLight),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 6) BOTTOM BAR — Product count + action buttons + Cobrar + TOTAL
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBottomBar({
    required double totalItems,
    required double subtotal,
    required double discountTotal,
    required double taxTotal,
    required double grandTotal,
  }) {
    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(top: BorderSide(color: Color(0xFFDDE1E7), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Product count
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                totalItems % 1 == 0 ? totalItems.toInt().toString() : totalItems.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF2563EB)),
              ),
              const Text('Productos en la venta actual.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w500)),
            ],
          ),

          const SizedBox(width: 20),

          // Action buttons: F5, F6, Eliminar
          _bottomActionBtn(LucideIcons.refreshCw, 'F5 - Cambiar', _showQuantityDialog,
              iconColor: const Color(0xFF2563EB)),
          const SizedBox(width: 6),
          _bottomActionBtn(LucideIcons.clock, 'F6 - Pendiente', _holdCurrentSale,
              iconColor: const Color(0xFFD97706)),
          const SizedBox(width: 6),
          _bottomActionBtn(LucideIcons.trash2, 'Eliminar', _removeSelectedItem,
              color: const Color(0xFFDC2626), iconColor: const Color(0xFFDC2626)),

          const Spacer(),

          // F12 COBRAR button — Big and prominent
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showPaymentDialog,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.banknote, size: 22, color: Color(0xFF059669)),
                    SizedBox(width: 10),
                    Text('F12 - Cobrar',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 24),

          // GRAND TOTAL — Big blue number like eleventa
          Text(
            grandTotal.currency,
            style: const TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1D4ED8),
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomActionBtn(IconData icon, String label, VoidCallback onTap, {Color? color, Color? iconColor}) {
    final c = color ?? const Color(0xFF334155);
    final ic = iconColor ?? const Color(0xFF475569);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFD1D5DB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: ic),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, color: c, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 7) FOOTER — Total/Pagó Con/Cambio + utilities + date/time
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFooter({required double grandTotal}) {
    final now = DateTime.now();

    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFFE8ECF1),
        border: Border(top: BorderSide(color: Color(0xFFDDE1E7), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Total / Pagó Con / Cambio
          _footerValue('Total:', grandTotal.currency, const Color(0xFF2563EB)),
          const SizedBox(width: 20),
          _footerValue('Pagó Con:', '\$0.00', const Color(0xFF334155)),
          const SizedBox(width: 20),
          _footerValue('Cambio:', '\$0.00', const Color(0xFF059669)),

          const SizedBox(width: 16),
          // Cash drawer button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openCashDrawer,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFDDE1E7)),
                ),
                child: const Icon(LucideIcons.inbox, size: 14, color: Color(0xFF64748B)),
              ),
            ),
          ),

          const Spacer(),

          // Utility buttons
          _footerBtn(LucideIcons.printer, 'Reimprimir Último Ticket', () {}),
          const SizedBox(width: 8),
          _footerBtn(LucideIcons.clipboardList, 'Ventas del día y Devoluciones', _showTodaySalesDialog),

          const SizedBox(width: 16),
          // Timestamp
          Text(
            '${DateFormat('dd - MMM', 'es').format(now)}    ${DateFormat('h:mm a').format(now)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _footerValue(String label, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
        const SizedBox(width: 6),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: valueColor)),
      ],
    );
  }

  Widget _footerBtn(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFF2563EB)),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onBarcodeSubmitted(String value) async {
    if (value.trim().isEmpty) return;
    final db = ref.read(appDatabaseProvider);
    final product = await db.productsDao.getProductByBarcode(value.trim());

    if (product != null) {
      ref.read(cartProvider.notifier).addItem(product);
      _barcodeController.clear();
      _barcodeFocusNode.requestFocus();
    } else {
      final results = await db.productsDao.searchProducts(value.trim());
      if (results.length == 1) {
        ref.read(cartProvider.notifier).addItem(results.first);
        _barcodeController.clear();
        _barcodeFocusNode.requestFocus();
      } else if (results.isNotEmpty) {
        _barcodeController.clear();
        if (!mounted) return;
        _showProductPickerDialog(results);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Producto no encontrado: $value'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
        _barcodeController.clear();
        _barcodeFocusNode.requestFocus();
      }
    }
  }

  // ── F2: Search ──
  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _SearchProductDialog(
        onSelect: (product) {
          ref.read(cartProvider.notifier).addItem(product);
          _barcodeFocusNode.requestFocus();
        },
      ),
    );
  }

  // ── F3: Price ──
  void _showPriceDialog() {
    final index = ref.read(selectedCartIndexProvider);
    final cart = ref.read(cartProvider);
    if (index == null || index >= cart.length) {
      _noItemSelectedSnack();
      return;
    }
    final item = cart[index];
    showDialog(
      context: context,
      builder: (ctx) => _PriceLevelDialog(
        item: item,
        onSelect: (level, customPrice) {
          ref.read(cartProvider.notifier).setPriceLevel(item.product.id, level,
              customPrice: customPrice);
        },
      ),
    );
  }

  // ── F4: Edit item ──
  void _showEditItemDialog() {
    final index = ref.read(selectedCartIndexProvider);
    final cart = ref.read(cartProvider);
    if (index == null || index >= cart.length) {
      _noItemSelectedSnack();
      return;
    }
    final item = cart[index];
    showDialog(
      context: context,
      builder: (ctx) => _EditItemDialog(
        item: item,
        onSave: (qty, discPct, priceLevel, customPrice, desc) {
          final notifier = ref.read(cartProvider.notifier);
          notifier.updateQuantity(item.product.id, qty);
          notifier.applyDiscountPercent(item.product.id, discPct);
          notifier.setPriceLevel(item.product.id, priceLevel, customPrice: customPrice);
          if (desc != null && desc.isNotEmpty) {
            notifier.setTempDescription(item.product.id, desc);
          }
        },
      ),
    );
  }

  // ── F5: Quantity ──
  void _showQuantityDialog() {
    final index = ref.read(selectedCartIndexProvider);
    final cart = ref.read(cartProvider);
    if (index == null || index >= cart.length) {
      _noItemSelectedSnack();
      return;
    }
    final item = cart[index];
    final controller = TextEditingController(
        text: item.quantity % 1 == 0
            ? item.quantity.toInt().toString()
            : item.quantity.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar Cantidad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Stock disponible: ${item.product.currentStock.toStringAsFixed(0)}',
                style: TextStyle(color: AppColors.textSecondaryLight, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                prefixIcon: Icon(LucideIcons.hash),
              ),
              onSubmitted: (val) {
                final qty = double.tryParse(val);
                if (qty != null && qty > 0) {
                  ref.read(cartProvider.notifier).updateQuantity(item.product.id, qty);
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final qty = double.tryParse(controller.text);
              if (qty != null && qty > 0) {
                ref.read(cartProvider.notifier).updateQuantity(item.product.id, qty);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  // ── F6: Remove ──
  void _removeSelectedItem() {
    final index = ref.read(selectedCartIndexProvider);
    final cart = ref.read(cartProvider);
    if (index == null || index >= cart.length) return;
    ref.read(cartProvider.notifier).removeItem(cart[index].product.id);
    ref.read(selectedCartIndexProvider.notifier).state = null;
    _barcodeFocusNode.requestFocus();
  }

  // ── F7: Discount ──
  void _showDiscountDialog() {
    final index = ref.read(selectedCartIndexProvider);
    final cart = ref.read(cartProvider);
    final isGlobal = index == null || index >= cart.length;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isGlobal ? 'Descuento Global (%)' : 'Descuento al Artículo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isGlobal) ...[
              Text(cart[index].displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Porcentaje de descuento',
                suffixText: '%',
                prefixIcon: Icon(LucideIcons.percent),
              ),
              onSubmitted: (val) {
                _applyDiscount(val, isGlobal, index, cart);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              _applyDiscount(controller.text, isGlobal, index, cart);
              Navigator.pop(ctx);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _applyDiscount(String val, bool isGlobal, int? index, List<CartItem> cart) {
    final pct = double.tryParse(val);
    if (pct == null || pct < 0 || pct > 100) return;
    if (isGlobal) {
      ref.read(cartProvider.notifier).applyGlobalDiscount(pct);
    } else {
      ref.read(cartProvider.notifier).applyDiscountPercent(cart[index!].product.id, pct);
    }
  }

  // ── F8: Cash drawer ──
  void _openCashDrawer() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Señal enviada al cajón de dinero'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ── F9: Hold sale ──
  void _holdCurrentSale() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final customer = ref.read(selectedCustomerProvider);
    final docType = ref.read(documentTypeProvider);

    final sale = HeldSale(
      id: const Uuid().v4(),
      label: 'Venta ${DateFormat('HH:mm').format(DateTime.now())}',
      items: List.from(cart),
      customer: customer,
      docType: docType,
      heldAt: DateTime.now(),
    );

    ref.read(heldSalesProvider.notifier).holdSale(sale);
    ref.read(cartProvider.notifier).clearCart();
    ref.read(selectedCustomerProvider.notifier).state = null;
    ref.read(selectedCartIndexProvider.notifier).state = null;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Venta guardada en espera'),
        backgroundColor: AppColors.info,
        duration: Duration(seconds: 2),
      ),
    );
    _barcodeFocusNode.requestFocus();
  }

  // ── F10: Import amount ──
  void _showImportDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ingreso de Importe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ingrese la cantidad exacta que el cliente entrega.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  labelText: 'Cantidad recibida',
                  prefixText: r'$ ',
                  prefixIcon: Icon(LucideIcons.calculator),
                ),
                onSubmitted: (_) {
                  final amount = double.tryParse(controller.text);
                  if (amount != null && amount > 0) {
                    Navigator.pop(ctx);
                    _showPaymentDialogWithAmount(amount);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(controller.text);
                if (amount != null && amount > 0) {
                  Navigator.pop(ctx);
                  _showPaymentDialogWithAmount(amount);
                }
              },
              child: const Text('Cobrar con este importe'),
            ),
          ],
        );
      },
    ).then((_) => controller.dispose());
  }

  void _showPaymentDialogWithAmount(double amount) {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    final grandTotal = cart.fold<double>(0, (s, i) => s + i.total);
    if (amount >= grandTotal) {
      _finalizeSale('cash', amount, grandTotal);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('El importe \$${amount.toStringAsFixed(2)} es menor al total ${grandTotal.currency}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ── F11: Payment ──
  void _showPaymentDialog() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    final grandTotal = cart.fold<double>(0, (s, i) => s + i.total);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PaymentDialog(
        total: grandTotal,
        onConfirm: (paymentMethod, cashReceived) {
          _finalizeSale(paymentMethod, cashReceived, grandTotal);
        },
      ),
    );
  }

  Future<void> _finalizeSale(
      String paymentMethod, double cashReceived, double total) async {
    final cart = ref.read(cartProvider);
    final customer = ref.read(selectedCustomerProvider);
    final docType = ref.read(documentTypeProvider);
    final seller = ref.read(selectedSellerProvider);
    final db = ref.read(appDatabaseProvider);

    final subtotal = cart.fold<double>(0, (s, i) => s + i.subtotal);
    final taxAmount = cart.fold<double>(0, (s, i) => s + i.taxAmount);
    final discountAmount = cart.fold<double>(0, (s, i) => s + i.discountAmount);

    final invoiceNumber = await db.salesDao.generateInvoiceNumber();
    final saleId = const Uuid().v4();

    final saleCompanion = SalesCompanion(
      id: Value(saleId),
      invoiceNumber: Value(invoiceNumber),
      customerName: Value(customer?.name ?? 'Consumidor Final'),
      customerRuc: Value(customer?.ruc ?? '9999999999999'),
      sellerId: Value(seller?.id ?? ''),
      subtotal: Value(subtotal),
      taxAmount: Value(taxAmount),
      discountAmount: Value(discountAmount),
      total: Value(total),
      paymentMethod: Value(paymentMethod),
      cashReceived: Value(cashReceived),
      changeGiven: Value(
          paymentMethod == 'cash' ? (cashReceived - total).clamp(0, double.infinity).toDouble() : 0),
      status: const Value('completed'),
      notes: Value(docType == DocumentType.invoice ? 'FACTURA' : 'TICKET'),
      createdAt: Value(DateTime.now()),
    );

    final itemCompanions = cart.map((item) {
      return SaleItemsCompanion(
        id: Value(const Uuid().v4()),
        saleId: Value(saleId),
        productId: Value(item.product.id),
        productName: Value(item.displayName),
        quantity: Value(item.quantity),
        unitPrice: Value(item.effectivePrice),
        costPrice: Value(item.product.costPrice),
        discount: Value(item.discountAmount),
        taxRate: Value(item.product.isTaxExempt ? 0 : item.product.taxRate),
        taxAmount: Value(item.taxAmount),
        subtotal: Value(item.subtotal),
        total: Value(item.total),
      );
    }).toList();

    try {
      await db.salesDao.createSale(sale: saleCompanion, items: itemCompanions);

      // Update cash register totals
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final register = await db.cashRegisterDao.getOpenRegister(user.id);
        if (register != null) {
          await db.cashRegisterDao.updateRegisterTotals(
            register.id,
            saleAmount: total,
            paymentMethod: paymentMethod,
          );
        }
      }

      final change = paymentMethod == 'cash'
          ? (cashReceived - total).clamp(0, double.infinity).toDouble()
          : 0.0;

      ref.read(cartProvider.notifier).clearCart();
      ref.read(selectedCustomerProvider.notifier).state = null;
      ref.read(selectedCartIndexProvider.notifier).state = null;

      if (!mounted) return;

      if (change > 0) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Venta Completada'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.checkCircle2, color: AppColors.success, size: 48),
                const SizedBox(height: 12),
                Text('Folio: $invoiceNumber',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Total: ${total.currency}'),
                Text('Recibido: ${cashReceived.currency}'),
                const Divider(),
                Text(
                  'Cambio: ${change.currency}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                autofocus: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _barcodeFocusNode.requestFocus();
                },
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Venta $invoiceNumber completada • ${total.currency}'),
            backgroundColor: AppColors.success,
          ),
        );
        _barcodeFocusNode.requestFocus();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al procesar venta: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  // ── Customer lookup ──
  void _showCustomerLookup() {
    showDialog(
      context: context,
      builder: (ctx) => _CustomerLookupDialog(
        onSelect: (customer) {
          ref.read(selectedCustomerProvider.notifier).state = customer;
        },
      ),
    );
  }

  // ── Seller select ──
  void _showSellerSelect() {
    showDialog(
      context: context,
      builder: (ctx) => _SellerSelectDialog(
        onSelect: (user) {
          ref.read(selectedSellerProvider.notifier).state = user;
        },
      ),
    );
  }

  // ── Quick item ──
  void _showQuickItemDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _QuickItemDialog(
        onAdd: (description, price, qty) {
          // Create a temporary product for quick sale
          final tempProduct = Product(
            id: 'quick_${const Uuid().v4()}',
            barcode: null,
            internalCode: 'RAPIDO',
            name: description,
            genericName: null,
            description: null,
            categoryId: null,
            presentation: null,
            concentration: null,
            laboratory: null,
            costPrice: 0,
            salePrice: price,
            wholesalePrice: null,
            taxRate: 15.0,
            isTaxExempt: false,
            currentStock: 9999,
            minStock: 0,
            maxStock: null,
            unit: 'unidad',
            requiresPrescription: false,
            isControlled: false,
            adminRoute: null,
            saleType: 'Unidad/Pieza',
            storageCondition: null,
            storageNotes: null,
            registroSanitario: null,
            usesInventory: false,
            isActive: true,
            imagePath: null,
            createdAt: DateTime.now(),
            updatedAt: null,
            syncStatus: 'local',
            syncVersion: 0,
          );
          ref.read(cartProvider.notifier).addItem(tempProduct, quantity: qty);
          _barcodeFocusNode.requestFocus();
        },
      ),
    );
  }

  // ── Recover sale ──
  void _showRecoverSaleDialog(List<HeldSale> heldSales) {
    if (heldSales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay ventas en espera')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(LucideIcons.pauseCircle, size: 20),
            const SizedBox(width: 8),
            const Text('Ventas en Espera'),
            const Spacer(),
            Text('${heldSales.length}', style: TextStyle(color: AppColors.textSecondaryLight)),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: heldSales.length,
            itemBuilder: (context, index) {
              final sale = heldSales[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text('${sale.items.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                title: Text(sale.label),
                subtitle: Text(
                    '${sale.items.length} artículos • ${sale.total.currency}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(DateFormat('HH:mm').format(sale.heldAt),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(sale.customer?.name ?? 'Consumidor Final',
                        style: TextStyle(fontSize: 10, color: AppColors.textSecondaryLight)),
                  ],
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  final currentCart = ref.read(cartProvider);
                  if (currentCart.isNotEmpty) {
                    _holdCurrentSale();
                  }
                  final recovered = ref.read(heldSalesProvider.notifier).recoverSale(sale.id);
                  if (recovered != null) {
                    ref.read(cartProvider.notifier).clearCart();
                    for (final item in recovered.items) {
                      ref.read(cartProvider.notifier).addItem(item.product, quantity: item.quantity);
                    }
                    if (recovered.customer != null) {
                      ref.read(selectedCustomerProvider.notifier).state = recovered.customer;
                    }
                    ref.read(documentTypeProvider.notifier).state = recovered.docType;
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  // ── Product picker ──
  void _showProductPickerDialog(List<Product> products) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${products.length} resultados encontrados'),
        content: SizedBox(
          width: 550,
          height: 400,
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final p = products[index];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(LucideIcons.pill, size: 18, color: AppColors.primary),
                ),
                title: Text(p.name, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                    '${p.barcode ?? p.internalCode ?? '-'} • Stock: ${p.currentStock.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11)),
                trailing: Text(p.salePrice.currency,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(cartProvider.notifier).addItem(p);
                  _barcodeFocusNode.requestFocus();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ],
      ),
    );
  }

  // ── New sale ──
  void _startNewSale() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva Venta'),
        content: const Text('¿Desea descartar la venta actual y comenzar una nueva?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(cartProvider.notifier).clearCart();
              ref.read(selectedCustomerProvider.notifier).state = null;
              ref.read(selectedSellerProvider.notifier).state = null;
              ref.read(selectedCartIndexProvider.notifier).state = null;
              _barcodeFocusNode.requestFocus();
            },
            child: const Text('Descartar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _holdCurrentSale();
            },
            child: const Text('Guardar en espera'),
          ),
        ],
      ),
    );
  }

  // ── Cash register ──
  void _showCashRegisterDialog() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    showDialog(
      context: context,
      builder: (ctx) => _CashRegisterDialog(userId: user.id),
    );
  }

  // ── Quotation ──
  void _showQuotationDialog() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregue productos para crear una cotización')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear Cotización'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Se creará una cotización con ${cart.length} artículo(s).'),
            const SizedBox(height: 8),
            Text('Total: ${cart.fold<double>(0, (s, i) => s + i.total).currency}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Válida por 15 días.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _createQuotation();
            },
            child: const Text('Crear Cotización'),
          ),
        ],
      ),
    );
  }

  Future<void> _createQuotation() async {
    final cart = ref.read(cartProvider);
    final customer = ref.read(selectedCustomerProvider);
    final seller = ref.read(selectedSellerProvider);
    final db = ref.read(appDatabaseProvider);

    final subtotal = cart.fold<double>(0, (s, i) => s + i.subtotal);
    final taxAmount = cart.fold<double>(0, (s, i) => s + i.taxAmount);
    final discountAmount = cart.fold<double>(0, (s, i) => s + i.discountAmount);
    final total = cart.fold<double>(0, (s, i) => s + i.total);

    try {
      final quoteNumber = await db.quotationsDao.generateQuoteNumber();
      final quoteId = const Uuid().v4();

      final quoteCompanion = QuotationsCompanion(
        id: Value(quoteId),
        quoteNumber: Value(quoteNumber),
        customerId: Value(customer?.id),
        customerName: Value(customer?.name ?? 'Consumidor Final'),
        sellerId: Value(seller?.id ?? ''),
        subtotal: Value(subtotal),
        taxAmount: Value(taxAmount),
        discountAmount: Value(discountAmount),
        total: Value(total),
        status: const Value('active'),
        validUntil: Value(DateTime.now().add(const Duration(days: 15))),
        createdAt: Value(DateTime.now()),
      );

      final itemCompanions = cart.map((item) {
        return QuotationItemsCompanion(
          id: Value(const Uuid().v4()),
          quotationId: Value(quoteId),
          productId: Value(item.product.id),
          productName: Value(item.displayName),
          quantity: Value(item.quantity),
          unitPrice: Value(item.effectivePrice),
          discount: Value(item.discountAmount),
          taxRate: Value(item.product.isTaxExempt ? 0 : item.product.taxRate),
          total: Value(item.total),
        );
      }).toList();

      await db.quotationsDao.createQuotation(quote: quoteCompanion, items: itemCompanions);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cotización $quoteNumber creada exitosamente'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear cotización: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  // ── Credit note ──
  void _showCreditNoteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _CreditNoteDialog(
        onCreated: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nota de crédito creada exitosamente'),
              backgroundColor: AppColors.success,
            ),
          );
        },
      ),
    );
  }

  // ── Today's sales ──
  void _showTodaySalesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const _TodaySalesDialog(),
    );
  }

  // ── Logout ──
  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Está seguro que desea cerrar sesión?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(cartProvider.notifier).clearCart();
              ref.read(currentUserProvider.notifier).state = null;
            },
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }

  void _noItemSelectedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seleccione un artículo de la tabla primero'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════

class _ColHeader extends StatelessWidget {
  final String label;
  final double? width;
  final String? tooltip;

  const _ColHeader(this.label, {this.width, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final widget = SizedBox(
      width: width,
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3),
          textAlign: TextAlign.center),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: widget);
    return widget;
  }
}

class _CellText extends StatelessWidget {
  final String text;
  final double? width;
  final TextAlign? align;
  final bool bold;
  final Color? color;

  const _CellText(this.text, {this.width, this.align, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: color ?? const Color(0xFF1E293B),
          ),
          textAlign: align,
          overflow: TextOverflow.ellipsis),
    );
  }
}

class _IndicatorCell extends StatelessWidget {
  final bool active;
  final String label;
  final Color color;

  const _IndicatorCell({required this.active, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: active ? color : Colors.grey[300]!, width: 1),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 8, fontWeight: FontWeight.w700, color: active ? color : Colors.grey[400])),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SEARCH PRODUCT DIALOG (F2)
// ═══════════════════════════════════════════════════════════════════

class _SearchProductDialog extends ConsumerStatefulWidget {
  final void Function(Product) onSelect;

  const _SearchProductDialog({required this.onSelect});

  @override
  ConsumerState<_SearchProductDialog> createState() => _SearchProductDialogState();
}

class _SearchProductDialogState extends ConsumerState<_SearchProductDialog> {
  final _controller = TextEditingController();
  List<Product> _results = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    if (query.length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final db = ref.read(appDatabaseProvider);
    final results = await db.productsDao.searchProducts(query);
    if (mounted) {
      setState(() {
        _results = results;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 650,
        height: 500,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.search, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('Buscar Producto',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  const Text('F2', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Nombre, código de barras, código interno...',
                  prefixIcon: Icon(LucideIcons.search),
                ),
                onChanged: _search,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _controller.text.length < 2
                                ? 'Escriba al menos 2 caracteres'
                                : 'Sin resultados',
                            style: TextStyle(color: AppColors.textSecondaryLight),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final p = _results[index];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: const Icon(LucideIcons.pill,
                                    size: 16, color: AppColors.primary),
                              ),
                              title: Text(p.name,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w500)),
                              subtitle: Text(
                                '${p.barcode ?? '-'} | ${p.internalCode ?? '-'} | Stock: ${p.currentStock.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(p.salePrice.currency,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 13)),
                                  if (p.wholesalePrice != null)
                                    Text('May: ${p.wholesalePrice!.currency}',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textSecondaryLight)),
                                ],
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onSelect(p);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// PRICE LEVEL DIALOG (F3)
// ═══════════════════════════════════════════════════════════════════

class _PriceLevelDialog extends StatelessWidget {
  final CartItem item;
  final void Function(PriceLevel, double?) onSelect;

  const _PriceLevelDialog({required this.item, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final customController = TextEditingController();

    return AlertDialog(
      title: const Text('Seleccionar Precio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Precio Regular'),
            trailing: Text(item.product.salePrice.currency,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            selected: item.priceLevel == PriceLevel.regular,
            onTap: () {
              Navigator.pop(context);
              onSelect(PriceLevel.regular, null);
            },
          ),
          if (item.product.wholesalePrice != null)
            ListTile(
              title: const Text('Precio Mayoreo'),
              trailing: Text(item.product.wholesalePrice!.currency,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              selected: item.priceLevel == PriceLevel.wholesale,
              onTap: () {
                Navigator.pop(context);
                onSelect(PriceLevel.wholesale, null);
              },
            ),
          const Divider(),
          TextField(
            controller: customController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Precio personalizado',
              prefixText: r'$ ',
            ),
            onSubmitted: (val) {
              final price = double.tryParse(val);
              if (price != null && price > 0) {
                Navigator.pop(context);
                onSelect(PriceLevel.custom, price);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            final price = double.tryParse(customController.text);
            if (price != null && price > 0) {
              Navigator.pop(context);
              onSelect(PriceLevel.custom, price);
            }
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// PAYMENT DIALOG (F11)
// ═══════════════════════════════════════════════════════════════════

class _PaymentDialog extends StatefulWidget {
  final double total;
  final void Function(String method, double cashReceived) onConfirm;

  const _PaymentDialog({required this.total, required this.onConfirm});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String _method = 'cash';
  final _cashController = TextEditingController();

  double get _cashReceived => double.tryParse(_cashController.text) ?? 0;
  double get _change =>
      (_cashReceived - widget.total).clamp(0, double.infinity).toDouble();

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.creditCard, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('Cobrar Venta',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  const Text('F11', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(widget.total.currency,
                      style: const TextStyle(
                          fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.primary)),
                  const SizedBox(height: 4),
                  const Text('Total a cobrar',
                      style: TextStyle(color: AppColors.textSecondaryLight)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _payMethodChip('cash', 'Efectivo', LucideIcons.banknote),
                      const SizedBox(width: 8),
                      _payMethodChip('card', 'Tarjeta', LucideIcons.creditCard),
                      const SizedBox(width: 8),
                      _payMethodChip('transfer', 'Transferencia', LucideIcons.arrowLeftRight),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_method == 'cash') ...[
                    TextField(
                      controller: _cashController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                        labelText: 'Efectivo recibido',
                        prefixText: r'$ ',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _confirm(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _quickAmounts().map((amount) {
                        return ActionChip(
                          label: Text(amount.currency),
                          onPressed: () {
                            _cashController.text = amount.toStringAsFixed(2);
                            setState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _change > 0
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _change > 0 ? AppColors.success : AppColors.borderLight),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Cambio:',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          Text(_change.currency,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: _change > 0
                                    ? AppColors.success
                                    : AppColors.textPrimaryLight,
                              )),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderLight)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _canConfirm ? _confirm : null,
                      icon: const Icon(LucideIcons.check),
                      label: const Text('Confirmar Venta'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canConfirm {
    if (_method == 'cash') return _cashReceived >= widget.total;
    return true;
  }

  void _confirm() {
    if (!_canConfirm) return;
    Navigator.pop(context);
    widget.onConfirm(_method, _method == 'cash' ? _cashReceived : widget.total);
  }

  List<double> _quickAmounts() {
    final total = widget.total;
    final amounts = <double>[total];
    for (final r in [5, 10, 20, 50, 100]) {
      final rounded = (total / r).ceil() * r.toDouble();
      if (rounded > total && !amounts.contains(rounded)) {
        amounts.add(rounded);
      }
    }
    return amounts.take(6).toList();
  }

  Widget _payMethodChip(String method, String label, IconData icon) {
    final isActive = _method == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _method = method),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.borderLight,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isActive ? AppColors.primary : AppColors.textSecondaryLight, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    color: isActive ? AppColors.primary : AppColors.textSecondaryLight,
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CUSTOMER LOOKUP DIALOG
// ═══════════════════════════════════════════════════════════════════

class _CustomerLookupDialog extends ConsumerStatefulWidget {
  final void Function(Customer) onSelect;

  const _CustomerLookupDialog({required this.onSelect});

  @override
  ConsumerState<_CustomerLookupDialog> createState() => _CustomerLookupDialogState();
}

class _CustomerLookupDialogState extends ConsumerState<_CustomerLookupDialog> {
  final _controller = TextEditingController();
  List<Customer> _results = [];

  Future<void> _search(String query) async {
    if (query.length < 2) {
      setState(() => _results = []);
      return;
    }
    final db = ref.read(appDatabaseProvider);
    final results = await db.customersDao.searchCustomers(query);
    if (mounted) setState(() => _results = results);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 500,
        height: 450,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.userCircle2, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('Buscar Cliente',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Nombre, RUC, cédula...',
                  prefixIcon: Icon(LucideIcons.search),
                ),
                onChanged: _search,
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text('Busque por nombre, RUC o cédula',
                          style: TextStyle(color: AppColors.textSecondaryLight)),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final c = _results[index];
                        return ListTile(
                          dense: true,
                          leading: const CircleAvatar(child: Icon(LucideIcons.user, size: 16)),
                          title: Text(c.name, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(c.ruc ?? c.cedula ?? '-',
                              style: const TextStyle(fontSize: 11)),
                          trailing: c.phone != null
                              ? Text(c.phone!, style: TextStyle(fontSize: 11, color: AppColors.textSecondaryLight))
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelect(c);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SELLER SELECT DIALOG
// ═══════════════════════════════════════════════════════════════════

class _SellerSelectDialog extends ConsumerStatefulWidget {
  final void Function(User) onSelect;

  const _SellerSelectDialog({required this.onSelect});

  @override
  ConsumerState<_SellerSelectDialog> createState() => _SellerSelectDialogState();
}

class _SellerSelectDialogState extends ConsumerState<_SellerSelectDialog> {
  List<User> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final db = ref.read(appDatabaseProvider);
    final users = await db.usersDao.getAllUsers();
    if (mounted) {
      setState(() {
        _users = users;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.briefcase, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('Seleccionar Vendedor',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? const Center(child: Text('No hay usuarios registrados'))
                      : ListView.builder(
                          itemCount: _users.length,
                          itemBuilder: (context, index) {
                            final u = _users[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
                                child: Text(
                                  u.fullName.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(u.fullName),
                              subtitle: Text(u.role,
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.textSecondaryLight)),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onSelect(u);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// QUICK ITEM DIALOG
// ═══════════════════════════════════════════════════════════════════

class _QuickItemDialog extends StatefulWidget {
  final void Function(String description, double price, double qty) onAdd;

  const _QuickItemDialog({required this.onAdd});

  @override
  State<_QuickItemDialog> createState() => _QuickItemDialogState();
}

class _QuickItemDialogState extends State<_QuickItemDialog> {
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');

  @override
  void dispose() {
    _descController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.zap, color: AppColors.warning, size: 20),
          const SizedBox(width: 8),
          const Text('Artículo Rápido'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Venta rápida sin código de barras',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Descripción del artículo',
              prefixIcon: Icon(LucideIcons.tag),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio',
                    prefixText: r'$ ',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            final desc = _descController.text.trim();
            final price = double.tryParse(_priceController.text);
            final qty = double.tryParse(_qtyController.text) ?? 1;
            if (desc.isEmpty || price == null || price <= 0) return;
            Navigator.pop(context);
            widget.onAdd(desc, price, qty);
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// EDIT ITEM DIALOG (F4)
// ═══════════════════════════════════════════════════════════════════

class _EditItemDialog extends StatefulWidget {
  final CartItem item;
  final void Function(double qty, double discPct, PriceLevel level, double? customPrice, String? desc)
      onSave;

  const _EditItemDialog({required this.item, required this.onSave});

  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  late final TextEditingController _qtyController;
  late final TextEditingController _discController;
  late final TextEditingController _priceController;
  late final TextEditingController _descController;
  late PriceLevel _priceLevel;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _qtyController = TextEditingController(
        text: item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toString());
    _discController = TextEditingController(
        text: item.discountPercent > 0 ? item.discountPercent.toString() : '');
    _priceController = TextEditingController(
        text: item.customPrice?.toString() ?? '');
    _descController = TextEditingController(text: item.tempDescription ?? '');
    _priceLevel = item.priceLevel;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _discController.dispose();
    _priceController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.pencil, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item.product.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const Text('F4', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Info row
                  Row(
                    children: [
                      Text('Código: ${item.product.barcode ?? item.product.internalCode ?? '-'}',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight)),
                      const Spacer(),
                      Text('Stock: ${item.product.currentStock.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Quantity
                  TextField(
                    controller: _qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      prefixIcon: Icon(LucideIcons.hash),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Discount
                  TextField(
                    controller: _discController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Descuento (%)',
                      prefixIcon: Icon(LucideIcons.percent),
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Price level
                  Row(
                    children: [
                      const Text('Precio:', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: Text('Regular ${item.product.salePrice.currency}'),
                        selected: _priceLevel == PriceLevel.regular,
                        onSelected: (_) => setState(() => _priceLevel = PriceLevel.regular),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                      if (item.product.wholesalePrice != null)
                        ChoiceChip(
                          label: Text('Mayoreo ${item.product.wholesalePrice!.currency}'),
                          selected: _priceLevel == PriceLevel.wholesale,
                          onSelected: (_) => setState(() => _priceLevel = PriceLevel.wholesale),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Custom price
                  if (_priceLevel == PriceLevel.custom || _priceController.text.isNotEmpty)
                    TextField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Precio personalizado',
                        prefixText: r'$ ',
                      ),
                      onChanged: (_) => setState(() => _priceLevel = PriceLevel.custom),
                    ),

                  const SizedBox(height: 12),

                  // Description override
                  TextField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción (dejar vacío para el nombre original)',
                      prefixIcon: Icon(LucideIcons.tag),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderLight)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final qty = double.tryParse(_qtyController.text) ?? widget.item.quantity;
                      final discPct = double.tryParse(_discController.text) ?? 0;
                      final customPrice = double.tryParse(_priceController.text);
                      final desc = _descController.text.trim();
                      Navigator.pop(context);
                      widget.onSave(qty, discPct, _priceLevel, customPrice,
                          desc.isEmpty ? null : desc);
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CASH REGISTER DIALOG
// ═══════════════════════════════════════════════════════════════════

class _CashRegisterDialog extends ConsumerStatefulWidget {
  final String userId;

  const _CashRegisterDialog({required this.userId});

  @override
  ConsumerState<_CashRegisterDialog> createState() => _CashRegisterDialogState();
}

class _CashRegisterDialogState extends ConsumerState<_CashRegisterDialog> {
  CashRegister? _openRegister;
  bool _loading = true;
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRegister();
  }

  Future<void> _loadRegister() async {
    final db = ref.read(appDatabaseProvider);
    final register = await db.cashRegisterDao.getOpenRegister(widget.userId);
    if (mounted) {
      setState(() {
        _openRegister = register;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 450,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            : _openRegister != null
                ? _buildCloseRegister()
                : _buildOpenRegister(),
      ),
    );
  }

  Widget _buildOpenRegister() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.monitor, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text('Abrir Caja',
                  style:
                      TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(LucideIcons.unlock, size: 48, color: AppColors.primary),
              const SizedBox(height: 12),
              const Text('Ingrese el monto inicial de la caja',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  labelText: 'Monto inicial',
                  prefixText: r'$ ',
                  prefixIcon: Icon(LucideIcons.banknote),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(LucideIcons.unlock),
                  label: const Text('Abrir Caja'),
                  onPressed: () async {
                    final amount = double.tryParse(_amountController.text) ?? 0;
                    final db = ref.read(appDatabaseProvider);
                    final id = const Uuid().v4();
                    await db.cashRegisterDao.openRegister(CashRegistersCompanion(
                      id: Value(id),
                      userId: Value(widget.userId),
                      openingAmount: Value(amount),
                      status: const Value('open'),
                      openedAt: Value(DateTime.now()),
                    ));
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Caja abierta con ${amount.currency}'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCloseRegister() {
    final reg = _openRegister!;
    final expected = reg.openingAmount + reg.totalSales;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF2D3748),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.monitor, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text('Cerrar Caja',
                  style:
                      TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Register summary
              _regRow('Apertura:', reg.openingAmount.currency),
              _regRow('Ventas:', reg.totalSales.currency),
              _regRow('Efectivo:', reg.totalCash.currency),
              _regRow('Tarjeta:', reg.totalCard.currency),
              _regRow('Transferencia:', reg.totalTransfer.currency),
              _regRow('Nº Ventas:', '${reg.salesCount}'),
              const Divider(),
              _regRow('Esperado:', expected.currency, bold: true),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  labelText: 'Monto de cierre (en caja)',
                  prefixText: r'$ ',
                  prefixIcon: Icon(LucideIcons.banknote),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(LucideIcons.lock),
                  label: const Text('Cerrar Caja'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D3748)),
                  onPressed: () async {
                    final closingAmount = double.tryParse(_amountController.text) ?? 0;
                    final db = ref.read(appDatabaseProvider);
                    await db.cashRegisterDao.closeRegister(
                      registerId: reg.id,
                      closingAmount: closingAmount,
                      expectedAmount: expected,
                      totalSales: reg.totalSales,
                      totalCash: reg.totalCash,
                      totalCard: reg.totalCard,
                      totalTransfer: reg.totalTransfer,
                      salesCount: reg.salesCount,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    final diff = closingAmount - expected;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Caja cerrada. Diferencia: ${diff.currency}'),
                        backgroundColor:
                            diff.abs() < 1 ? AppColors.success : AppColors.warning,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _regRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : null)),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CREDIT NOTE DIALOG
// ═══════════════════════════════════════════════════════════════════

class _CreditNoteDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  const _CreditNoteDialog({required this.onCreated});

  @override
  ConsumerState<_CreditNoteDialog> createState() => _CreditNoteDialogState();
}

class _CreditNoteDialogState extends ConsumerState<_CreditNoteDialog> {
  final _invoiceController = TextEditingController();
  Sale? _foundSale;
  List<SaleItem>? _saleItems;
  String _reason = 'return';
  bool _searching = false;

  Future<void> _searchSale() async {
    final query = _invoiceController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    final db = ref.read(appDatabaseProvider);
    // Search by invoice number in today's sales
    final today = DateTime.now();
    final sales = await db.salesDao.getSalesByDateRange(
      today.copyWith(hour: 0, minute: 0, second: 0),
      today.copyWith(hour: 23, minute: 59, second: 59),
    );
    final match = sales.where((s) => s.invoiceNumber == query).firstOrNull;
    if (match != null) {
      final items = await db.salesDao.getItemsForSale(match.id);
      setState(() {
        _foundSale = match;
        _saleItems = items;
        _searching = false;
      });
    } else {
      setState(() {
        _foundSale = null;
        _saleItems = null;
        _searching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venta no encontrada')),
        );
      }
    }
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 550,
        height: 500,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.fileX, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('Nota de Crédito',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _invoiceController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Número de factura/folio...',
                        prefixIcon: Icon(LucideIcons.search),
                      ),
                      onSubmitted: (_) => _searchSale(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _searching ? null : _searchSale,
                    child: const Text('Buscar'),
                  ),
                ],
              ),
            ),
            if (_foundSale != null && _saleItems != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text('Venta: ${_foundSale!.invoiceNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Text('Total: ${_foundSale!.total.currency}'),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _reason,
                      items: const [
                        DropdownMenuItem(value: 'return', child: Text('Devolución')),
                        DropdownMenuItem(value: 'discount', child: Text('Descuento')),
                        DropdownMenuItem(value: 'error', child: Text('Error')),
                        DropdownMenuItem(value: 'damaged', child: Text('Dañado')),
                      ],
                      onChanged: (v) => setState(() => _reason = v ?? 'return'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _saleItems!.length,
                  itemBuilder: (context, index) {
                    final item = _saleItems![index];
                    return ListTile(
                      dense: true,
                      title: Text(item.productName, style: const TextStyle(fontSize: 13)),
                      subtitle: Text('Cant: ${item.quantity} × ${item.unitPrice.currency}'),
                      trailing: Text(item.total.currency,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                    icon: const Icon(LucideIcons.fileX),
                    label: const Text('Crear Nota de Crédito'),
                    onPressed: () async {
                      await _createCreditNote();
                    },
                  ),
                ),
              ),
            ] else
              Expanded(
                child: Center(
                  child: Text(
                    _searching ? 'Buscando...' : 'Ingrese el folio de la venta a devolver',
                    style: TextStyle(color: AppColors.textSecondaryLight),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCreditNote() async {
    if (_foundSale == null || _saleItems == null) return;
    final db = ref.read(appDatabaseProvider);
    final user = ref.read(currentUserProvider);
    final sale = _foundSale!;

    try {
      final noteNumber = await db.creditNotesDao.generateNoteNumber();
      final noteId = const Uuid().v4();

      final noteCompanion = CreditNotesCompanion(
        id: Value(noteId),
        noteNumber: Value(noteNumber),
        saleId: Value(sale.id),
        customerId: const Value(null),
        customerName: Value(sale.customerName),
        reason: Value(_reason),
        subtotal: Value(sale.subtotal),
        taxAmount: Value(sale.taxAmount),
        total: Value(sale.total),
        status: const Value('active'),
        createdBy: Value(user?.id ?? ''),
        createdAt: Value(DateTime.now()),
      );

      final itemCompanions = _saleItems!.map((item) {
        return CreditNoteItemsCompanion(
          id: Value(const Uuid().v4()),
          creditNoteId: Value(noteId),
          productId: Value(item.productId),
          productName: Value(item.productName),
          quantity: Value(item.quantity),
          unitPrice: Value(item.unitPrice),
          total: Value(item.total),
          returnToStock: const Value(true),
        );
      }).toList();

      await db.creditNotesDao.createCreditNote(note: noteCompanion, items: itemCompanions);

      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// TODAY'S SALES DIALOG
// ═══════════════════════════════════════════════════════════════════

class _TodaySalesDialog extends ConsumerStatefulWidget {
  const _TodaySalesDialog();

  @override
  ConsumerState<_TodaySalesDialog> createState() => _TodaySalesDialogState();
}

class _TodaySalesDialogState extends ConsumerState<_TodaySalesDialog> {
  List<Sale> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    final sales = await db.salesDao.getSalesByDateRange(
      now.copyWith(hour: 0, minute: 0, second: 0),
      now.copyWith(hour: 23, minute: 59, second: 59),
    );
    if (mounted) {
      setState(() {
        _sales = sales;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDay = _sales.fold<double>(0, (s, sale) => s + sale.total);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.clipboardList, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('Ventas del Día',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  if (!_loading)
                    Text('${_sales.length} ventas • ${totalDay.currency}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _sales.isEmpty
                      ? const Center(child: Text('No hay ventas hoy'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _sales.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final sale = _sales[index];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: sale.status == 'cancelled'
                                    ? AppColors.error.withValues(alpha: 0.1)
                                    : AppColors.primary.withValues(alpha: 0.1),
                                child: Icon(
                                  sale.status == 'cancelled'
                                      ? LucideIcons.x
                                      : LucideIcons.receipt,
                                  size: 14,
                                  color: sale.status == 'cancelled'
                                      ? AppColors.error
                                      : AppColors.primary,
                                ),
                              ),
                              title: Text(sale.invoiceNumber ?? '-',
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${sale.customerName ?? 'Consumidor Final'} • ${sale.paymentMethod}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(sale.total.currency,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 13)),
                                  Text(
                                    DateFormat('HH:mm').format(sale.createdAt),
                                    style: TextStyle(
                                        fontSize: 10, color: AppColors.textSecondaryLight),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
