import 'package:drift/drift.dart' hide Column;
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../../data/database/app_database.dart';

// ══════════════════════════════════════════════════════════════
// ── SMART IMPORT SERVICE (Excel & XML) ──
// ══════════════════════════════════════════════════════════════
/// Unified import service for Excel and XML files.
/// Consistent product matching: barcode → internalCode → name.
class SmartImportService {
  final AppDatabase _db;
  final _uuid = const Uuid();

  SmartImportService(this._db);

  // ══════════════════════════════════════════════════════════════
  // ── UNIFIED PRODUCT MATCH (barcode → internalCode → name) ──
  // ══════════════════════════════════════════════════════════════
  Future<Product?> _findExistingProduct({
    String? barcode,
    String? internalCode,
    required String name,
  }) async {
    final dao = _db.productsDao;

    // 1. Match by barcode (strongest)
    if (barcode != null && barcode.isNotEmpty) {
      final found = await dao.getProductByBarcode(barcode);
      if (found != null) return found;
    }

    // 2. Match by internal code
    if (internalCode != null && internalCode.isNotEmpty) {
      final found = await (
        _db.select(_db.products)
          ..where((p) => p.internalCode.equals(internalCode))
      ).getSingleOrNull();
      if (found != null) return found;
    }

    // 3. Match by exact name (case-insensitive)
    if (name.isNotEmpty) {
      final matches = await dao.searchProducts(name);
      final exact = matches
          .where((p) => p.name.toLowerCase().trim() == name.toLowerCase().trim())
          .firstOrNull;
      if (exact != null) return exact;
    }

    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // ── UNIFIED UPSERT ──
  // ══════════════════════════════════════════════════════════════
  Future<String> _upsertProduct(_ProductData data) async {
    final dao = _db.productsDao;
    final existing = await _findExistingProduct(
      barcode: data.barcode,
      internalCode: data.internalCode,
      name: data.name,
    );

    if (existing != null) {
      // ── UPDATE existing ──
      final newStock = existing.currentStock + data.quantity;
      final companion = ProductsCompanion(
        id: Value(existing.id),
        costPrice: Value(data.costPrice > 0 ? data.costPrice : existing.costPrice),
        salePrice: Value(data.salePrice > 0 ? data.salePrice : existing.salePrice),
        wholesalePrice: data.wholesalePrice != null
            ? Value(data.wholesalePrice)
            : const Value.absent(),
        currentStock: Value(newStock),
        laboratory: data.laboratory != null
            ? Value(data.laboratory)
            : const Value.absent(),
        registroSanitario: data.registroSanitario != null
            ? Value(data.registroSanitario)
            : const Value.absent(),
        presentation: data.presentation != null
            ? Value(data.presentation)
            : const Value.absent(),
        concentration: data.concentration != null
            ? Value(data.concentration)
            : const Value.absent(),
        genericName: data.genericName != null
            ? Value(data.genericName)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      );
      await dao.updateProduct(companion);

      // Create batch if info available
      if (data.batchNumber != null || data.expirationDate != null) {
        await _createBatch(
          productId: existing.id,
          batchNumber: data.batchNumber ?? 'IMP-${_uuid.v4().substring(0, 8)}',
          expirationDate: data.expirationDate ?? DateTime.now().add(const Duration(days: 365)),
          quantity: data.quantity,
          costPrice: data.costPrice,
        );
        return 'updated+batch';
      }
      return 'updated';
    } else {
      // ── INSERT new ──
      final productId = _uuid.v4();
      await dao.insertProduct(ProductsCompanion.insert(
        id: productId,
        name: data.name,
        barcode: Value(data.barcode?.isNotEmpty == true ? data.barcode : null),
        internalCode: Value(data.internalCode?.isNotEmpty == true ? data.internalCode : null),
        genericName: Value(data.genericName),
        description: Value(data.description),
        categoryId: Value(data.categoryId),
        presentation: Value(data.presentation),
        concentration: Value(data.concentration),
        laboratory: Value(data.laboratory),
        costPrice: Value(data.costPrice),
        salePrice: Value(data.salePrice),
        wholesalePrice: Value(data.wholesalePrice),
        taxRate: data.taxRate != null ? Value(data.taxRate!) : const Value.absent(),
        isTaxExempt: Value(data.isTaxExempt),
        currentStock: Value(data.quantity),
        minStock: Value(data.minStock),
        maxStock: Value(data.maxStock),
        unit: Value(data.unit ?? 'unidad'),
        saleType: Value(data.saleType ?? 'Unidad/Pieza'),
        location: Value(data.location),
        shelf: Value(data.shelf),
        requiresPrescription: Value(data.requiresPrescription),
        isControlled: Value(data.isControlled),
        adminRoute: Value(data.adminRoute),
        storageCondition: Value(data.storageCondition),
        registroSanitario: Value(data.registroSanitario),
        usesInventory: Value(data.usesInventory),
        syncStatus: const Value('pending'),
      ));

      // Create batch if info available
      if (data.batchNumber != null || data.expirationDate != null) {
        await _createBatch(
          productId: productId,
          batchNumber: data.batchNumber ?? 'IMP-${_uuid.v4().substring(0, 8)}',
          expirationDate: data.expirationDate ?? DateTime.now().add(const Duration(days: 365)),
          quantity: data.quantity,
          costPrice: data.costPrice,
        );
        return 'imported+batch';
      }
      return 'imported';
    }
  }

  Future<void> _createBatch({
    required String productId,
    required String batchNumber,
    required DateTime expirationDate,
    required double quantity,
    required double costPrice,
  }) async {
    await _db.productsDao.insertBatch(ProductBatchesCompanion.insert(
      id: _uuid.v4(),
      productId: productId,
      batchNumber: batchNumber,
      expirationDate: expirationDate,
      quantity: Value(quantity),
      costPrice: Value(costPrice > 0 ? costPrice : 0),
    ));
  }

  // ══════════════════════════════════════════════════════════════
  // ── 1. EXCEL IMPORT ──
  // ══════════════════════════════════════════════════════════════
  Future<SmartImportResult> importExcel(List<int> bytes) async {
    final excel = Excel.decodeBytes(bytes);
    final errors = <String>[];
    var imported = 0;
    var updated = 0;
    var batches = 0;
    var skipped = 0;

    final sheetName = excel.tables.keys.firstWhere(
      (k) => k.toLowerCase() != 'instrucciones',
      orElse: () => excel.tables.keys.first,
    );
    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.rows.isEmpty) {
      return SmartImportResult(errors: ['No se encontraron datos en el archivo']);
    }

    // Parse headers
    final headerRow = sheet.rows[0];
    final colMapping = <int, String>{};
    for (var i = 0; i < headerRow.length; i++) {
      final cellValue = headerRow[i]?.value?.toString().trim().toLowerCase() ?? '';
      if (cellValue.isEmpty) continue;
      final dbField = _excelColumnMap[cellValue];
      if (dbField != null) colMapping[i] = dbField;
    }

    if (!colMapping.containsValue('name') && !colMapping.containsValue('barcode')) {
      return SmartImportResult(errors: [
        'No se encontraron columnas reconocidas. '
        'La primera fila debe tener encabezados como: Nombre, Código de Barras, Precio Venta, Existencia.'
      ]);
    }

    // Load categories
    final allCategories = await _db.productsDao.getAllCategories();
    final categoryMap = {
      for (final c in allCategories) c.name.toLowerCase(): c.id,
    };

    for (var rowIdx = 1; rowIdx < sheet.rows.length; rowIdx++) {
      final row = sheet.rows[rowIdx];
      if (row.every((c) => c?.value == null || c!.value.toString().trim().isEmpty)) continue;

      try {
        final data = <String, String>{};
        for (final entry in colMapping.entries) {
          if (entry.key < row.length) {
            final cell = row[entry.key];
            if (cell?.value != null) {
              data[entry.value] = cell!.value.toString().trim();
            }
          }
        }

        final name = data['name'] ?? '';
        if (name.isEmpty) { skipped++; continue; }

        final costPrice = _parseNum(data['costPrice']);
        final salePrice = _parseNum(data['salePrice']);
        final stock = _parseNum(data['currentStock']);

        // Auto-create category
        String? categoryId;
        if (data['category'] != null && data['category']!.isNotEmpty) {
          final catLower = data['category']!.toLowerCase();
          categoryId = categoryMap[catLower];
          if (categoryId == null) {
            categoryId = _uuid.v4();
            await _db.productsDao.insertCategory(CategoriesCompanion(
              id: Value(categoryId),
              name: Value(data['category']!),
            ));
            categoryMap[catLower] = categoryId;
          }
        }

        // Parse batch/expiry
        DateTime? expiry;
        if (data['expirationDate'] != null) {
          expiry = DateTime.tryParse(data['expirationDate']!);
        }

        final result = await _upsertProduct(_ProductData(
          name: name,
          barcode: data['barcode'],
          internalCode: data['internalCode'],
          genericName: data['genericName'],
          description: data['description'],
          categoryId: categoryId,
          presentation: data['presentation'],
          concentration: data['concentration'],
          laboratory: data['laboratory'],
          costPrice: costPrice,
          salePrice: salePrice > 0 ? salePrice : (costPrice > 0 ? costPrice * 1.30 : 0),
          wholesalePrice: _parseNumNull(data['wholesalePrice']),
          taxRate: _parseNumNull(data['taxRate']),
          isTaxExempt: _parseBool(data['isTaxExempt']),
          quantity: stock,
          minStock: _parseNum(data['minStock'], fallback: 10),
          maxStock: _parseNumNull(data['maxStock']),
          unit: data['unit'],
          saleType: data['saleType'],
          location: data['location'],
          shelf: data['shelf'],
          requiresPrescription: _parseBool(data['requiresPrescription']),
          isControlled: _parseBool(data['isControlled']),
          adminRoute: data['adminRoute'],
          storageCondition: data['storageCondition'],
          registroSanitario: data['registroSanitario'],
          usesInventory: data['usesInventory'] != null ? _parseBool(data['usesInventory']) : true,
          batchNumber: data['batchNumber'],
          expirationDate: expiry,
        ));

        if (result.startsWith('imported')) imported++;
        if (result.startsWith('updated')) updated++;
        if (result.contains('batch')) batches++;
      } catch (e) {
        errors.add('Fila ${rowIdx + 1}: $e');
      }
    }

    return SmartImportResult(
      imported: imported,
      updated: updated,
      skipped: skipped,
      batches: batches,
      errors: errors,
      source: 'Excel',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── 2. XML IMPORT ──
  // ══════════════════════════════════════════════════════════════
  Future<SmartImportResult> importXml(String xmlContent, {String? fileName}) async {
    final errors = <String>[];
    var imported = 0;
    var updated = 0;
    final invoiceInfo = <String, String>{};

    try {
      final document = XmlDocument.parse(xmlContent);
      var root = document.rootElement;

      // SRI Ecuador: unwrap <autorizacion>
      root = _unwrapSriAutorizacion(root) ?? root;
      _extractInvoiceInfo(root, invoiceInfo);

      final items = _findXmlProducts(root);
      if (items.isEmpty) {
        return SmartImportResult(
          errors: ['No se encontraron productos en el XML${fileName != null ? " ($fileName)" : ""}.'],
          invoiceInfo: invoiceInfo,
          source: 'XML',
        );
      }

      for (var i = 0; i < items.length; i++) {
        try {
          final item = items[i];
          final parsed = _parseXmlItem(item, i);

          final result = await _upsertProduct(parsed);
          if (result.startsWith('imported')) imported++;
          if (result.startsWith('updated')) updated++;
        } catch (e) {
          errors.add('Producto ${i + 1}: $e');
        }
      }
    } catch (e) {
      errors.add('Error al parsear XML: $e');
    }

    return SmartImportResult(
      imported: imported,
      updated: updated,
      errors: errors,
      invoiceInfo: invoiceInfo,
      source: 'XML',
    );
  }

  Future<SmartImportResult> importMultipleXml(List<String> contents, List<String> fileNames) async {
    var totalImported = 0;
    var totalUpdated = 0;
    final allErrors = <String>[];
    final allInvoiceInfo = <String, String>{};

    for (var i = 0; i < contents.length; i++) {
      final result = await importXml(contents[i], fileName: fileNames[i]);
      totalImported += result.imported;
      totalUpdated += result.updated;
      allErrors.addAll(result.errors.map((e) => '${fileNames[i]}: $e'));
      allInvoiceInfo.addAll(result.invoiceInfo);
    }

    return SmartImportResult(
      imported: totalImported,
      updated: totalUpdated,
      errors: allErrors,
      invoiceInfo: allInvoiceInfo,
      source: 'XML',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── XML HELPERS ──
  // ══════════════════════════════════════════════════════════════
  XmlElement? _unwrapSriAutorizacion(XmlElement root) {
    if (root.localName.toLowerCase() != 'autorizacion') return null;
    final comprobante = _xmlChild(root, 'comprobante');
    if (comprobante == null) return null;
    final cdataContent = comprobante.innerText.trim();
    if (cdataContent.isEmpty || !cdataContent.contains('<')) return null;
    try {
      return XmlDocument.parse(cdataContent).rootElement;
    } catch (_) {
      return null;
    }
  }

  void _extractInvoiceInfo(XmlElement root, Map<String, String> info) {
    // CFDI attributes
    for (final attr in root.attributes) {
      switch (attr.localName.toLowerCase()) {
        case 'folio': info['Folio'] = attr.value;
        case 'serie': info['Serie'] = attr.value;
        case 'fecha': info['Fecha'] = attr.value;
        case 'total': info['Total'] = '\$${attr.value}';
      }
    }

    // Emisor (CFDI México)
    final emisor = root.findAllElements('*')
        .where((e) => e.localName.toLowerCase() == 'emisor').firstOrNull;
    if (emisor != null) {
      final nombre = emisor.getAttribute('Nombre') ?? emisor.getAttribute('nombre');
      final rfc = emisor.getAttribute('Rfc') ?? emisor.getAttribute('rfc');
      if (nombre != null) info['Proveedor'] = nombre;
      if (rfc != null) info['RFC'] = rfc;
    }

    // SRI Ecuador
    final infoTrib = _xmlChild(root, 'infoTributaria');
    if (infoTrib != null) {
      final razon = _xmlText(infoTrib, 'razonSocial');
      final ruc = _xmlText(infoTrib, 'ruc');
      final estab = _xmlText(infoTrib, 'estab');
      final ptoEmi = _xmlText(infoTrib, 'ptoEmi');
      final secuencial = _xmlText(infoTrib, 'secuencial');
      if (razon != null) info['Proveedor'] = razon;
      if (ruc != null) info['RUC'] = ruc;
      if (estab != null && ptoEmi != null && secuencial != null) {
        info['Factura'] = '$estab-$ptoEmi-$secuencial';
      }
    }
    final infoFact = _xmlChild(root, 'infoFactura');
    if (infoFact != null) {
      final fecha = _xmlText(infoFact, 'fechaEmision');
      final total = _xmlText(infoFact, 'importeTotal');
      if (fecha != null) info['Fecha'] = fecha;
      if (total != null) info['Total'] = '\$$total';
    }
  }

  List<XmlElement> _findXmlProducts(XmlElement root) {
    final results = <XmlElement>[];
    const productTags = {
      'concepto', 'item', 'product', 'producto', 'detalle',
      'linea', 'articulo', 'det', 'invoiceline',
    };

    void search(XmlElement el) {
      if (productTags.contains(el.localName.toLowerCase())) {
        results.add(el);
      }
      for (final child in el.childElements) {
        search(child);
      }
    }
    search(root);

    // Heuristic fallback
    if (results.isEmpty) {
      const priceAttrs = {'valorunitario', 'preciounitario', 'precio', 'unitprice', 'importe', 'valor'};
      const qtyAttrs = {'cantidad', 'quantity', 'qty', 'cant'};

      void heuristic(XmlElement el) {
        final attrs = el.attributes.map((a) => a.localName.toLowerCase()).toSet();
        final childNames = el.childElements.map((c) => c.localName.toLowerCase()).toSet();
        final hasPrice = attrs.any(priceAttrs.contains) || childNames.any(priceAttrs.contains);
        final hasQty = attrs.any(qtyAttrs.contains) || childNames.any(qtyAttrs.contains);
        if (hasPrice && hasQty) {
          results.add(el);
        } else {
          for (final child in el.childElements) {
            heuristic(child);
          }
        }
      }
      heuristic(root);
    }

    return results;
  }

  _ProductData _parseXmlItem(XmlElement item, int index) {
    String? get_(List<String> names) {
      for (final name in names) {
        final attr = item.getAttribute(name) ?? item.getAttribute(name.toLowerCase());
        if (attr != null && attr.trim().isNotEmpty) return attr.trim();
        final child = _xmlText(item, name);
        if (child != null && child.isNotEmpty) return child;
      }
      return null;
    }

    double getNum_(List<String> names) {
      final val = get_(names);
      if (val == null) return 0;
      return double.tryParse(val.replaceAll(',', '.').replaceAll('\$', '').trim()) ?? 0;
    }

    final description = get_(['Descripcion', 'Description', 'Nombre', 'Name',
        'Producto', 'nombre', 'descripcion', 'codigoAuxiliar']) ?? 'Producto XML ${index + 1}';
    final codigo = get_(['NoIdentificacion', 'Codigo', 'codigo', 'CodigoPrincipal',
        'codigoPrincipal', 'Code', 'SKU', 'Barcode', 'codigoBarras']);
    final cantidad = getNum_(['Cantidad', 'cantidad', 'Quantity', 'qty', 'Cant']);
    final valorUnit = getNum_(['ValorUnitario', 'PrecioUnitario', 'precioUnitario',
        'Precio', 'precio', 'UnitPrice', 'precioSinSubsidio']);
    final importe = getNum_(['Importe', 'importe', 'Amount', 'PrecioTotalSinImpuesto',
        'precioTotalSinImpuesto', 'Total', 'total']);
    final descuento = getNum_(['Descuento', 'descuento', 'Discount', 'discount']);

    double costPrice;
    if (valorUnit > 0) {
      final perUnit = cantidad > 0 && descuento > 0 ? descuento / cantidad : 0.0;
      costPrice = valorUnit - perUnit;
    } else if (cantidad > 0 && importe > 0) {
      costPrice = importe / cantidad;
    } else {
      costPrice = 0;
    }

    return _ProductData(
      name: description,
      barcode: codigo,
      costPrice: costPrice,
      salePrice: costPrice > 0 ? costPrice * 1.30 : 0,
      quantity: cantidad,
      unit: get_(['Unidad', 'unidad', 'Unit']),
    );
  }

  XmlElement? _xmlChild(XmlElement parent, String name) {
    for (final child in parent.childElements) {
      if (child.localName.toLowerCase() == name.toLowerCase()) return child;
    }
    return null;
  }

  String? _xmlText(XmlElement parent, String name) {
    final child = _xmlChild(parent, name);
    return child?.innerText.trim();
  }

  // ══════════════════════════════════════════════════════════════
  // ── HELPERS ──
  // ══════════════════════════════════════════════════════════════
  double _parseNum(String? value, {double fallback = 0}) {
    if (value == null) return fallback;
    return double.tryParse(value.replaceAll('\$', '').replaceAll(',', '').trim()) ?? fallback;
  }

  double? _parseNumNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return double.tryParse(value.replaceAll('\$', '').replaceAll(',', '').trim());
  }

  bool _parseBool(String? value) {
    if (value == null) return false;
    final v = value.toLowerCase().trim();
    return v == 'true' || v == '1' || v == 'sí' || v == 'si' || v == 'yes';
  }

  String? _nonEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  // ── Excel column map ──
  static const _excelColumnMap = {
    'codigo_barras': 'barcode', 'codigo barras': 'barcode',
    'código de barras': 'barcode', 'barcode': 'barcode',
    'codigo': 'barcode', 'código': 'barcode',
    'codigo_interno': 'internalCode', 'codigo interno': 'internalCode',
    'cod. interno': 'internalCode', 'código interno': 'internalCode',
    'nombre': 'name', 'descripcion del producto': 'name',
    'descripción del producto': 'name', 'product name': 'name', 'name': 'name',
    'nombre_generico': 'genericName', 'nombre generico': 'genericName',
    'nombre genérico': 'genericName', 'principio activo': 'genericName',
    'descripcion': 'description', 'descripción': 'description',
    'departamento': 'category', 'categoria': 'category',
    'categoría': 'category', 'category': 'category',
    'presentacion': 'presentation', 'presentación': 'presentation',
    'concentracion': 'concentration', 'concentración': 'concentration',
    'laboratorio': 'laboratory', 'laboratory': 'laboratory',
    'costo': 'costPrice', 'precio_costo': 'costPrice',
    'precio costo': 'costPrice', 'cost': 'costPrice',
    'precio_venta': 'salePrice', 'precio venta': 'salePrice',
    'p. venta': 'salePrice', 'price': 'salePrice', 'p venta': 'salePrice',
    'precio_mayoreo': 'wholesalePrice', 'precio mayoreo': 'wholesalePrice',
    'p. mayoreo': 'wholesalePrice', 'p mayoreo': 'wholesalePrice',
    'existencia': 'currentStock', 'stock': 'currentStock',
    'inventario': 'currentStock', 'cantidad': 'currentStock',
    'stock_minimo': 'minStock', 'stock minimo': 'minStock',
    'inv. mínimo': 'minStock', 'inv. minimo': 'minStock', 'inv minimo': 'minStock',
    'stock_maximo': 'maxStock', 'stock maximo': 'maxStock',
    'inv. máximo': 'maxStock', 'inv. maximo': 'maxStock', 'inv maximo': 'maxStock',
    'unidad': 'unit', 'tipo_venta': 'saleType', 'tipo venta': 'saleType',
    'tipo de venta': 'saleType',
    'ubicacion': 'location', 'ubicación': 'location', 'location': 'location',
    'estante': 'shelf', 'anaquel': 'shelf', 'pasillo': 'shelf', 'shelf': 'shelf',
    'fecha_caducidad': 'expirationDate', 'fecha caducidad': 'expirationDate',
    'caducidad': 'expirationDate', 'vencimiento': 'expirationDate',
    'lote': 'batchNumber', 'batch': 'batchNumber', 'numero de lote': 'batchNumber',
    'receta': 'requiresPrescription', 'requiere_receta': 'requiresPrescription',
    'iva': 'taxRate', 'iva%': 'taxRate', 'tasa iva': 'taxRate', 'impuesto': 'taxRate',
    'exento_iva': 'isTaxExempt', 'exento iva': 'isTaxExempt', 'iva exento': 'isTaxExempt',
    'controlado': 'isControlled', 'sustancia controlada': 'isControlled',
    'via_administracion': 'adminRoute', 'via administración': 'adminRoute',
    'vía administración': 'adminRoute', 'vía de administración': 'adminRoute', 'ruta': 'adminRoute',
    'condicion_almacenamiento': 'storageCondition', 'condición almacenamiento': 'storageCondition',
    'almacenamiento': 'storageCondition',
    'registro_sanitario': 'registroSanitario', 'registro sanitario': 'registroSanitario',
    'reg. sanitario': 'registroSanitario', 'arcsa': 'registroSanitario',
    'usa_inventario': 'usesInventory', 'usa inventario': 'usesInventory',
    'maneja inventario': 'usesInventory',
  };
}

// ══════════════════════════════════════════════════════════════
// ── DATA MODELS ──
// ══════════════════════════════════════════════════════════════
class _ProductData {
  final String name;
  final String? barcode;
  final String? internalCode;
  final String? genericName;
  final String? description;
  final String? categoryId;
  final String? presentation;
  final String? concentration;
  final String? laboratory;
  final double costPrice;
  final double salePrice;
  final double? wholesalePrice;
  final double? taxRate;
  final bool isTaxExempt;
  final double quantity;
  final double minStock;
  final double? maxStock;
  final String? unit;
  final String? saleType;
  final String? location;
  final String? shelf;
  final bool requiresPrescription;
  final bool isControlled;
  final String? adminRoute;
  final String? storageCondition;
  final String? registroSanitario;
  final bool usesInventory;
  final String? batchNumber;
  final DateTime? expirationDate;

  _ProductData({
    required this.name,
    this.barcode,
    this.internalCode,
    this.genericName,
    this.description,
    this.categoryId,
    this.presentation,
    this.concentration,
    this.laboratory,
    this.costPrice = 0,
    this.salePrice = 0,
    this.wholesalePrice,
    this.taxRate,
    this.isTaxExempt = false,
    this.quantity = 0,
    this.minStock = 10,
    this.maxStock,
    this.unit,
    this.saleType,
    this.location,
    this.shelf,
    this.requiresPrescription = false,
    this.isControlled = false,
    this.adminRoute,
    this.storageCondition,
    this.registroSanitario,
    this.usesInventory = true,
    this.batchNumber,
    this.expirationDate,
  });
}

class SmartImportResult {
  final int imported;
  final int updated;
  final int skipped;
  final int batches;
  final bool supplierCreated;
  final String? supplierName;
  final String? invoiceNumber;
  final Map<String, String> invoiceInfo;
  final List<String> errors;
  final String source;

  SmartImportResult({
    this.imported = 0,
    this.updated = 0,
    this.skipped = 0,
    this.batches = 0,
    this.supplierCreated = false,
    this.supplierName,
    this.invoiceNumber,
    this.invoiceInfo = const {},
    this.errors = const [],
    this.source = '',
  });

  bool get hasErrors => errors.isNotEmpty;
  int get totalProducts => imported + updated;
}
