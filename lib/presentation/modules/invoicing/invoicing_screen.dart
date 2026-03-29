import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';

class InvoicingScreen extends ConsumerStatefulWidget {
  const InvoicingScreen({super.key});

  @override
  ConsumerState<InvoicingScreen> createState() => _InvoicingScreenState();
}

class _InvoicingScreenState extends ConsumerState<InvoicingScreen> {
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
                const Text('Facturación Electrónica',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _showConfigDialog(context),
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Configurar SRI'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Stats cards
            Row(
              children: [
                _buildStatCard('Emitidas', '0', AppColors.info, Icons.send),
                const SizedBox(width: 12),
                _buildStatCard(
                    'Autorizadas', '0', AppColors.success, Icons.check_circle),
                const SizedBox(width: 12),
                _buildStatCard(
                    'Rechazadas', '0', AppColors.error, Icons.cancel),
                const SizedBox(width: 12),
                _buildStatCard(
                    'Anuladas', '0', AppColors.warning, Icons.block),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _filterChip('Todas', 'all'),
                _filterChip('Pendientes', 'pending'),
                _filterChip('Firmadas', 'signed'),
                _filterChip('Enviadas', 'sent'),
                _filterChip('Autorizadas', 'authorized'),
                _filterChip('Rechazadas', 'rejected'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: StreamBuilder<List<ElectronicInvoice>>(
                  stream: db.invoicesDao.watchInvoices(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var invoices = snapshot.data!;
                    if (_filter != 'all') {
                      invoices = invoices
                          .where((i) => i.status == _filter)
                          .toList();
                    }

                    if (invoices.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long,
                                size: 64,
                                color: AppColors.textSecondaryLight
                                    .withValues(alpha: 0.5)),
                            const SizedBox(height: 16),
                            const Text('No hay facturas electrónicas'),
                            const SizedBox(height: 8),
                            const Text(
                              'Las facturas se generan automáticamente al realizar ventas',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryLight),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: invoices.length,
                      itemBuilder: (context, index) {
                        final inv = invoices[index];
                        return _buildInvoiceCard(inv);
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

  Widget _buildStatCard(
      String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryLight)),
                ],
              ),
            ],
          ),
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

  Widget _buildInvoiceCard(ElectronicInvoice inv) {
    final statusColor = switch (inv.status) {
      'pending' => AppColors.warning,
      'signed' => AppColors.info,
      'sent' => AppColors.info,
      'authorized' => AppColors.success,
      'rejected' => AppColors.error,
      _ => AppColors.textSecondaryLight,
    };
    final statusLabel = switch (inv.status) {
      'pending' => 'Pendiente',
      'signed' => 'Firmada',
      'sent' => 'Enviada',
      'authorized' => 'Autorizada',
      'rejected' => 'Rechazada',
      _ => inv.status,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.receipt, color: statusColor),
        title: Row(
          children: [
            Text(inv.invoiceNumber,
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
            'Emisión: ${inv.emissionType == "1" ? "Normal" : inv.emissionType} | Total: \$${inv.total.toStringAsFixed(2)} | ${inv.emittedAt.formatted}'),
        trailing: inv.authorizationNumber != null
            ? Tooltip(
                message: 'Autorización: ${inv.authorizationNumber}',
                child: const Icon(Icons.verified, color: AppColors.success),
              )
            : null,
      ),
    );
  }

  void _showConfigDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configuración SRI'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.info, color: AppColors.info),
                title: Text('Facturación Electrónica - SRI Ecuador'),
                subtitle: Text(
                    'Configure su certificado digital (.p12) y datos del emisor para generar comprobantes electrónicos.'),
              ),
              const Divider(),
              TextField(
                decoration: const InputDecoration(
                    labelText: 'RUC del Emisor', hintText: '1234567890001'),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                    labelText: 'Razón Social'),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                    labelText: 'Nombre Comercial'),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                    labelText: 'Dirección del Establecimiento'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: 'test',
                      decoration: const InputDecoration(labelText: 'Ambiente'),
                      items: const [
                        DropdownMenuItem(
                            value: 'test', child: Text('Pruebas')),
                        DropdownMenuItem(
                            value: 'production', child: Text('Producción')),
                      ],
                      onChanged: (_) {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                          labelText: 'Punto de Emisión',
                          hintText: '001'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.upload_file),
                label: const Text('Cargar Certificado Digital (.p12)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
