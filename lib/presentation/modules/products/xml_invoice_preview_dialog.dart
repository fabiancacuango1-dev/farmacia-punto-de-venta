import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/import_export/xml_invoice_preview.dart';

// ══════════════════════════════════════════════════════════════
// ── XML INVOICE PREVIEW SCREEN ──
// ══════════════════════════════════════════════════════════════
/// Full-screen preview dialog showing all extracted invoice data
/// before confirming the import.
class XmlInvoicePreviewDialog extends StatefulWidget {
  final InvoicePreview preview;
  final Future<ImportConfirmResult> Function(InvoicePreview) onConfirmImport;

  const XmlInvoicePreviewDialog({
    super.key,
    required this.preview,
    required this.onConfirmImport,
  });

  /// Shows the dialog and returns the [ImportConfirmResult] if confirmed, null if cancelled.
  /// Accepts any service with a `confirmImport(InvoicePreview)` method.
  static Future<ImportConfirmResult?> show(
    BuildContext context, {
    required InvoicePreview preview,
    required dynamic service,
  }) {
    return showDialog<ImportConfirmResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => XmlInvoicePreviewDialog(
        preview: preview,
        onConfirmImport: (p) => service.confirmImport(p),
      ),
    );
  }

  @override
  State<XmlInvoicePreviewDialog> createState() => _XmlInvoicePreviewDialogState();
}

class _XmlInvoicePreviewDialogState extends State<XmlInvoicePreviewDialog> {
  bool _isImporting = false;
  String? _importError;

  InvoicePreview get p => widget.preview;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 900,
        height: 700,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Status Banner ──
                    _buildStatusBanner(),
                    const SizedBox(height: 16),

