import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/daos/reports_dao.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Text(
                  'Reportes',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _selectDateRange(context),
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    '${_dateRange.start.formatted} - ${_dateRange.end.formatted}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Summary Cards
            FutureBuilder<Map<String, dynamic>>(
              future: db.reportsDao.salesSummary(
                  _dateRange.start, _dateRange.end),
              builder: (context, snapshot) {
                final data = snapshot.data ?? {};
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth > 800 ? 4 : 2;
                    return GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: cols,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 2.5,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _ReportCard(
                          title: 'Ventas Totales',
                          value: ((data['total_revenue'] as num?)
                                      ?.toDouble() ??
                                  0)
                              .currency,
                          icon: Icons.trending_up,
                          color: AppColors.success,
                        ),
                        _ReportCard(
                          title: 'Transacciones',
                          value:
                              (data['sales_count'] as int? ?? 0).toString(),
                          icon: Icons.receipt,
                          color: AppColors.secondary,
                        ),
                        _ReportCard(
                          title: 'IVA Recaudado',
                          value: ((data['total_tax'] as num?)
                                      ?.toDouble() ??
                                  0)
                              .currency,
                          icon: Icons.account_balance,
                          color: AppColors.info,
                        ),
                        _ReportCard(
                          title: 'Descuentos',
                          value: ((data['total_discount'] as num?)
                                      ?.toDouble() ??
                                  0)
                              .currency,
                          icon: Icons.discount,
                          color: AppColors.warning,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),

            // Profit & Top Products
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profit
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ganancias',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 16),
                          FutureBuilder<Map<String, double>>(
                            future: db.reportsDao.profitReport(
                                _dateRange.start, _dateRange.end),
                            builder: (context, snapshot) {
                              final data = snapshot.data ??
                                  {'revenue': 0.0, 'cost': 0.0, 'profit': 0.0};
                              final margin = data['revenue']! > 0
                                  ? (data['profit']! / data['revenue']! * 100)
                                  : 0.0;

                              return Column(
                                children: [
                                  _ProfitRow(
                                    label: 'Ingresos',
                                    value: data['revenue']!.currency,
                                    color: AppColors.success,
                                  ),
                                  _ProfitRow(
                                    label: 'Costos',
                                    value: data['cost']!.currency,
                                    color: AppColors.error,
                                  ),
                                  const Divider(),
                                  _ProfitRow(
                                    label: 'Ganancia Neta',
                                    value: data['profit']!.currency,
                                    color: AppColors.primary,
                                    isBold: true,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Margen: ${margin.percentage}',
                                    style: TextStyle(
                                      color: margin > 20
                                          ? AppColors.success
                                          : AppColors.warning,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Top Products
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Productos Más Vendidos',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 16),
                          FutureBuilder<List<ProductSalesReport>>(
                            future: db.reportsDao.topSellingProducts(
                              start: _dateRange.start,
                              end: _dateRange.end,
                              limit: 10,
                            ),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData ||
                                  snapshot.data!.isEmpty) {
                                return const Center(
                                    child: Text('Sin datos'));
                              }

                              return DataTable(
                                columnSpacing: 20,
                                columns: const [
                                  DataColumn(label: Text('#')),
                                  DataColumn(label: Text('Producto')),
                                  DataColumn(
                                      label: Text('Cant.'), numeric: true),
                                  DataColumn(
                                      label: Text('Ingreso'),
                                      numeric: true),
                                  DataColumn(
                                      label: Text('Ganancia'),
                                      numeric: true),
                                ],
                                rows: snapshot.data!
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                  final i = entry.key;
                                  final p = entry.value;
                                  return DataRow(cells: [
                                    DataCell(Text('${i + 1}')),
                                    DataCell(ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 200),
                                      child: Text(p.productName,
                                          overflow:
                                              TextOverflow.ellipsis),
                                    )),
                                    DataCell(Text(
                                        p.totalQuantity.toInt().toString())),
                                    DataCell(
                                        Text(p.totalRevenue.currency)),
                                    DataCell(Text(
                                      p.totalProfit.currency,
                                      style: TextStyle(
                                        color: p.totalProfit > 0
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                    )),
                                  ]);
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Sales Chart
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ventas por Día',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 250,
                      child: FutureBuilder<List<DailySalesReport>>(
                        future: db.reportsDao.dailySalesBreakdown(
                            _dateRange.start, _dateRange.end),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData ||
                              snapshot.data!.isEmpty) {
                            return const Center(
                                child: Text('Sin datos de ventas'));
                          }

                          final data = snapshot.data!;
                          return BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: data
                                      .map((d) => d.totalRevenue)
                                      .reduce(
                                          (a, b) => a > b ? a : b) *
                                  1.2,
                              barGroups: data
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                return BarChartGroupData(
                                  x: entry.key,
                                  barRods: [
                                    BarChartRodData(
                                      toY: entry.value.totalRevenue,
                                      color: AppColors.primary,
                                      width: 16,
                                      borderRadius:
                                          const BorderRadius.vertical(
                                              top: Radius.circular(4)),
                                    ),
                                  ],
                                );
                              }).toList(),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 60,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        value.currency,
                                        style: const TextStyle(fontSize: 10),
                                      );
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final idx = value.toInt();
                                      if (idx < 0 || idx >= data.length) {
                                        return const SizedBox();
                                      }
                                      return Text(
                                        '${data[idx].date.day}/${data[idx].date.month}',
                                        style: const TextStyle(fontSize: 10),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              gridData: const FlGridData(show: true),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (range != null) {
      setState(() => _dateRange = range);
    }
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ReportCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700),
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

class _ProfitRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _ProfitRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
                fontSize: isBold ? 16 : 14,
              )),
          Text(value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: isBold ? 18 : 14,
              )),
        ],
      ),
    );
  }
}
