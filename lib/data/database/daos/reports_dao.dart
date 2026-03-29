import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/sales_table.dart';
import '../tables/sale_items_table.dart';
import '../tables/products_table.dart';

part 'reports_dao.g.dart';

class ProductSalesReport {
  final String productId;
  final String productName;
  final double totalQuantity;
  final double totalRevenue;
  final double totalProfit;

  ProductSalesReport({
    required this.productId,
    required this.productName,
    required this.totalQuantity,
    required this.totalRevenue,
    required this.totalProfit,
  });
}

class DailySalesReport {
  final DateTime date;
  final int salesCount;
  final double totalRevenue;
  final double totalProfit;

  DailySalesReport({
    required this.date,
    required this.salesCount,
    required this.totalRevenue,
    required this.totalProfit,
  });
}

@DriftAccessor(tables: [Sales, SaleItems, Products])
class ReportsDao extends DatabaseAccessor<AppDatabase>
    with _$ReportsDaoMixin {
  ReportsDao(super.db);

  /// Sales summary for a date range
  Future<Map<String, dynamic>> salesSummary(DateTime start, DateTime end) async {
    final result = await customSelect(
      '''
      SELECT 
        COUNT(*) as sales_count,
        COALESCE(SUM(total), 0) as total_revenue,
        COALESCE(SUM(tax_amount), 0) as total_tax,
        COALESCE(SUM(discount_amount), 0) as total_discount,
        COALESCE(SUM(subtotal), 0) as total_subtotal
      FROM sales 
      WHERE created_at BETWEEN ? AND ? AND status = 'completed'
      ''',
      variables: [Variable.withDateTime(start), Variable.withDateTime(end)],
      readsFrom: {sales},
    ).getSingle();

    return result.data;
  }

  /// Profit report for a date range
  Future<Map<String, double>> profitReport(DateTime start, DateTime end) async {
    final result = await customSelect(
      '''
      SELECT 
        COALESCE(SUM(si.total), 0) as revenue,
        COALESCE(SUM(si.cost_price * si.quantity), 0) as cost,
        COALESCE(SUM(si.total - (si.cost_price * si.quantity)), 0) as profit
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      WHERE s.created_at BETWEEN ? AND ? AND s.status = 'completed'
      ''',
      variables: [Variable.withDateTime(start), Variable.withDateTime(end)],
      readsFrom: {sales, saleItems},
    ).getSingle();

    return {
      'revenue': (result.data['revenue'] as num).toDouble(),
      'cost': (result.data['cost'] as num).toDouble(),
      'profit': (result.data['profit'] as num).toDouble(),
    };
  }

  /// Top selling products
  Future<List<ProductSalesReport>> topSellingProducts({
    required DateTime start,
    required DateTime end,
    int limit = 20,
  }) async {
    final results = await customSelect(
      '''
      SELECT 
        si.product_id,
        si.product_name,
        SUM(si.quantity) as total_quantity,
        SUM(si.total) as total_revenue,
        SUM(si.total - (si.cost_price * si.quantity)) as total_profit
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      WHERE s.created_at BETWEEN ? AND ? AND s.status = 'completed'
      GROUP BY si.product_id, si.product_name
      ORDER BY total_quantity DESC
      LIMIT ?
      ''',
      variables: [
        Variable.withDateTime(start),
        Variable.withDateTime(end),
        Variable.withInt(limit),
      ],
      readsFrom: {sales, saleItems},
    ).get();

    return results.map((row) => ProductSalesReport(
      productId: row.data['product_id'] as String,
      productName: row.data['product_name'] as String,
      totalQuantity: (row.data['total_quantity'] as num).toDouble(),
      totalRevenue: (row.data['total_revenue'] as num).toDouble(),
      totalProfit: (row.data['total_profit'] as num).toDouble(),
    )).toList();
  }

  /// Daily sales breakdown
  Future<List<DailySalesReport>> dailySalesBreakdown(
    DateTime start,
    DateTime end,
  ) async {
    final results = await customSelect(
      '''
      SELECT 
        DATE(created_at) as sale_date,
        COUNT(*) as sales_count,
        COALESCE(SUM(total), 0) as total_revenue,
        COALESCE(SUM(subtotal), 0) as total_subtotal
      FROM sales 
      WHERE created_at BETWEEN ? AND ? AND status = 'completed'
      GROUP BY DATE(created_at)
      ORDER BY sale_date ASC
      ''',
      variables: [Variable.withDateTime(start), Variable.withDateTime(end)],
      readsFrom: {sales},
    ).get();

    return results.map((row) {
      return DailySalesReport(
        date: DateTime.parse(row.data['sale_date'] as String),
        salesCount: row.data['sales_count'] as int,
        totalRevenue: (row.data['total_revenue'] as num).toDouble(),
        totalProfit: 0, // Calculated separately if needed
      );
    }).toList();
  }

  /// Payment method breakdown
  Future<Map<String, double>> paymentMethodBreakdown(
    DateTime start,
    DateTime end,
  ) async {
    final results = await customSelect(
      '''
      SELECT 
        payment_method,
        COALESCE(SUM(total), 0) as total
      FROM sales 
      WHERE created_at BETWEEN ? AND ? AND status = 'completed'
      GROUP BY payment_method
      ''',
      variables: [Variable.withDateTime(start), Variable.withDateTime(end)],
      readsFrom: {sales},
    ).get();

    final breakdown = <String, double>{};
    for (final row in results) {
      breakdown[row.data['payment_method'] as String] =
          (row.data['total'] as num).toDouble();
    }
    return breakdown;
  }
}
