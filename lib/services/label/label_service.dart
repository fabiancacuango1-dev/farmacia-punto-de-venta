import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../data/database/app_database.dart';

/// Label printing service
class LabelService {
  /// Generate a PDF label for a product
  Future<pw.Document> generateProductLabel({
    required Product product,
    LabelTemplate? template,
    int copies = 1,
  }) async {
    final pdf = pw.Document();
    final width = template?.width ?? 50;
    final height = template?.height ?? 30;
    final showBarcode = template?.showBarcode ?? true;
    final showPrice = template?.showPrice ?? true;
    final showName = template?.showName ?? true;
    final fontSize = (template?.fontSize ?? 12).toDouble();

    for (var i = 0; i < copies; i++) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat(
          width * PdfPageFormat.mm,
          height * PdfPageFormat.mm,
          marginAll: 2 * PdfPageFormat.mm,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              if (showName)
                pw.Text(
                  product.name,
                  style: pw.TextStyle(
                    fontSize: fontSize - 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  maxLines: 2,
                  textAlign: pw.TextAlign.center,
                ),
              if (showBarcode && product.barcode != null) ...[
                pw.SizedBox(height: 2),
                pw.BarcodeWidget(
                  data: product.barcode!,
                  barcode: pw.Barcode.code128(),
                  width: (width - 8) * PdfPageFormat.mm,
                  height: 12 * PdfPageFormat.mm,
                  drawText: true,
                  textStyle: pw.TextStyle(fontSize: fontSize - 4),
                ),
              ],
              if (showPrice) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  '\$ ${product.salePrice.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: fontSize + 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ],
          );
        },
      ));
    }

    return pdf;
  }

  /// Print a product label
  Future<void> printLabel({
    required Product product,
    LabelTemplate? template,
    int copies = 1,
  }) async {
    final pdf = await generateProductLabel(
      product: product,
      template: template,
      copies: copies,
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Etiqueta - ${product.name}',
    );
  }

  /// Generate shelf labels for multiple products
  Future<pw.Document> generateShelfLabels(List<Product> products) async {
    final pdf = pw.Document();

    // 3 columns x N rows on A4
    const labelsPerRow = 3;
    final labelWidth = (PdfPageFormat.a4.width - 40) / labelsPerRow;
    const labelHeight = 80.0;

    final pages = <List<Product>>[];
    for (var i = 0; i < products.length; i += 21) {
      pages.add(products.sublist(
        i,
        i + 21 > products.length ? products.length : i + 21,
      ));
    }

    for (final pageProducts in pages) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          final rows = <pw.TableRow>[];
          for (var i = 0; i < pageProducts.length; i += labelsPerRow) {
            final rowProducts = pageProducts.sublist(
              i,
              i + labelsPerRow > pageProducts.length
                  ? pageProducts.length
                  : i + labelsPerRow,
            );
            rows.add(pw.TableRow(
              children: [
                for (final prod in rowProducts)
                  pw.Container(
                    width: labelWidth,
                    height: labelHeight,
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          prod.name,
                          style: const pw.TextStyle(fontSize: 8),
                          maxLines: 2,
                          textAlign: pw.TextAlign.center,
                        ),
                        pw.SizedBox(height: 2),
                        if (prod.barcode != null)
                          pw.BarcodeWidget(
                            data: prod.barcode!,
                            barcode: pw.Barcode.code128(),
                            width: labelWidth - 16,
                            height: 20,
                            drawText: true,
                            textStyle: const pw.TextStyle(fontSize: 6),
                          ),
                        pw.Spacer(),
                        pw.Text(
                          '\$ ${prod.salePrice.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Pad empty cells if row is not full
                for (var j = rowProducts.length; j < labelsPerRow; j++)
                  pw.Container(width: labelWidth, height: labelHeight),
              ],
            ));
          }
          return pw.Table(children: rows);
        },
      ));
    }

    return pdf;
  }
}
