import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';

class PrescriptionsScreen extends ConsumerStatefulWidget {
  const PrescriptionsScreen({super.key});

  @override
  ConsumerState<PrescriptionsScreen> createState() =>
      _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends ConsumerState<PrescriptionsScreen> {
  String _filter = 'all';
  final _searchController = TextEditingController();

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
                const Text('Recetas Médicas',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showPrescriptionDialog(context, db),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nueva Receta'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por paciente o doctor...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    _filterChip('Todas', 'all'),
                    _filterChip('Pendientes', 'pending'),
                    _filterChip('Dispensadas', 'dispensed'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: StreamBuilder<List<Prescription>>(
                  stream: db.prescriptionsDao.watchPrescriptions(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var prescriptions = snapshot.data!;

                    if (_filter == 'pending') {
                      prescriptions = prescriptions
                          .where((p) => p.dispensedAt == null)
                          .toList();
                    } else if (_filter == 'dispensed') {
                      prescriptions = prescriptions
                          .where((p) => p.dispensedAt != null)
                          .toList();
                    }

                    final query = _searchController.text.toLowerCase();
                    if (query.isNotEmpty) {
                      prescriptions = prescriptions.where((p) {
                        return p.patientName.toLowerCase().contains(query) ||
                            p.doctorName.toLowerCase().contains(query) ||
                            (p.prescriptionNumber
                                    ?.toLowerCase()
                                    .contains(query) ??
                                false);
                      }).toList();
                    }

                    if (prescriptions.isEmpty) {
                      return const Center(
                          child: Text('No hay recetas médicas'));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: prescriptions.length,
                      itemBuilder: (context, index) {
                        final p = prescriptions[index];
                        return _buildPrescriptionCard(context, db, p);
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

  Widget _buildPrescriptionCard(
      BuildContext context, AppDatabase db, Prescription p) {
    final isPending = p.dispensedAt == null;
    final statusColor = isPending ? AppColors.warning : AppColors.success;
    final statusLabel = isPending ? 'Pendiente' : 'Dispensada';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.2),
          child: Icon(Icons.medical_services, color: statusColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text('Paciente: ${p.patientName}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Doctor: ${p.doctorName}'),
            if (p.prescriptionNumber != null)
              Text('N° Receta: ${p.prescriptionNumber}'),
            Text('Fecha: ${p.prescriptionDate.formatted}'),
            Text('Cantidad: ${p.quantityPrescribed.toStringAsFixed(0)} prescrita / ${p.quantityDispensed.toStringAsFixed(0)} dispensada'),
            if (p.notes != null)
              Text('Notas: ${p.notes}',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        trailing: isPending
            ? ElevatedButton(
                onPressed: () async {
                  await db.prescriptionsDao.markAsDispensed(p.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Receta dispensada')),
                    );
                  }
                },
                child: const Text('Dispensar'),
              )
            : null,
        isThreeLine: true,
      ),
    );
  }

  void _showPrescriptionDialog(BuildContext context, AppDatabase db) {
    final patientCtrl = TextEditingController();
    final doctorCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    DateTime prescDate = DateTime.now();
    String? selectedProductId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva Receta Médica'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: patientCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Paciente *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: doctorCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Doctor *'),
                  ),
                  const SizedBox(height: 12),
                  // Product selector
                  StreamBuilder<List<Product>>(
                    stream: db.productsDao.watchAllProducts(),
                    builder: (context, snap) {
                      final products = snap.data ?? [];
                      return DropdownButtonFormField<String>(
                        value: selectedProductId,
                        decoration: const InputDecoration(
                            labelText: 'Producto/Medicamento *'),
                        items: products
                            .map((p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.name),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setDialogState(() {
                            selectedProductId = v;
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Cantidad Prescrita *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numberCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Número de Receta'),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fecha de la receta'),
                    subtitle: Text(prescDate.formatted),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: prescDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) {
                          setDialogState(() => prescDate = d);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Notas / Diagnóstico'),
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
                if (patientCtrl.text.trim().isEmpty ||
                    doctorCtrl.text.trim().isEmpty ||
                    selectedProductId == null ||
                    qtyCtrl.text.trim().isEmpty) return;
                final qty = double.tryParse(qtyCtrl.text.trim());
                if (qty == null || qty <= 0) return;
                final now = DateTime.now();
                await db.prescriptionsDao.insertPrescription(
                  PrescriptionsCompanion.insert(
                    id: 'presc_${now.millisecondsSinceEpoch}',
                    patientName: patientCtrl.text.trim(),
                    doctorName: doctorCtrl.text.trim(),
                    productId: selectedProductId!,
                    quantityPrescribed: qty,
                    prescriptionDate: prescDate,
                    prescriptionNumber: Value(
                        numberCtrl.text.trim().isEmpty
                            ? null
                            : numberCtrl.text.trim()),
                    notes: Value(notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim()),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}
