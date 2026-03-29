import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../services/label/label_service.dart';

class LabelsScreen extends ConsumerStatefulWidget {
  const LabelsScreen({super.key});

  @override
  ConsumerState<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends ConsumerState<LabelsScreen> {
  final _searchController = TextEditingController();
  final _selectedProducts = <Product>[];

  @override
  void dispose() {
    _searchController.dispose();
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
            Row(
              children: [
                const Text('Etiquetas y Códigos de Barras',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_selectedProducts.isNotEmpty) ...[
                  Text('${_selectedProducts.length} seleccionados',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _printLabels(),
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('Imprimir Etiquetas'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _printShelfLabels(),
                    icon: const Icon(Icons.label, size: 18),
                    label: const Text('Etiquetas de Estante'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // Search
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar productos para etiquetar...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            // Selected products
            if (_selectedProducts.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _selectedProducts.map((p) {
                  return Chip(
                    label: Text(p.name, style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() => _selectedProducts.remove(p));
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            // Products list
            Expanded(
              child: Card(
                child: StreamBuilder<List<Product>>(
                  stream: db.productsDao.watchAllProducts(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var products = snapshot.data!;
                    final query = _searchController.text.toLowerCase();
                    if (query.isNotEmpty) {
                      products = products.where((p) {
                        return p.name.toLowerCase().contains(query) ||
                            (p.barcode?.toLowerCase().contains(query) ??
                                false);
                      }).toList();
                    }

                    if (products.isEmpty) {
                      return const Center(
                          child: Text('No se encontraron productos'));
                    }

                    return ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final p = products[index];
                        final isSelected = _selectedProducts.contains(p);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedProducts.add(p);
                              } else {
                                _selectedProducts.remove(p);
                              }
                            });
                          },
                          title: Text(p.name),
                          subtitle: Text(
                              'Código: ${p.barcode ?? "N/A"} | Precio: \$${p.salePrice.toStringAsFixed(2)}'),
                          secondary: p.barcode != null
                              ? const Icon(Icons.qr_code,
                                  color: AppColors.primary)
                              : const Icon(Icons.qr_code,
                                  color: AppColors.textSecondaryLight),
                        );
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

  Future<void> _printLabels() async {
    final labelService = LabelService();
    for (final product in _selectedProducts) {
      await labelService.printLabel(
        product: product,
      );
    }
  }

  Future<void> _printShelfLabels() async {
    final labelService = LabelService();
    final doc = await labelService.generateShelfLabels(_selectedProducts);
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }
}
