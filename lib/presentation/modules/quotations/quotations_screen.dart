import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';

class QuotationsScreen extends ConsumerStatefulWidget {
  const QuotationsScreen({super.key});

  @override
  ConsumerState<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends ConsumerState<QuotationsScreen> {
  String _filter = 'all'; // all, active, converted, cancelled, expired

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
                const Text('Cotizaciones',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showNewQuotationDialog(context, db),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nueva Cotización'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Filter chips
            Wrap(
              spacing: 8,
              children: [
                _filterChip('Todas', 'all'),
                _filterChip('Activas', 'active'),
                _filterChip('Convertidas', 'converted'),
                _filterChip('Canceladas', 'cancelled'),
                _filterChip('Vencidas', 'expired'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: StreamBuilder<List<Quotation>>(
                  stream: db.quotationsDao.watchQuotations(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var quotations = snapshot.data!;

                    if (_filter != 'all') {
                      if (_filter == 'expired') {
                        quotations = quotations
                            .where((q) =>
                                q.status == 'active' &&
                                q.validUntil.isBefore(DateTime.now()))
                            .toList();
                      } else {
                        quotations = quotations
                            .where((q) => q.status == _filter)
                            .toList();
                      }
                    }

                    if (quotations.isEmpty) {
                      return const Center(
                          child: Text('No hay cotizaciones'));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: quotations.length,
                      itemBuilder: (context, index) {
                        final q = quotations[index];
                        return _buildQuotationCard(context, db, q);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => setState(() => _filter = value),
    );
  }

  Widget _buildQuotationCard(
      BuildContext context, AppDatabase db, Quotation q) {
    final isExpired =
        q.status == 'active' && q.validUntil.isBefore(DateTime.now());
    final statusColor = switch (q.status) {
      'active' => isExpired ? AppColors.warning : AppColors.info,
      'converted' => AppColors.success,
      'cancelled' => AppColors.error,
      _ => AppColors.textSecondaryLight,
    };
    final statusLabel = switch (q.status) {
      'active' => isExpired ? 'Vencida' : 'Activa',
      'converted' => 'Convertida',
      'cancelled' => 'Cancelada',
      _ => q.status,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(Icons.description, color: statusColor),
        title: Row(
          children: [
            Text(q.quoteNumber,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        subtitle: Text(
            '${q.customerName ?? "Sin cliente"} | Total: ${q.total.currency} | Válida hasta: ${q.validUntil.formatted}'),
        children: [
          FutureBuilder<List<QuotationItem>>(
            future: db.quotationsDao.getQuotationItems(q.id),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final items = snap.data!;
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                  flex: 4,
                                  child: Text(item.productName)),
                              Expanded(
                                  child: Text('x${item.quantity.toInt()}',
                                      textAlign: TextAlign.center)),
                              Expanded(
                                  child: Text(item.unitPrice.currency,
                                      textAlign: TextAlign.right)),
                              Expanded(
                                  child: Text(item.total.currency,
                                      textAlign: TextAlign.right)),
                            ],
                          ),
                        )),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (q.status == 'active' && !isExpired) ...[
                          TextButton.icon(
                            onPressed: () async {
                              await db.quotationsDao
                                  .cancelQuotation(q.id);
                            },
                            icon: const Icon(Icons.cancel, size: 16),
                            label: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              // TODO: Convert to sale via POS
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Ir al POS para convertir esta cotización')),
                              );
                            },
                            icon: const Icon(Icons.shopping_cart, size: 16),
                            label: const Text('Convertir a Venta'),
                          ),
                        ],
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
  }

  void _showNewQuotationDialog(BuildContext context, AppDatabase db) {
    final customerNameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final validDays = ValueNotifier<int>(15);
    final items = <_QuoteItemEntry>[];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva Cotización'),
          content: SizedBox(
            width: 600,
            height: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: customerNameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nombre del Cliente'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Válida por: '),
                      ValueListenableBuilder<int>(
                        valueListenable: validDays,
                        builder: (_, days, __) => DropdownButton<int>(
                          value: days,
                          items: [7, 15, 30, 60]
                              .map((d) => DropdownMenuItem(
                                  value: d, child: Text('$d días')))
                              .toList(),
                          onChanged: (v) => validDays.value = v ?? 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notas'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Productos',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          _showAddItemDialog(context, db, (entry) {
                            setDialogState(() => items.add(entry));
                          });
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar'),
                      ),
                    ],
                  ),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No se han agregado productos'),
                    )
                  else
                    ...items.asMap().entries.map((e) {
                      final i = e.key;
                      final item = e.value;
                      return ListTile(
                        dense: true,
                        title: Text(item.productName),
                        subtitle: Text(
                            '${item.quantity} x ${item.unitPrice.currency}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                (item.quantity * item.unitPrice).currency),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 16),
                              onPressed: () =>
                                  setDialogState(() => items.removeAt(i)),
                            ),
                          ],
                        ),
                      );
                    }),
                  if (items.isNotEmpty) ...[
                    const Divider(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total: ${items.fold<double>(0, (sum, i) => sum + i.quantity * i.unitPrice).currency}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: items.isEmpty
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final quoteId =
                          'quote_${now.millisecondsSinceEpoch}';
                      final subtotal = items.fold<double>(
                          0, (sum, i) => sum + i.quantity * i.unitPrice);
                      final tax = subtotal * 0.15; // 15% IVA Ecuador
                      final total = subtotal + tax;

                      await db.quotationsDao.createQuotation(
                        quote: QuotationsCompanion.insert(
                          id: quoteId,
                          quoteNumber: 'COT-${now.millisecondsSinceEpoch.toString().substring(6)}',
                          sellerId: 'admin',
                          customerName: Value(
                              customerNameCtrl.text.trim().isEmpty
                                  ? null
                                  : customerNameCtrl.text.trim()),
                          subtotal: Value(subtotal),
                          taxAmount: Value(tax),
                          total: Value(total),
                          validUntil: now.add(
                              Duration(days: validDays.value)),
                          notes: Value(notesCtrl.text.trim().isEmpty
                              ? null
                              : notesCtrl.text.trim()),
                        ),
                        items: items
                            .map((i) =>
                                QuotationItemsCompanion.insert(
                                  id: 'qi_${DateTime.now().millisecondsSinceEpoch}_${items.indexOf(i)}',
                                  quotationId: quoteId,
                                  productId: i.productId,
                                  productName: i.productName,
                                  quantity: i.quantity.toDouble(),
                                  unitPrice: i.unitPrice,
                                  discount: Value(0.0),
                                  total: i.quantity * i.unitPrice,
                                ))
                            .toList(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: const Text('Crear Cotización'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddItemDialog(
      BuildContext context, AppDatabase db, Function(_QuoteItemEntry) onAdd) {
    final searchCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Agregar Producto'),
            content: SizedBox(
              width: 400,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Buscar producto...', prefixIcon: Icon(Icons.search)),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<List<Product>>(
                      future: searchCtrl.text.length < 2
                          ? Future.value([])
                          : db.productsDao.searchProducts(searchCtrl.text),
                      builder: (context, snap) {
                        final products = snap.data ?? [];
                        if (products.isEmpty && searchCtrl.text.length >= 2) {
                          return const Center(
                              child: Text('Sin resultados'));
                        }
                        return ListView.builder(
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final p = products[index];
                            return ListTile(
                              dense: true,
                              title: Text(p.name),
                              subtitle: Text(
                                  '${p.salePrice.currency} | Stock: ${p.currentStock.toInt()}'),
                              onTap: () {
                                final qty =
                                    int.tryParse(qtyCtrl.text) ?? 1;
                                onAdd(_QuoteItemEntry(
                                  productId: p.id,
                                  productName: p.name,
                                  unitPrice: p.salePrice,
                                  quantity: qty.toDouble(),
                                ));
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Cantidad'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuoteItemEntry {
  final String productId;
  final String productName;
  final double unitPrice;
  final double quantity;

  _QuoteItemEntry({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
  });
}
