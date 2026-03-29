import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../data/database/app_database.dart';
import '../../data/database/daos/sales_dao.dart';

/// Invoice and receipt printing service
class PrintService {
  /// Print a sales receipt
  Future<void> printReceipt(SaleWithItems saleWithItems) async {
    final sale = saleWithItems.sale;
    final items = saleWithItems.items;
    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity,
          marginAll: 5 * PdfPageFormat.mm),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text('FARMAPOS',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Center(child: pw.Text('Sistema de Farmacia', style: const pw.TextStyle(fontSize: 8))),
            pw.Divider(thickness: 0.5),
            pw.Text('Factura: ${sale.invoiceNumber ?? 'N/A'}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Text(
                'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt)}',
                style: const pw.TextStyle(fontSize: 9)),
            if (sale.customerName != null)
              pw.Text('Cliente: ${sale.customerName}',
                  style: const pw.TextStyle(fontSize: 9)),
            if (sale.customerRuc != null)
              pw.Text('RUC/CI: ${sale.customerRuc}',
                  style: const pw.TextStyle(fontSize: 9)),
            pw.Divider(thickness: 0.5),
            // Items header
            pw.Row(
              children: [
                pw.Expanded(flex: 4, child: pw.Text('Producto', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 1, child: pw.Text('Cant', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                pw.Expanded(flex: 2, child: pw.Text('P.Unit', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                pw.Expanded(flex: 2, child: pw.Text('Total', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
              ],
            ),
            pw.SizedBox(height: 2),
            // Items
            for (final item in items)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                        flex: 4,
                        child: pw.Text(item.productName,
                            style: const pw.TextStyle(fontSize: 8))),
                    pw.Expanded(
                        flex: 1,
                        child: pw.Text(item.quantity.toStringAsFixed(0),
                            style: const pw.TextStyle(fontSize: 8),
                            textAlign: pw.TextAlign.right)),
                    pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                            item.unitPrice.toStringAsFixed(2),
                            style: const pw.TextStyle(fontSize: 8),
                            textAlign: pw.TextAlign.right)),
                    pw.Expanded(
                        flex: 2,
                        child: pw.Text(item.total.toStringAsFixed(2),
                            style: const pw.TextStyle(fontSize: 8),
                            textAlign: pw.TextAlign.right)),
                  ],
                ),
              ),
            pw.Divider(thickness: 0.5),
            // Totals
            _buildTotalRow('Subtotal:', sale.subtotal),
            if (sale.discountAmount > 0)
              _buildTotalRow('Descuento:', -sale.discountAmount),
            _buildTotalRow('IVA:', sale.taxAmount),
            _buildTotalRow('TOTAL:', sale.total, bold: true),
            pw.SizedBox(height: 4),
            pw.Text('Método: ${_paymentMethodLabel(sale.paymentMethod)}',
                style: const pw.TextStyle(fontSize: 8)),
            if (sale.cashReceived != null)
              pw.Text('Recibido: \$${sale.cashReceived!.toStringAsFixed(2)}',
                  style: const pw.TextStyle(fontSize: 8)),
            if (sale.changeGiven != null)
              pw.Text('Cambio: \$${sale.changeGiven!.toStringAsFixed(2)}',
                  style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 8),
            pw.Center(
                child: pw.Text('¡Gracias por su compra!',
                    style: const pw.TextStyle(fontSize: 9))),
            pw.Center(
                child: pw.Text('FarmaPos v2.0',
                    style: const pw.TextStyle(fontSize: 7))),
          ],
        );
      },
    ));

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Recibo - ${sale.invoiceNumber ?? sale.id}',
    );
  }

  /// Print a quotation
  Future<void> printQuotation({
    required Quotation quotation,
    required List<QuotationItem> items,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('FARMAPOS',
                    style: pw.TextStyle(
                        fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('COTIZACIÓN',
                        style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue800)),
                    pw.Text('N° ${quotation.quoteNumber}',
                        style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text(
                'Fecha: ${DateFormat('dd/MM/yyyy').format(quotation.createdAt)}'),
            pw.Text(
                'Válido hasta: ${DateFormat('dd/MM/yyyy').format(quotation.validUntil)}'),
            if (quotation.customerName != null)
              pw.Text('Cliente: ${quotation.customerName}'),
            pw.SizedBox(height: 20),
            // Table
            pw.TableHelper.fromTextArray(
              headers: ['Producto', 'Cant.', 'P. Unit.', 'Desc.', 'Total'],
              data: items
                  .map((i) => [
                        i.productName,
                        i.quantity.toStringAsFixed(0),
                        '\$${i.unitPrice.toStringAsFixed(2)}',
                        '${i.discount.toStringAsFixed(0)}%',
                        '\$${i.total.toStringAsFixed(2)}',
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerRight,
              headerAlignment: pw.Alignment.center,
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(2),
              },
            ),
            pw.SizedBox(height: 10),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                      'Subtotal: \$${quotation.subtotal.toStringAsFixed(2)}'),
                  pw.Text('IVA: \$${quotation.taxAmount.toStringAsFixed(2)}'),
                  pw.Text('TOTAL: \$${quotation.total.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            if (quotation.notes != null) ...[
              pw.SizedBox(height: 20),
              pw.Text('Notas: ${quotation.notes}',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ],
        );
      },
    ));

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Cotización - ${quotation.quoteNumber}',
    );
  }

  static pw.Widget _buildTotalRow(String label, double amount,
      {bool bold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: bold ? 10 : 8,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text('\$${amount.toStringAsFixed(2)}',
            style: pw.TextStyle(
                fontSize: bold ? 10 : 8,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    );
  }

  static String _paymentMethodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      case 'mixed':
        return 'Mixto';
      default:
        return method;
    }
  }
}
