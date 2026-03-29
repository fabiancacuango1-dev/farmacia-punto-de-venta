import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value, OrderingTerm;

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';

class PromotionsScreen extends ConsumerStatefulWidget {
  const PromotionsScreen({super.key});

  @override
  ConsumerState<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends ConsumerState<PromotionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
                const Text('Promociones y Combos',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showPromotionDialog(context, db),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nueva Promoción'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showComboDialog(context, db),
                  icon: const Icon(Icons.add_box, size: 18),
                  label: const Text('Nuevo Combo'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Promociones'),
                Tab(text: 'Combos / Paquetes'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPromotionsList(db),
                  _buildCombosList(db),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromotionsList(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<Promotion>>(
        stream: (db.promotionsDao.select(db.promotions)
              ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
            .watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final promotions = snapshot.data!;
          if (promotions.isEmpty) {
            return const Center(child: Text('No hay promociones'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: promotions.length,
            itemBuilder: (context, index) {
              final p = promotions[index];
              final isActive = p.isActive &&
                  p.startDate.isBefore(DateTime.now()) &&
                  p.endDate.isAfter(DateTime.now());
              final typeLabel = switch (p.type) {
                'percentage' => 'Descuento %',
                'fixed' => 'Desc. fijo',
                '2x1' => '2x1',
                'combo' => 'Combo',
                'buy_x_get_y' => 'Lleve X Pague Y',
                _ => p.type,
              };

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive
                        ? AppColors.success.withValues(alpha: 0.2)
                        : AppColors.textSecondaryLight.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.local_offer,
                      color: isActive
                          ? AppColors.success
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                          child: Text(p.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(typeLabel,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.info)),
                      ),
                    ],
                  ),
                  subtitle: Text(
                      '${p.startDate.formatted} - ${p.endDate.formatted} | Valor: ${p.value.toStringAsFixed(p.type == "percentage" ? 0 : 2)}${p.type == "percentage" ? "%" : "\$"} | Usos: ${p.usageCount}/${p.usageLimit ?? "∞"}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(isActive ? 'Activa' : 'Inactiva',
                            style: TextStyle(
                                fontSize: 12,
                                color: isActive
                                    ? AppColors.success
                                    : AppColors.error)),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          await (db.promotionsDao.update(db.promotions)
                                ..where(
                                    (p) => p.id.equals(promotions[index].id)))
                              .write(
                                  const PromotionsCompanion(isActive: Value(false)));
                        },
                        tooltip: 'Desactivar',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCombosList(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<ProductCombo>>(
        stream: (db.promotionsDao.select(db.productCombos)
              ..where((c) => c.isActive.equals(true))
              ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
            .watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final combos = snapshot.data!;
          if (combos.isEmpty) {
            return const Center(child: Text('No hay combos'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: combos.length,
            itemBuilder: (context, index) {
              final combo = combos[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  leading:
                      const Icon(Icons.card_giftcard, color: AppColors.primary),
                  title: Text(combo.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      'Precio especial: ${combo.comboPrice.currency} | Precio regular: ${combo.regularPrice.currency}'),
                  children: [
                    FutureBuilder<List<ComboItem>>(
                      future: db.promotionsDao.getComboItems(combo.id),
                      builder: (context, snap) {
                        if (!snap.hasData) return const SizedBox.shrink();
                        final items = snap.data!;
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: items
                                .map((item) => ListTile(
                                      dense: true,
                                      title: Text('Producto: ${item.productId}'),
                                      trailing: Text(
                                          'x${item.quantity.toInt()}'),
                                    ))
                                .toList(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showPromotionDialog(BuildContext context, AppDatabase db) {
    final nameCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    String type = 'percentage';
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 30));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva Promoción'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nombre *'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration:
                        const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(
                          value: 'percentage', child: Text('Porcentaje')),
                      DropdownMenuItem(
                          value: 'fixed', child: Text('Monto fijo')),
                      DropdownMenuItem(value: '2x1', child: Text('2x1')),
                      DropdownMenuItem(
                          value: 'buy_x_get_y',
                          child: Text('Lleve X Pague Y')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => type = v ?? 'percentage'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText:
                          type == 'percentage' ? 'Porcentaje (%)' : 'Valor (\$)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          dense: true,
                          title: const Text('Inicio'),
                          subtitle: Text(startDate.formatted),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) {
                              setDialogState(() => startDate = d);
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          dense: true,
                          title: const Text('Fin'),
                          subtitle: Text(endDate.formatted),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: endDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) {
                              setDialogState(() => endDate = d);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final now = DateTime.now();
                final promoDb = ref.read(appDatabaseProvider);
                await promoDb.into(promoDb.promotions).insert(PromotionsCompanion.insert(
                  id: 'promo_${now.millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  type: type,
                  value: Value(double.tryParse(valueCtrl.text) ?? 0.0),
                  startDate: startDate,
                  endDate: endDate,
                  createdBy: 'admin',
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _showComboDialog(BuildContext context, AppDatabase db) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Combo'),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Precio del combo', prefixText: r'$ '),
              ),
              const SizedBox(height: 12),
              const Text(
                'Después de crear el combo, podrá agregar productos desde la lista.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final now = DateTime.now();
              await db.promotionsDao.createCombo(
                combo: ProductCombosCompanion.insert(
                  id: 'combo_${now.millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  comboPrice: double.tryParse(priceCtrl.text) ?? 0,
                  regularPrice: 0,
                ),
                items: [],
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }
}
