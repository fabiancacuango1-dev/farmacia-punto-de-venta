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
      var root = document.rootElement;

      // SRI Ecuador: <autorizacion><comprobante><![CDATA[<factura>...]]></comprobante></autorizacion>
      root = _unwrapSriAutorizacion(root) ?? root;

      // Try to extract invoice info
      _extractInvoiceInfo(root, invoiceInfo);

      // Find product items (Conceptos/Concepto in CFDI, Detalle in SRI, etc.)
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

    // Emisor (Supplier) info — CFDI México
    final emisor = root.findAllElements('*').where((e) =>
        e.localName.toLowerCase() == 'emisor').firstOrNull;
    if (emisor != null) {
      final nombre = emisor.getAttribute('Nombre') ?? emisor.getAttribute('nombre');
      final rfc = emisor.getAttribute('Rfc') ?? emisor.getAttribute('rfc');
      if (nombre != null) info['Proveedor'] = nombre;
      if (rfc != null) info['RFC'] = rfc;
    }

    // SRI Ecuador: infoTributaria + infoFactura
    final infoTrib = _findChild(root, 'infoTributaria');
    if (infoTrib != null) {
      final razon = _getChildText(infoTrib, 'razonSocial');
      final ruc = _getChildText(infoTrib, 'ruc');
      final estab = _getChildText(infoTrib, 'estab');
      final ptoEmi = _getChildText(infoTrib, 'ptoEmi');
      final secuencial = _getChildText(infoTrib, 'secuencial');
      if (razon != null) info['Proveedor'] = razon;
      if (ruc != null) info['RUC'] = ruc;
      if (estab != null && ptoEmi != null && secuencial != null) {
        info['Factura'] = '$estab-$ptoEmi-$secuencial';
      }
    }
    final infoFact = _findChild(root, 'infoFactura');
    if (infoFact != null) {
      final fecha = _getChildText(infoFact, 'fechaEmision');
      final total = _getChildText(infoFact, 'importeTotal');
      final comprador = _getChildText(infoFact, 'razonSocialComprador');
      if (fecha != null) info['Fecha'] = fecha;
      if (total != null) info['Total'] = '\$$total';
      if (comprador != null) info['Comprador'] = comprador;
    }
  }

  /// Unwrap SRI Ecuador authorized invoice XML
  /// Structure: <autorizacion><comprobante><![CDATA[<factura>...</factura>]]></comprobante></autorizacion>
  XmlElement? _unwrapSriAutorizacion(XmlElement root) {
    if (root.localName.toLowerCase() != 'autorizacion') return null;

    // Find <comprobante> element
    final comprobante = _findChild(root, 'comprobante');
    if (comprobante == null) return null;

    // The CDATA content is the inner factura XML
    final cdataContent = comprobante.innerText.trim();
    if (cdataContent.isEmpty || !cdataContent.contains('<')) return null;

    try {
      final innerDoc = XmlDocument.parse(cdataContent);
      return innerDoc.rootElement;
    } catch (_) {
      return null;
    }
  }

  XmlElement? _findChild(XmlElement parent, String name) {
    for (final child in parent.childElements) {
      if (child.localName.toLowerCase() == name.toLowerCase()) {
        return child;
      }
    }
    return null;
  }

  List<XmlElement> _findConceptos(XmlElement root) {
    // Search for product elements in various XML formats
    final results = <XmlElement>[];
    final productTags = {
      'concepto',    // CFDI México
      'item',        // Generic
      'product',     // Generic
      'producto',    // Spanish generic
      'detalle',     // Common in Latin American invoices
      'linea',       // Some invoice formats
      'articulo',    // Spanish
      'det',         // SRI Ecuador
      'invoiceline', // UBL format
    };

    void searchRecursive(XmlElement element) {
      final localName = element.localName.toLowerCase();
      if (productTags.contains(localName)) {
        results.add(element);
      }
      for (final child in element.childElements) {
        searchRecursive(child);
      }
    }

    searchRecursive(root);

    // If no known tags found, try heuristic: find elements with price-like attributes
    if (results.isEmpty) {
      _findByHeuristic(root, results);
    }

    return results;
  }

  void _findByHeuristic(XmlElement root, List<XmlElement> results) {
    // Look for any element with price/quantity attributes (common in invoices)
    final priceAttrs = {'valorunitario', 'preciounitario', 'precio', 'unitprice', 'amount', 'importe', 'valor'};
    final qtyAttrs = {'cantidad', 'quantity', 'qty', 'cant'};

    void search(XmlElement element) {
      final attrs = element.attributes.map((a) => a.localName.toLowerCase()).toSet();
      final hasPrice = attrs.any((a) => priceAttrs.contains(a));
      final hasQty = attrs.any((a) => qtyAttrs.contains(a));

      // Also check child elements for price/quantity
      final childNames = element.childElements.map((c) => c.localName.toLowerCase()).toSet();
      final hasPriceChild = childNames.any((n) => priceAttrs.contains(n));
      final hasQtyChild = childNames.any((n) => qtyAttrs.contains(n));

      if ((hasPrice || hasPriceChild) && (hasQty || hasQtyChild)) {
        results.add(element);
      } else {
        for (final child in element.childElements) {
          search(child);
        }
      }
    }

    search(root);
  }

  Future<String> _processConcepto(
    XmlElement item,
    int index,
    Map<String, String> categoryMap,
  ) async {
    // Helper to get attribute or child element text (case-insensitive)
    String? _get(XmlElement el, List<String> names) {
      for (final name in names) {
        final attr = el.getAttribute(name) ?? el.getAttribute(name.toLowerCase());
        if (attr != null && attr.trim().isNotEmpty) return attr.trim();
        final child = _getChildText(el, name);
        if (child != null && child.isNotEmpty) return child;
      }
      return null;
    }

    double _getNum(XmlElement el, List<String> names) {
      final val = _get(el, names);
      if (val == null) return 0;
      return double.tryParse(val.replaceAll(',', '.').replaceAll('\$', '').trim()) ?? 0;
    }

    // Extract data flexibly from attributes OR child elements
    final description = _get(item, ['Descripcion', 'Description', 'Nombre', 'Name', 'Producto', 'nombre', 'descripcion', 'codigoAuxiliar']) ??
        'Producto XML ${index + 1}';

    final claveUnidad = _get(item, ['ClaveUnidad', 'claveunidad']);

    final noIdentificacion = _get(item, ['NoIdentificacion', 'Codigo', 'codigo', 'CodigoPrincipal', 'codigoPrincipal', 'Code', 'SKU', 'Barcode', 'codigoBarras']);

    final cantidad = _getNum(item, ['Cantidad', 'cantidad', 'Quantity', 'qty', 'Cant']);

    final valorUnitario = _getNum(item, ['ValorUnitario', 'PrecioUnitario', 'precioUnitario', 'Precio', 'precio', 'UnitPrice', 'precioSinSubsidio']);

    final importe = _getNum(item, ['Importe', 'importe', 'Amount', 'PrecioTotalSinImpuesto', 'precioTotalSinImpuesto', 'Total', 'total']);

    final descuento = _getNum(item, ['Descuento', 'descuento', 'Discount', 'discount']);

    // If no unit price but have importe and cantidad, calculate it
    // For SRI Ecuador: use precioUnitario directly, taking discount into account
    double finalUnitPrice;
    if (valorUnitario > 0) {
      // If there's a per-unit discount, subtract it
      final perUnitDiscount = cantidad > 0 && descuento > 0 ? descuento / cantidad : 0.0;
      finalUnitPrice = valorUnitario - perUnitDiscount;
    } else if (cantidad > 0 && importe > 0) {
      finalUnitPrice = importe / cantidad;
    } else {
      finalUnitPrice = 0.0;
    }

    final unidad = _get(item, ['Unidad', 'unidad', 'Unit']) ??
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
          costPrice: Value(finalUnitPrice),
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
      final salePrice = finalUnitPrice > 0 ? finalUnitPrice * 1.30 : 0.0;

      await _db.productsDao.insertProduct(ProductsCompanion.insert(
        id: id,
        name: description,
        barcode: Value(noIdentificacion),
        costPrice: Value(finalUnitPrice),
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
