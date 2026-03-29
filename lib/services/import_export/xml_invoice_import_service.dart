import '../../utils/platform_io.dart'
    if (dart.library.js_interop) '../../utils/platform_io_web.dart';
import 'package:drift/drift.dart';
import 'package:xml/xml.dart';

import '../../data/database/app_database.dart';

/// Imports products from CFDI XML invoices (Mexican/Latin American electronic invoicing)
class XmlInvoiceImportService {
  final AppDatabase _db;

  XmlInvoiceImportService(this._db);

  /// Import products from a single XML invoice file
  Future<XmlImportResult> importFromXml(String filePath) async {
    final content = await File(filePath).readAsString();
    return importFromXmlContent(content, fileName: filePath.split('/').last);
  }

  /// Import products from XML content string
  Future<XmlImportResult> importFromXmlContent(String xmlContent, {String? fileName}) async {
    final errors = <String>[];
    var imported = 0;
    var updated = 0;
    final invoiceInfo = <String, String>{};

    try {
      final document = XmlDocument.parse(xmlContent);
      final root = document.rootElement;

      // Try to extract CFDI invoice info
      _extractInvoiceInfo(root, invoiceInfo);

      // Find product items (Conceptos/Concepto in CFDI)
      final items = _findConceptos(root);

      if (items.isEmpty) {
        return XmlImportResult(
          imported: 0,
          updated: 0,
          errors: ['No se encontraron productos en el XML.'],
          invoiceInfo: invoiceInfo,
        );
      }

      // Get existing categories
      final allCategories = await _db.productsDao.getAllCategories();
      final categoryMap = {
        for (final c in allCategories) c.name.toLowerCase(): c.id,
      };

      for (var i = 0; i < items.length; i++) {
        try {
          final item = items[i];
          final result = await _processConcepto(item, i, categoryMap);
          if (result == 'imported') {
            imported++;
          } else if (result == 'updated') {
            updated++;
          }
        } catch (e) {
          errors.add('Producto ${i + 1}: $e');
        }
      }
    } catch (e) {
      errors.add('Error al parsear XML: $e');
    }

    return XmlImportResult(
      imported: imported,
      updated: updated,
      errors: errors,
      invoiceInfo: invoiceInfo,
    );
  }

  /// Import from multiple XML files at once
  Future<XmlImportResult> importMultipleXml(List<String> filePaths) async {
    var totalImported = 0;
    var totalUpdated = 0;
    final allErrors = <String>[];
    final allInvoiceInfo = <String, String>{};

    for (final path in filePaths) {
      final result = await importFromXml(path);
      totalImported += result.imported;
      totalUpdated += result.updated;
      allErrors.addAll(result.errors.map((e) => '${path.split('/').last}: $e'));
      allInvoiceInfo.addAll(result.invoiceInfo);
    }

    return XmlImportResult(
      imported: totalImported,
      updated: totalUpdated,
      errors: allErrors,
      invoiceInfo: allInvoiceInfo,
    );
  }

  void _extractInvoiceInfo(XmlElement root, Map<String, String> info) {
    // CFDI 3.3/4.0 attributes
    final attrs = root.attributes;
    for (final attr in attrs) {
      switch (attr.localName.toLowerCase()) {
        case 'folio':
          info['Folio'] = attr.value;
        case 'serie':
          info['Serie'] = attr.value;
        case 'fecha':
          info['Fecha'] = attr.value;
        case 'subtotal':
          info['Subtotal'] = '\$${attr.value}';
        case 'total':
          info['Total'] = '\$${attr.value}';
        case 'moneda':
          info['Moneda'] = attr.value;
      }
    }

    // Emisor (Supplier) info
    final emisor = root.findAllElements('*').where((e) =>
        e.localName.toLowerCase() == 'emisor').firstOrNull;
    if (emisor != null) {
      final nombre = emisor.getAttribute('Nombre') ?? emisor.getAttribute('nombre');
      final rfc = emisor.getAttribute('Rfc') ?? emisor.getAttribute('rfc');
      if (nombre != null) info['Proveedor'] = nombre;
      if (rfc != null) info['RFC'] = rfc;
    }
  }

