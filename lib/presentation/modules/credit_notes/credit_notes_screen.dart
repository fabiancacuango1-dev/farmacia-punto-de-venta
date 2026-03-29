import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';

class CreditNotesScreen extends ConsumerStatefulWidget {
  const CreditNotesScreen({super.key});

  @override
  ConsumerState<CreditNotesScreen> createState() => _CreditNotesScreenState();
}

class _CreditNotesScreenState extends ConsumerState<CreditNotesScreen> {
  String _filter = 'all';

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
                const Text('Notas de Crédito',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showNewCreditNoteDialog(context, db),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nueva Nota de Crédito'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _filterChip('Todas', 'all'),
                _filterChip('Activas', 'active'),
                _filterChip('Aplicadas', 'applied'),
                _filterChip('Canceladas', 'cancelled'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: StreamBuilder<List<CreditNote>>(
                  stream: db.creditNotesDao.watchCreditNotes(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var notes = snapshot.data!;
                    if (_filter != 'all') {
                      notes = notes.where((n) => n.status == _filter).toList();
                    }

                    if (notes.isEmpty) {
                      return const Center(
                          child: Text('No hay notas de crédito'));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return _buildNoteCard(context, db, note);
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
    return FilterChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _buildNoteCard(
      BuildContext context, AppDatabase db, CreditNote note) {
    final statusColor = switch (note.status) {
      'active' => AppColors.info,
      'applied' => AppColors.success,
      'cancelled' => AppColors.error,
      _ => AppColors.textSecondaryLight,
    };
    final statusLabel = switch (note.status) {
      'active' => 'Activa',
      'applied' => 'Aplicada',
      'cancelled' => 'Cancelada',
      _ => note.status,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(Icons.receipt, color: statusColor),
        title: Row(
          children: [
            Text(note.noteNumber,
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
            'Total: ${note.total.currency} | Fecha: ${note.createdAt.formatted} | Motivo: ${note.reason}'),
        children: [
          FutureBuilder<List<CreditNoteItem>>(
            future: db.creditNotesDao.getCreditNoteItems(note.id),
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
                                  flex: 4, child: Text(item.productName)),
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
                    if (note.status == 'active')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () async {
                              await db.creditNotesDao.voidCreditNote(note.id);
                            },
                            child: const Text('Anular',
                                style: TextStyle(color: AppColors.error)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              await db.creditNotesDao
                                  .applyCreditNote(note.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Nota de crédito aplicada')),
                                );
                              }
                            },
                            child: const Text('Aplicar'),
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
  }

  void _showNewCreditNoteDialog(BuildContext context, AppDatabase db) {
    final reasonCtrl = TextEditingController();
    final items = <_CreditNoteItemEntry>[];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva Nota de Crédito'),
          content: SizedBox(
            width: 600,
            height: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: 'return',
                    decoration:
                        const InputDecoration(labelText: 'Motivo'),
                    items: const [
                      DropdownMenuItem(
                          value: 'return', child: Text('Devolución')),
                      DropdownMenuItem(
                          value: 'discount', child: Text('Descuento')),
                      DropdownMenuItem(
                          value: 'error', child: Text('Error en factura')),
                      DropdownMenuItem(
                          value: 'other', child: Text('Otro')),
                    ],
                    onChanged: (v) => reasonCtrl.text = v ?? 'return',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Descripción del motivo'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Productos',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          _showAddCreditItemDialog(context, db, (entry) {
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
                        subtitle:
                            Text('${item.quantity} x ${item.unitPrice.currency}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text((item.quantity * item.unitPrice).currency),
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
                      final noteId = 'cn_${now.millisecondsSinceEpoch}';
                      final subtotal = items.fold<double>(
                          0, (sum, i) => sum + i.quantity * i.unitPrice);
                      final tax = subtotal * 0.15;

                      await db.creditNotesDao.createCreditNote(
                        note: CreditNotesCompanion.insert(
                          id: noteId,
                          noteNumber:
                              'NC-${now.millisecondsSinceEpoch.toString().substring(6)}',
                          reason: reasonCtrl.text.trim().isEmpty
                              ? 'Devolución'
                              : reasonCtrl.text.trim(),
                          subtotal: Value(subtotal),
                          taxAmount: Value(tax),
                          total: Value(subtotal + tax),
                          createdBy: 'admin',
                        ),
                        items: items
                            .map((i) => CreditNoteItemsCompanion.insert(
                                  id: 'cni_${DateTime.now().millisecondsSinceEpoch}_${items.indexOf(i)}',
                                  creditNoteId: noteId,
                                  productId: i.productId,
                                  productName: i.productName,
                                  quantity: i.quantity,
                                  unitPrice: i.unitPrice,
                                  total: i.quantity * i.unitPrice,
                                ))
                            .toList(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: const Text('Crear Nota'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCreditItemDialog(
      BuildContext context, AppDatabase db, Function(_CreditNoteItemEntry) onAdd) {
    final searchCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar Producto'),
          content: SizedBox(
            width: 400,
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Buscar producto...',
                      prefixIcon: Icon(Icons.search)),
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
                        return const Center(child: Text('Sin resultados'));
                      }
                      return ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final p = products[index];
                          return ListTile(
                            dense: true,
                            title: Text(p.name),
                            subtitle: Text(p.salePrice.currency),
                            onTap: () {
                              final qty =
                                  double.tryParse(qtyCtrl.text) ?? 1;
                              onAdd(_CreditNoteItemEntry(
                                productId: p.id,
                                productName: p.name,
                                unitPrice: p.salePrice,
                                quantity: qty,
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
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreditNoteItemEntry {
  final String productId;
  final String productName;
  final double unitPrice;
  final double quantity;

  _CreditNoteItemEntry({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
  });
}