                    // ── Invoice & Supplier Info Row ──
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildInvoiceCard()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSupplierCard()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildClientCard()),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Impact Summary ──
                    _buildImpactSummary(),
                    const SizedBox(height: 16),

                    // ── Products Table ──
                    _buildProductsTable(),
                    const SizedBox(height: 16),

                    // ── Totals ──
                    _buildTotalsCard(),

                    // ── Warnings ──
                    if (p.warnings.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildWarnings(),
                    ],
                  ],
                ),
              ),
            ),

            // ── Import Error ──
            if (_importError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.error.withValues(alpha: 0.08),
                child: Text(_importError!,
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.error)),
              ),

            if (_isImporting) const LinearProgressIndicator(),

            // ── Actions ──
            _buildActions(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── HEADER ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    final format = p.header.detectedFormat ?? 'XML';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.fileSearch, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vista Previa de Factura',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                ),
                Row(
                  children: [
                    _formatBadge(format),
                    const SizedBox(width: 8),
                    Text(
                      '${p.items.length} productos encontrados',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryLight),
                    ),
                    if (p.header.fileName != null) ...[
                      const SizedBox(width: 8),
                      Text('• ${p.header.fileName}',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiaryLight)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: _isImporting ? null : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _formatBadge(String format) {
    final color = switch (format) {
      'SRI' => AppColors.secondary,
      'CFDI' => AppColors.amber,
      'UBL' => AppColors.accent,
      _ => AppColors.info,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(format,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── STATUS BANNER ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildStatusBanner() {
    final (icon, color, text, bg) = switch (p.status) {
      PreviewStatus.ready => (
          LucideIcons.checkCircle2,
          AppColors.success,
          'Factura lista para importar',
          AppColors.success.withValues(alpha: 0.06),
        ),
      PreviewStatus.readyWithWarnings => (
          LucideIcons.alertTriangle,
          AppColors.warning,
          'Factura lista con advertencias — revisa antes de importar',
          AppColors.warning.withValues(alpha: 0.06),
        ),
      PreviewStatus.duplicate => (
          LucideIcons.alertCircle,
          AppColors.error,
          'Factura ${p.header.invoiceNumber} posiblemente ya fue importada',
          AppColors.error.withValues(alpha: 0.06),
        ),
      PreviewStatus.error => (
          LucideIcons.xCircle,
          AppColors.error,
          'Error al procesar la factura',
          AppColors.error.withValues(alpha: 0.06),
        ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── INVOICE CARD ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildInvoiceCard() {
    return _infoCard(
      icon: LucideIcons.fileText,
      title: 'Factura',
      color: AppColors.primary,
      fields: [
        if (p.header.invoiceNumber != null)
          _field('Número', p.header.invoiceNumber!),
        if (p.header.issueDate != null)
          _field('Fecha', p.header.issueDate!),
        if (p.header.invoiceType != null)
          _field('Tipo', _invoiceTypeName(p.header.invoiceType!)),
        if (p.header.accessKey != null)
          _field('Clave', '${p.header.accessKey!.substring(0, 15)}...'),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── SUPPLIER CARD ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildSupplierCard() {
    final s = p.supplier;
    return _infoCard(
      icon: LucideIcons.building2,
      title: 'Proveedor',
      color: AppColors.secondary,
      badge: s.dbStatus == DbMatchStatus.exists
          ? _statusBadge('Existe', AppColors.success)
          : s.dbStatus == DbMatchStatus.willCreate
              ? _statusBadge('Nuevo', AppColors.amber)
              : null,
      fields: [
        if (s.name != null) _field('Nombre', s.name!),
        if (s.commercialName != null && s.commercialName != s.name)
          _field('Comercial', s.commercialName!),
        if (s.ruc != null) _field('RUC/RFC', s.ruc!),
        if (s.address != null) _field('Dirección', s.address!),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── CLIENT CARD ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildClientCard() {
    final c = p.client;
    return _infoCard(
      icon: LucideIcons.user,
      title: 'Cliente/Receptor',
      color: AppColors.accent,
      fields: [
        if (c.name != null) _field('Nombre', c.name!),
        if (c.identification != null) _field('Identificación', c.identification!),
        if (c.address != null) _field('Dirección', c.address!),
        if (c.name == null && c.identification == null)
          _field('', 'Sin datos del cliente'),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── IMPACT SUMMARY ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildImpactSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Simulación de importación',
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
          const SizedBox(height: 10),
          Row(
            children: [
              _impactItem(LucideIcons.packagePlus, '${p.newProducts}',
                  'Productos\nnuevos', AppColors.secondary),
              const SizedBox(width: 16),
              _impactItem(LucideIcons.refreshCw, '${p.existingProducts}',
                  'Productos\na actualizar', AppColors.primary),
              const SizedBox(width: 16),
              _impactItem(
                LucideIcons.building2,
                p.supplier.dbStatus == DbMatchStatus.willCreate ? '1' : '0',
                'Proveedor\nnuevo',
                AppColors.amber,
              ),
              const SizedBox(width: 16),
              _impactItem(LucideIcons.package, '${p.items.length}',
                  'Inventario\n(ítems)', AppColors.info),
              const SizedBox(width: 16),
              _impactItem(LucideIcons.receipt, '1',
                  'Orden de\ncompra', AppColors.accent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _impactItem(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(value,
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondaryLight, height: 1.2)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── PRODUCTS TABLE ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildProductsTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(LucideIcons.list, size: 16, color: AppColors.textSecondaryLight),
                const SizedBox(width: 8),
                Text('Detalle de Productos',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${p.items.length} ítems',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiaryLight)),
              ],
            ),
          ),
          const Divider(height: 1),

          // Column headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: [
                _colHeader('#', 30),
                _colHeader('Estado', 65),
                _colHeader('Código', 90),
                Expanded(child: Text('Descripción',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textTertiaryLight))),
                _colHeader('Cant.', 50),
                _colHeader('P. Unit.', 70),
                _colHeader('Desc.', 55),
                _colHeader('Impuesto', 65),
                _colHeader('Subtotal', 75),
              ],
            ),
          ),
          const Divider(height: 1),

          // Items
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: p.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _buildProductRow(p.items[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colHeader(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(text,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textTertiaryLight)),
    );
  }

  Widget _buildProductRow(InvoiceItemPreview item) {
    final isNew = item.dbStatus == DbMatchStatus.willCreate;
    final exists = item.dbStatus == DbMatchStatus.exists;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isNew ? AppColors.amberSurface.withValues(alpha: 0.3) : null,
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('${item.index + 1}',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiaryLight)),
          ),
          SizedBox(
            width: 65,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isNew
                    ? AppColors.amber.withValues(alpha: 0.1)
                    : exists
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.textTertiaryLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isNew ? 'Nuevo' : exists ? 'Existe' : '?',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isNew ? AppColors.amberDark : exists ? AppColors.success : AppColors.textTertiaryLight,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(item.code ?? item.auxCode ?? '-',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryLight),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description,
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (exists && item.existingProductName != null &&
                    item.existingProductName!.toLowerCase() != item.description.toLowerCase())
                  Text('→ ${item.existingProductName}',
                      style: GoogleFonts.inter(fontSize: 9, color: AppColors.info),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (exists)
                  Text('Stock actual: ${item.currentStock.toStringAsFixed(0)} → ${(item.currentStock + item.quantity).toStringAsFixed(0)}',
                      style: GoogleFonts.inter(fontSize: 9, color: AppColors.success)),
                // ── Pharmacy data badges ──
                if (_hasPharmaData(item))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        if (item.concentration != null)
                          _pharmaBadge(item.concentration!, AppColors.primary),
                        if (item.presentation != null)
                          _pharmaBadge(item.presentation!, AppColors.accent),
                        if (item.laboratory != null)
                          _pharmaBadge(item.laboratory!, AppColors.secondary),
                        if (item.adminRoute != null)
                          _pharmaBadge(item.adminRoute!, AppColors.info),
                        if (item.isTaxExempt == true)
                          _pharmaBadge('IVA 0%', AppColors.success),
                        if (item.isTaxExempt == false)
                          _pharmaBadge('IVA ${item.detectedTaxRate?.toStringAsFixed(0) ?? '15'}%', AppColors.warning),
                        if (item.isControlled == true)
                          _pharmaBadge('⚠ Controlado', AppColors.error),
                        if (item.requiresPrescription == true && item.isControlled != true)
                          _pharmaBadge('Rx', AppColors.amber),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(_fmtNum(item.quantity),
                style: GoogleFonts.inter(fontSize: 11), textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 70,
            child: Text('\$${_fmtMoney(item.unitPrice)}',
                style: GoogleFonts.inter(fontSize: 11), textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 55,
            child: Text(item.discount > 0 ? '\$${_fmtMoney(item.discount)}' : '-',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.error), textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 65,
            child: Text(item.taxAmount > 0 ? '\$${_fmtMoney(item.taxAmount)}' : '-',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryLight), textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 75,
            child: Text('\$${_fmtMoney(item.subtotal)}',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── TOTALS CARD ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildTotalsCard() {
    final t = p.totals;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          // Left: XML totals
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Totales de la Factura',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _totalRow('Subtotal', t.subtotal),
                if (t.discount > 0) _totalRow('Descuento', -t.discount, color: AppColors.error),
                _totalRow('Impuestos (IVA)', t.tax),
                const Divider(height: 12),
                _totalRow('TOTAL', t.total, bold: true, fontSize: 16),
              ],
            ),
          ),

          // Right: Validation
          if (t.totalsMatch != null) ...[
            const SizedBox(width: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.totalsMatch!
                    ? AppColors.success.withValues(alpha: 0.06)
                    : AppColors.warning.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (t.totalsMatch! ? AppColors.success : AppColors.warning).withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    t.totalsMatch! ? LucideIcons.checkCircle2 : LucideIcons.alertTriangle,
                    size: 24,
                    color: t.totalsMatch! ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.totalsMatch! ? 'Totales\ncoinciden' : 'Diferencia\ndetectada',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: t.totalsMatch! ? AppColors.success : AppColors.warning,
                    ),
                  ),
                  if (!t.totalsMatch!) ...[
                    const SizedBox(height: 4),
                    Text(
                      'XML: \$${_fmtMoney(t.xmlTotal ?? 0)}\nCalc: \$${_fmtMoney(t.calculatedTotal)}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 9, color: AppColors.textTertiaryLight),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false, Color? color, double fontSize = 13}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(
              fontSize: fontSize - 1, fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: color ?? AppColors.textSecondaryLight)),
          Text('\$${_fmtMoney(value)}', style: GoogleFonts.inter(
              fontSize: fontSize, fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color ?? (bold ? const Color(0xFF1E293B) : AppColors.textSecondaryLight))),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── WARNINGS ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildWarnings() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.alertTriangle, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Text('Advertencias',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.amberDark)),
            ],
          ),
          const SizedBox(height: 6),
          ...p.warnings.map((w) => Padding(
            padding: const EdgeInsets.only(left: 24, top: 2),
            child: Text('• $w',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.amberDark)),
          )),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── ACTIONS BAR ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          // Cancel
          OutlinedButton.icon(
            onPressed: _isImporting ? null : () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x, size: 16),
            label: const Text('Cancelar'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const Spacer(),

          // Info text
          if (!_isImporting)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                p.isDuplicate
                    ? 'Esta factura podría estar duplicada'
                    : '${p.items.length} productos serán procesados',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiaryLight),
              ),
            ),

          // Confirm
          ElevatedButton.icon(
            onPressed: _isImporting || p.status == PreviewStatus.error
                ? null
                : _confirmImport,
            icon: _isImporting
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(LucideIcons.check, size: 16),
            label: Text(_isImporting ? 'Importando...' : 'Confirmar e Importar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: p.isDuplicate ? AppColors.warning : AppColors.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── SHARED WIDGETS ──
  // ══════════════════════════════════════════════════════════════
  Widget _infoCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> fields,
    Widget? badge,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(title,
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              if (badge != null) ...[const Spacer(), badge],
            ],
          ),
          const SizedBox(height: 8),
          if (fields.isEmpty)
            Text('Sin datos disponibles',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiaryLight, fontStyle: FontStyle.italic))
          else
            ...fields,
        ],
      ),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            SizedBox(
              width: 70,
              child: Text('$label:',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiaryLight)),
            ),
          ],
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            text == 'Existe' ? LucideIcons.checkCircle2 : LucideIcons.plus,
            size: 10, color: color,
          ),
          const SizedBox(width: 3),
          Text(text,
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── PHARMA HELPERS ──
  // ══════════════════════════════════════════════════════════════
  bool _hasPharmaData(InvoiceItemPreview item) {
    return item.concentration != null ||
        item.presentation != null ||
        item.laboratory != null ||
        item.adminRoute != null ||
        item.isTaxExempt != null ||
        item.isControlled == true ||
        item.requiresPrescription == true;
  }

  Widget _pharmaBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w600, color: color)),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── ACTIONS ──
  // ══════════════════════════════════════════════════════════════
  Future<void> _confirmImport() async {
    setState(() { _isImporting = true; _importError = null; });

    try {
      final result = await widget.onConfirmImport(p);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      setState(() { _importError = 'Error: $e'; _isImporting = false; });
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── HELPERS ──
  // ══════════════════════════════════════════════════════════════
  String _fmtMoney(double v) => v.toStringAsFixed(2);
  String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _invoiceTypeName(String code) {
    return switch (code) {
      '01' => 'Factura',
      '04' => 'Nota de Crédito',
      '05' => 'Nota de Débito',
      '06' => 'Guía de Remisión',
      '07' => 'Comprobante de Retención',
      '03' => 'Liquidación de Compra',
      'I' => 'Ingreso',
      'E' => 'Egreso',
      'T' => 'Traslado',
      'P' => 'Pago',
      _ => code,
    };
  }
}