  List<XmlElement> _findConceptos(XmlElement root) {
    // Search for Concepto elements (CFDI standard)
    final results = <XmlElement>[];

    void searchRecursive(XmlElement element) {
      final localName = element.localName.toLowerCase();
      if (localName == 'concepto' || localName == 'item' || localName == 'product') {
        results.add(element);
      }
      for (final child in element.childElements) {
        searchRecursive(child);
      }
    }

    searchRecursive(root);
    return results;
  }

  Future<String> _processConcepto(
    XmlElement item,
    int index,
    Map<String, String> categoryMap,
  ) async {
    // Extract data from CFDI Concepto attributes
    final description = item.getAttribute('Descripcion') ??
        item.getAttribute('descripcion') ??
        item.getAttribute('Description') ??
        _getChildText(item, 'Descripcion') ??
        _getChildText(item, 'Description') ??
        'Producto XML ${index + 1}';

    final claveProdServ = item.getAttribute('ClaveProdServ') ??
        item.getAttribute('claveprodserv');

    final claveUnidad = item.getAttribute('ClaveUnidad') ??
        item.getAttribute('claveunidad');

    final noIdentificacion = item.getAttribute('NoIdentificacion') ??
        item.getAttribute('noidentificacion') ??
        item.getAttribute('Codigo') ??
        _getChildText(item, 'NoIdentificacion') ??
        _getChildText(item, 'Codigo');

    final cantidad = double.tryParse(
        item.getAttribute('Cantidad') ?? item.getAttribute('cantidad') ?? '0') ?? 0;

    final valorUnitario = double.tryParse(
        item.getAttribute('ValorUnitario') ?? item.getAttribute('valorunitario') ?? '0') ?? 0;

    final importe = double.tryParse(
        item.getAttribute('Importe') ?? item.getAttribute('importe') ?? '0') ?? 0;

    final unidad = item.getAttribute('Unidad') ??
        item.getAttribute('unidad') ??
        _mapClaveUnidad(claveUnidad);

    // Check if product exists by code
    Product? existing;
    if (noIdentificacion != null && noIdentificacion.isNotEmpty) {
      existing = await _db.productsDao.getProductByBarcode(noIdentificacion);
    }

    if (existing != null) {
      // Update existing: update cost price and add stock
      await (_db.update(_db.products)..where((p) => p.id.equals(existing!.id))).write(
        ProductsCompanion(
          costPrice: Value(valorUnitario),
          currentStock: Value(existing.currentStock + cantidad),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value('pending'),
        ),
      );
      return 'updated';
    } else {
      // Create new product
      final id = 'prod_xml_${DateTime.now().millisecondsSinceEpoch}_$index';

      // Calculate a default sale price (30% margin)
      final salePrice = valorUnitario > 0 ? valorUnitario * 1.30 : 0.0;

      await _db.productsDao.insertProduct(ProductsCompanion.insert(
        id: id,
        name: description,
        barcode: Value(noIdentificacion),
        costPrice: Value(valorUnitario),
        salePrice: Value(salePrice),
        currentStock: Value(cantidad),
        unit: Value(unidad),
      ));
      return 'imported';
    }
  }

  String? _getChildText(XmlElement parent, String childName) {
    for (final child in parent.childElements) {
      if (child.localName.toLowerCase() == childName.toLowerCase()) {
        return child.innerText.trim();
      }
    }
    return null;
  }

  String _mapClaveUnidad(String? clave) {
    if (clave == null) return 'unidad';
    switch (clave.toUpperCase()) {
      case 'H87':
      case 'EA':
        return 'unidad';
      case 'XBX':
        return 'caja';
      case 'XBO':
      case 'XBT':
        return 'frasco';
      case 'LTR':
        return 'litro';
      case 'KGM':
        return 'kilogramo';
      case 'GRM':
        return 'gramo';
      default:
        return 'unidad';
    }
  }
}

class XmlImportResult {
  final int imported;
  final int updated;
  final List<String> errors;
  final Map<String, String> invoiceInfo;

  XmlImportResult({
    required this.imported,
    required this.updated,
    required this.errors,
    required this.invoiceInfo,
  });

  bool get hasErrors => errors.isNotEmpty;
  int get total => imported + updated;
}
