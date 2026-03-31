import 'package:drift/drift.dart' hide Column;
import 'package:xml/xml.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/app_database.dart';

// ══════════════════════════════════════════════════════════════
// ── XML INVOICE PREVIEW SERVICE ──
// ══════════════════════════════════════════════════════════════
/// Parses any XML invoice format and produces a preview model
/// without touching the database. Supports SRI Ecuador, CFDI México,
/// UBL, and generic formats via heuristic detection.
class XmlInvoicePreviewService {
  final AppDatabase _db;
  final _uuid = const Uuid();

  XmlInvoicePreviewService(this._db);

  // ══════════════════════════════════════════════════════════════
  // ── MAIN: Parse XML → InvoicePreview ──
  // ══════════════════════════════════════════════════════════════
  Future<InvoicePreview> parseXml(String xmlContent, {String? fileName}) async {
    final warnings = <String>[];

    try {
      final document = XmlDocument.parse(xmlContent);
      var root = document.rootElement;

      // Detect format
      final format = _detectFormat(root);

      // SRI Ecuador: unwrap <autorizacion>
      final unwrapped = _unwrapSriAutorizacion(root);
      if (unwrapped != null) root = unwrapped;

      // ── Extract header info ──
      final header = _extractHeader(root, format);
      header.detectedFormat = format;
      header.fileName = fileName;

      // ── Extract supplier ──
      final supplier = _extractSupplier(root, format);

      // ── Extract client ──
      final client = _extractClient(root, format);

      // ── Extract all items ──
      final rawItems = _findAllItems(root);
      if (rawItems.isEmpty) {
        return InvoicePreview(
          header: header,
          supplier: supplier,
          client: client,
          items: [],
          totals: InvoiceTotals(),
          warnings: ['No se encontraron productos en el XML${fileName != null ? " ($fileName)" : ""}.'],
          status: PreviewStatus.error,
        );
      }

      final items = <InvoiceItemPreview>[];
      for (var i = 0; i < rawItems.length; i++) {
        try {
          items.add(_parseItem(rawItems[i], i, format));
        } catch (e) {
          warnings.add('Producto ${i + 1}: $e');
        }
      }

      // ── Extract totals from XML (don't calculate) ──
      final totals = _extractTotals(root, format, items);

      // ── Check DB status for each item and supplier ──
      await _enrichWithDbStatus(items, supplier);

      // ── Check duplicate invoice ──
      final isDuplicate = await _checkDuplicateInvoice(header);

      return InvoicePreview(
        header: header,
        supplier: supplier,
        client: client,
        items: items,
        totals: totals,
        warnings: warnings,
        isDuplicate: isDuplicate,
        status: isDuplicate
            ? PreviewStatus.duplicate
            : (warnings.isEmpty ? PreviewStatus.ready : PreviewStatus.readyWithWarnings),
      );
    } catch (e) {
      return InvoicePreview(
        header: InvoiceHeader(),
        supplier: SupplierPreview(),
        client: ClientPreview(),
        items: [],
        totals: InvoiceTotals(),
        warnings: ['Error al parsear XML: $e'],
        status: PreviewStatus.error,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── CONFIRM IMPORT ──
  // ══════════════════════════════════════════════════════════════
  Future<ImportConfirmResult> confirmImport(InvoicePreview preview) async {
    final errors = <String>[];
    var imported = 0;
    var updated = 0;
    var batches = 0;
    String? supplierId;

    try {
      // 1. Create/find supplier
      if (preview.supplier.name != null && preview.supplier.name!.isNotEmpty) {
        supplierId = await _findOrCreateSupplier(preview.supplier);
      }

      // 2. Import products
      for (var i = 0; i < preview.items.length; i++) {
        try {
          final item = preview.items[i];
          final result = await _upsertProduct(item, supplierId);
          if (result.startsWith('imported')) imported++;
          if (result.startsWith('updated')) updated++;
          if (result.contains('batch')) batches++;
        } catch (e) {
          errors.add('Producto ${i + 1} (${preview.items[i].description}): $e');
        }
      }

      // 3. Create purchase order if we have supplier and items
      String? purchaseOrderId;
      if (supplierId != null && (imported + updated) > 0) {
        purchaseOrderId = await _createPurchaseOrder(
          preview: preview,
          supplierId: supplierId,
        );
      }

      return ImportConfirmResult(
        imported: imported,
        updated: updated,
        batches: batches,
        errors: errors,
        supplierCreated: preview.supplier.dbStatus == DbMatchStatus.willCreate,
        supplierName: preview.supplier.name,
        invoiceNumber: preview.header.invoiceNumber,
        purchaseOrderId: purchaseOrderId,
      );
    } catch (e) {
      errors.add('Error general: $e');
      return ImportConfirmResult(
        imported: imported,
        updated: updated,
        errors: errors,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── FORMAT DETECTION ──
  // ══════════════════════════════════════════════════════════════
  String _detectFormat(XmlElement root) {
    final rootName = root.localName.toLowerCase();

    // SRI Ecuador
    if (rootName == 'autorizacion' || rootName == 'factura' ||
        rootName == 'notacredito' || rootName == 'liquidacioncompra') {
      return 'SRI';
    }

    // CFDI México
    if (rootName == 'comprobante' || root.getAttribute('Version') != null ||
        root.getAttribute('version') != null) {
      final ns = root.attributes.any((a) =>
          a.value.contains('cfd') || a.value.contains('sat.gob.mx'));
      if (ns) return 'CFDI';
    }

    // UBL
    if (rootName.contains('invoice') || rootName.contains('creditnote') ||
        root.attributes.any((a) => a.value.contains('oasis') || a.value.contains('ubl'))) {
      return 'UBL';
    }

    return 'Generic';
  }

  // ══════════════════════════════════════════════════════════════
  // ── HEADER EXTRACTION ──
  // ══════════════════════════════════════════════════════════════
  InvoiceHeader _extractHeader(XmlElement root, String format) {
    final header = InvoiceHeader();

    switch (format) {
      case 'SRI':
        final infoTrib = _xmlChild(root, 'infoTributaria');
        if (infoTrib != null) {
          final estab = _xmlText(infoTrib, 'estab');
          final ptoEmi = _xmlText(infoTrib, 'ptoEmi');
          final secuencial = _xmlText(infoTrib, 'secuencial');
          if (estab != null && ptoEmi != null && secuencial != null) {
            header.invoiceNumber = '$estab-$ptoEmi-$secuencial';
          }
          header.accessKey = _xmlText(infoTrib, 'claveAcceso');
          header.invoiceType = _xmlText(infoTrib, 'codDoc');
        }
        final infoFact = _xmlChild(root, 'infoFactura') ??
            _xmlChild(root, 'infoNotaCredito') ??
            _xmlChild(root, 'infoLiquidacionCompra');
        if (infoFact != null) {
          header.issueDate = _xmlText(infoFact, 'fechaEmision');
        }
        break;

      case 'CFDI':
        header.invoiceNumber = root.getAttribute('Folio') ?? root.getAttribute('folio');
        final serie = root.getAttribute('Serie') ?? root.getAttribute('serie');
        if (serie != null && header.invoiceNumber != null) {
          header.invoiceNumber = '$serie-${header.invoiceNumber}';
        }
        header.issueDate = root.getAttribute('Fecha') ?? root.getAttribute('fecha');
        header.invoiceType = root.getAttribute('TipoDeComprobante') ??
            root.getAttribute('tipoDeComprobante');
        break;

      case 'UBL':
        header.invoiceNumber = _xmlTextDeep(root, ['ID', 'cbc:ID']);
        header.issueDate = _xmlTextDeep(root, ['IssueDate', 'cbc:IssueDate']);
        header.invoiceType = _xmlTextDeep(root, ['InvoiceTypeCode', 'cbc:InvoiceTypeCode']);
        break;

      default:
        // Generic: search broadly
        header.invoiceNumber = _findByContext(root, [
          'numero', 'number', 'folio', 'secuencial', 'nrofactura', 'invoicenumber',
        ]);
        header.issueDate = _findByContext(root, [
          'fecha', 'fechaemision', 'issuedate', 'date', 'fechaemisión',
        ]);
    }

    return header;
  }

  // ══════════════════════════════════════════════════════════════
  // ── SUPPLIER EXTRACTION ──
  // ══════════════════════════════════════════════════════════════
  SupplierPreview _extractSupplier(XmlElement root, String format) {
    final s = SupplierPreview();

    switch (format) {
      case 'SRI':
        final infoTrib = _xmlChild(root, 'infoTributaria');
        if (infoTrib != null) {
          s.name = _xmlText(infoTrib, 'razonSocial');
          s.ruc = _xmlText(infoTrib, 'ruc');
          s.commercialName = _xmlText(infoTrib, 'nombreComercial');
          final dir = _xmlText(infoTrib, 'dirMatriz');
          if (dir != null) s.address = dir;
        }
        break;

      case 'CFDI':
        final emisor = _findElementDeep(root, ['Emisor', 'cfdi:Emisor', 'emisor']);
        if (emisor != null) {
          s.name = emisor.getAttribute('Nombre') ?? emisor.getAttribute('nombre');
          s.ruc = emisor.getAttribute('Rfc') ?? emisor.getAttribute('rfc');
        }
        break;

      case 'UBL':
        final supplier = _findElementDeep(root, [
          'AccountingSupplierParty', 'cac:AccountingSupplierParty',
        ]);
        if (supplier != null) {
          s.name = _xmlTextDeep(supplier, [
            'RegistrationName', 'cbc:RegistrationName', 'Name', 'cbc:Name',
          ]);
          s.ruc = _xmlTextDeep(supplier, [
            'CompanyID', 'cbc:CompanyID', 'ID', 'cbc:ID',
          ]);
        }
        break;

      default:
        s.name = _findByContext(root, [
          'razonsocial', 'proveedor', 'emisor', 'supplier', 'vendedor',
          'nombrecomercial', 'empresa',
        ]);
        s.ruc = _findByContext(root, [
          'ruc', 'rfc', 'nit', 'cuit', 'identificacion', 'taxid',
        ]);
    }

    return s;
  }

  // ══════════════════════════════════════════════════════════════
  // ── CLIENT EXTRACTION ──
  // ══════════════════════════════════════════════════════════════
  ClientPreview _extractClient(XmlElement root, String format) {
    final c = ClientPreview();

    switch (format) {
      case 'SRI':
        final infoFact = _xmlChild(root, 'infoFactura') ??
            _xmlChild(root, 'infoNotaCredito');
        if (infoFact != null) {
          c.name = _xmlText(infoFact, 'razonSocialComprador');
          c.identification = _xmlText(infoFact, 'identificacionComprador');
          c.address = _xmlText(infoFact, 'direccionComprador');
        }
        break;

      case 'CFDI':
        final receptor = _findElementDeep(root, ['Receptor', 'cfdi:Receptor', 'receptor']);
        if (receptor != null) {
          c.name = receptor.getAttribute('Nombre') ?? receptor.getAttribute('nombre');
          c.identification = receptor.getAttribute('Rfc') ?? receptor.getAttribute('rfc');
        }
        break;

      case 'UBL':
        final customer = _findElementDeep(root, [
          'AccountingCustomerParty', 'cac:AccountingCustomerParty',
        ]);
        if (customer != null) {
          c.name = _xmlTextDeep(customer, [
            'RegistrationName', 'cbc:RegistrationName', 'Name', 'cbc:Name',
          ]);
          c.identification = _xmlTextDeep(customer, [
            'CompanyID', 'cbc:CompanyID',
          ]);
        }
        break;

      default:
        c.name = _findByContext(root, [
          'cliente', 'comprador', 'receptor', 'customer', 'buyer',
        ]);
        c.identification = _findByContext(root, [
          'identificacioncomprador', 'clienteruc', 'buyerid',
        ]);
    }

    return c;
  }

  // ══════════════════════════════════════════════════════════════
  // ── FIND ALL ITEMS (universal) ──
  // ══════════════════════════════════════════════════════════════
  List<XmlElement> _findAllItems(XmlElement root) {
    final results = <XmlElement>[];
    const productTags = {
      'concepto', 'item', 'product', 'producto', 'detalle',
      'linea', 'articulo', 'det', 'invoiceline', 'creditnoteline',
      'debitnoteline', 'lineitem',
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

    // Heuristic fallback: find elements with price + quantity
    if (results.isEmpty) {
      const priceKeys = {
        'valorunitario', 'preciounitario', 'precio', 'unitprice',
        'importe', 'valor', 'priceamount', 'amount',
      };
      const qtyKeys = {'cantidad', 'quantity', 'qty', 'cant'};

      void heuristic(XmlElement el) {
        final attrNames = el.attributes.map((a) => a.localName.toLowerCase()).toSet();
        final childNames = el.childElements.map((c) => c.localName.toLowerCase()).toSet();
        final allNames = {...attrNames, ...childNames};
        final hasPrice = allNames.any(priceKeys.contains);
        final hasQty = allNames.any(qtyKeys.contains);
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

  // ══════════════════════════════════════════════════════════════
  // ── PARSE SINGLE ITEM ──
  // ══════════════════════════════════════════════════════════════
  InvoiceItemPreview _parseItem(XmlElement item, int index, String format) {
    String? get_(List<String> names) {
      for (final name in names) {
        // Check child elements first (most common in SRI XML)
        final child = _xmlText(item, name);
        if (child != null && child.isNotEmpty) return child;
        // Then check attributes
        final attr = item.getAttribute(name) ?? item.getAttribute(name.toLowerCase());
        if (attr != null && attr.trim().isNotEmpty) return attr.trim();
      }
      return null;
    }

    double getNum_(List<String> names) {
      final val = get_(names);
      if (val == null) return 0;
      return double.tryParse(val.replaceAll(',', '.').replaceAll('\$', '').trim()) ?? 0;
    }

    // ── SRI-specific field names first, then generic ──
    final code = get_([
      'codigoPrincipal', 'CodigoPrincipal',
      'NoIdentificacion', 'Codigo', 'codigo',
      'Code', 'SKU', 'Barcode', 'codigoBarras',
      'SellersItemIdentification', 'ID', 'codigoInterno',
    ]);

    final auxCode = get_([
      'codigoAuxiliar', 'CodigoAuxiliar', 'codigoBarras',
      'BuyersItemIdentification',
    ]);

    final description = get_([
      'descripcion', 'Descripcion', 'Description',
      'Nombre', 'Name', 'Producto', 'nombre',
      'ItemDescription',
    ]) ?? 'Producto XML ${index + 1}';

    final quantity = getNum_([
      'cantidad', 'Cantidad', 'Quantity', 'qty', 'Cant',
      'InvoicedQuantity', 'CreditedQuantity',
    ]);

    final unitPrice = getNum_([
      'precioUnitario', 'PrecioUnitario', 'ValorUnitario',
      'Precio', 'precio', 'UnitPrice', 'precioSinSubsidio',
      'PriceAmount', 'BaseQuantity',
    ]);

    final totalLine = getNum_([
      'precioTotalSinImpuesto', 'PrecioTotalSinImpuesto',
      'Importe', 'importe', 'Amount',
      'Total', 'total', 'LineExtensionAmount',
    ]);

    final discount = getNum_([
      'descuento', 'Descuento', 'Discount', 'discount',
      'AllowanceChargeAmount', 'descuentoValor',
    ]);

    final unit = get_([
      'unidad', 'Unidad', 'Unit', 'ClaveUnidad', 'claveUnidad',
      'UnitCode', 'unitCode',
    ]);

    // ── Tax extraction — SRI uses nested <impuestos><impuesto> ──
    double taxAmount = 0;
    double taxPercent = 0;
    int? taxCode; // SRI: 2=IVA, 3=ICE, 5=IRBPNR

    // Strategy 1: SRI nested impuestos
    final impuestos = _xmlChild(item, 'impuestos');
    if (impuestos != null) {
      for (final imp in impuestos.childElements) {
        final val = double.tryParse(
            _xmlText(imp, 'valor')?.replaceAll(',', '.') ?? '0') ?? 0;
        taxAmount += val;
        final tarifa = double.tryParse(
            _xmlText(imp, 'tarifa')?.replaceAll(',', '.') ?? '0') ?? 0;
        if (tarifa > 0) taxPercent = tarifa;
        final codigo = int.tryParse(_xmlText(imp, 'codigo') ?? '');
        if (codigo != null) taxCode = codigo;
        // SRI codigoPorcentaje: 0=IVA 0%, 2=IVA 12%, 3=IVA 14%, 4=IVA 15%, 6=IVA 5%
        final codPct = int.tryParse(_xmlText(imp, 'codigoPorcentaje') ?? '');
        if (codPct != null && taxPercent == 0) {
          taxPercent = switch (codPct) {
            0 => 0,
            2 => 12,
            3 => 14,
            4 => 15,
            6 => 5,
            _ => 0,
          };
        }
      }
    }

    // Strategy 2: Direct fields (CFDI, UBL)
    if (taxAmount == 0) {
      taxAmount = getNum_(['valorImpuesto', 'TaxAmount', 'valor']);
    }
    if (taxPercent == 0) {
      taxPercent = getNum_(['tarifa', 'TaxPercent', 'Tasa', 'Porcentaje', 'porcentaje']);
    }

    // ── Calculate cost price ──
    double costPrice;
    if (unitPrice > 0) {
      final perUnitDiscount = quantity > 0 && discount > 0 ? discount / quantity : 0.0;
      costPrice = unitPrice - perUnitDiscount;
    } else if (quantity > 0 && totalLine > 0) {
      costPrice = totalLine / quantity;
    } else {
      costPrice = 0;
    }

    final subtotal = totalLine > 0
        ? totalLine
        : (quantity > 0 && costPrice > 0 ? quantity * costPrice : 0.0);

    // ── Determine tax status ──
    bool? isTaxExempt;
    double? detectedTaxRate;
    if (taxCode == 2) {
      // IVA
      isTaxExempt = taxPercent == 0;
      detectedTaxRate = taxPercent;
    } else if (taxPercent >= 0) {
      isTaxExempt = taxPercent == 0;
      detectedTaxRate = taxPercent;
    }

    // ── Extract "detalle adicional" info (SRI extra fields) ──
    String? batchNumber;
    String? expirationDate;
    final detallesAdicionales = _xmlChild(item, 'detallesAdicionales');
    if (detallesAdicionales != null) {
      for (final da in detallesAdicionales.childElements) {
        final nombre = (da.getAttribute('nombre') ?? '').toLowerCase();
        final valor = da.getAttribute('valor') ?? da.innerText.trim();
        if (nombre.contains('lote') || nombre.contains('lot') || nombre.contains('batch')) {
          batchNumber = valor;
        }
        if (nombre.contains('vencimiento') || nombre.contains('expir') || nombre.contains('caduc') || nombre.contains('fech')) {
          expirationDate = valor;
        }
      }
    }

    final result = InvoiceItemPreview(
      index: index,
      code: code,
      auxCode: auxCode,
      description: description,
      quantity: quantity > 0 ? quantity : 1,
      unitPrice: unitPrice,
      discount: discount,
      taxAmount: taxAmount,
      taxPercent: taxPercent > 0 ? taxPercent : (taxAmount > 0 && subtotal > 0 ? (taxAmount / subtotal * 100) : 0),
      subtotal: subtotal,
      total: subtotal + taxAmount - discount,
      unit: unit,
      costPrice: costPrice,
      batchNumber: batchNumber,
      expirationDate: expirationDate,
      isTaxExempt: isTaxExempt,
      detectedTaxRate: detectedTaxRate,
    );

    // Enrich with pharmaceutical data from description
    _enrichWithPharmaData(result);

    return result;
  }

  // ══════════════════════════════════════════════════════════════
  // ── PHARMACEUTICAL INTELLIGENCE (local enrichment from description) ──
  // ══════════════════════════════════════════════════════════════
  void _enrichWithPharmaData(InvoiceItemPreview item) {
    final desc = item.description.toUpperCase();

    // Concentration extraction
    final concMatch = RegExp(
      r'(\d+(?:[,.]\d+)?)\s*(MG|G|ML|MCG|UG|UI|%|MG/ML|G/ML|MG/5ML|MG/DL)',
      caseSensitive: false,
    ).firstMatch(desc);
    if (concMatch != null) {
      item.concentration ??= '${concMatch.group(1)}${concMatch.group(2)!.toLowerCase()}';
    }

    // Presentation detection
    const presentations = {
      'TABLETA': 'Tableta', 'TAB': 'Tableta', 'TABS': 'Tableta', 'COMPRIMIDO': 'Tableta',
      'CAPSULA': 'Cápsula', 'CAP': 'Cápsula', 'CAPS': 'Cápsula',
      'JARABE': 'Jarabe', 'JBE': 'Jarabe', 'SUSPENSIÓN': 'Suspensión', 'SUSP': 'Suspensión',
      'CREMA': 'Crema', 'POMADA': 'Pomada', 'GEL': 'Gel', 'UNGÜENTO': 'Pomada',
      'AMPOLLA': 'Ampolla', 'AMP': 'Ampolla', 'INYECTABLE': 'Inyectable', 'INY': 'Inyectable',
      'GOTAS': 'Gotas', 'SOLUCIÓN': 'Solución', 'SOL': 'Solución',
      'SUPOSITORIO': 'Supositorio', 'ÓVULO': 'Óvulo', 'OVULO': 'Óvulo',
      'PARCHE': 'Parche', 'POLVO': 'Polvo', 'SPRAY': 'Spray', 'INHALADOR': 'Inhalador',
      'EMULSIÓN': 'Emulsión', 'LOCIÓN': 'Loción',
    };
    if (item.presentation == null) {
      for (final entry in presentations.entries) {
        if (desc.contains(entry.key)) {
          item.presentation = entry.value;
          break;
        }
      }
    }

    // Admin route from presentation
    if (item.adminRoute == null && item.presentation != null) {
      item.adminRoute = switch (item.presentation) {
        'Tableta' || 'Cápsula' || 'Jarabe' || 'Suspensión' || 'Gotas' => 'Oral',
        'Crema' || 'Pomada' || 'Gel' || 'Loción' || 'Parche' => 'Tópica',
        'Ampolla' || 'Inyectable' => 'Parenteral',
        'Supositorio' => 'Rectal',
        'Óvulo' => 'Vaginal',
        'Inhalador' || 'Spray' => 'Inhalatoria',
        _ => null,
      };
    }

    // Units per box detection
    if (item.unitsPerBox == null) {
      final unitsMatch = RegExp(r'[Xx]\s*(\d+)\s*(?:UND|UNID|TAB|CAP|AMP|COMP)?', caseSensitive: false).firstMatch(desc);
      if (unitsMatch != null) {
        item.unitsPerBox = int.tryParse(unitsMatch.group(1)!);
      }
    }

    // Known laboratories
    const labs = [
      'BAYER', 'PFIZER', 'ROCHE', 'NOVARTIS', 'SANOFI', 'GENFAR', 'MK',
      'LIFE', 'GRUPO FARMA', 'FARMAYALA', 'ACROMAX', 'NIFA', 'LAMOSAN',
      'TECNANDINA', 'BAGO', 'ROEMMERS', 'RECALCINE', 'GRÜNENTHAL',
      'GRUNENTHAL', 'MEDICAMENTA', 'INDEUREC', 'KRONOS', 'QUIFATEX',
      'LETERAGO', 'ECUAQUÍMICA', 'ECUAQUIMICA', 'JAMES BROWN', 'CHALVER',
      'ABBOTT', 'JOHNSON', 'ASTRAZENECA', 'GSK', 'MERCK', 'NESTLÉ', 'NESTLE',
      'GENOMMALAB', 'MEGA', 'STEIN', 'QUALIPHARM',
    ];
    if (item.laboratory == null) {
      for (final lab in labs) {
        if (desc.contains(lab)) {
          item.laboratory = lab[0] + lab.substring(1).toLowerCase();
          break;
        }
      }
    }

    // Known controlled substances
    const controlled = [
      'TRAMADOL', 'MORFINA', 'CODEINA', 'FENTANILO', 'DIAZEPAM',
      'CLONAZEPAM', 'ALPRAZOLAM', 'LORAZEPAM', 'MIDAZOLAM', 'FENOBARBITAL',
      'METILFENIDATO', 'OXICODONA', 'METADONA', 'ZOLPIDEM', 'PREGABALINA',
    ];
    if (item.isControlled == null) {
      for (final sub in controlled) {
        if (desc.contains(sub)) {
          item.isControlled = true;
          item.requiresPrescription = true;
          break;
        }
      }
    }

    // Prescription medicines
    const prescriptionRequired = [
      'ANTIBIOTICO', 'ANTIBIÓTICO', 'AMOXICILINA', 'AZITROMICINA',
      'CIPROFLOXACIN', 'METFORMINA', 'LOSARTAN', 'ENALAPRIL', 'ATORVASTATIN',
      'OMEPRAZOL', 'INSULINA', 'WARFARINA', 'PREDNISONA', 'DEXAMETASONA',
      'FLUOXETINA', 'SERTRALINA', 'LEVOTIROXINA',
    ];
    if (item.requiresPrescription == null) {
      for (final med in prescriptionRequired) {
        if (desc.contains(med)) {
          item.requiresPrescription = true;
          break;
        }
      }
    }

    // Tax status — in Ecuador medicines for human use are IVA 0%
    item.isTaxExempt ??= (item.taxAmount == 0 || item.taxPercent == 0);
    item.detectedTaxRate ??= item.taxPercent > 0 ? item.taxPercent : 0;

    // Storage conditions
    const refrigeration = ['INSULINA', 'VACUNA', 'BIOLÓGICO', 'BIOLOGICO', 'REFRIGER'];
    if (item.storageCondition == null) {
      for (final kw in refrigeration) {
        if (desc.contains(kw)) {
          item.storageCondition = 'Refrigeración';
          break;
        }
      }
      item.storageCondition ??= 'Ambiente';
    }

    // Sale type
    item.saleType ??= 'Unidad/Pieza';

    // Generic name — first word that looks pharmaceutical
    if (item.genericName == null) {
      final words = item.description.split(RegExp(r'\s+'));
      if (words.isNotEmpty && words[0].length > 3) {
        item.genericName = words[0][0].toUpperCase() + words[0].substring(1).toLowerCase();
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── TOTALS EXTRACTION ──
  // ══════════════════════════════════════════════════════════════
  InvoiceTotals _extractTotals(XmlElement root, String format, List<InvoiceItemPreview> items) {
    final t = InvoiceTotals();

    switch (format) {
      case 'SRI':
        final infoFact = _xmlChild(root, 'infoFactura') ??
            _xmlChild(root, 'infoNotaCredito');
        if (infoFact != null) {
          t.xmlSubtotal = _numFromXml(infoFact, 'totalSinImpuestos');
          t.xmlTotal = _numFromXml(infoFact, 'importeTotal');
          t.xmlDiscount = _numFromXml(infoFact, 'totalDescuento');

          // Extract IVA totals
          final totalConImp = _xmlChild(infoFact, 'totalConImpuestos');
          if (totalConImp != null) {
            for (final imp in totalConImp.childElements) {
              final valor = _numFromXml(imp, 'valor') ?? 0;
              t.xmlTax = (t.xmlTax ?? 0) + valor;
            }
          }
        }
        break;

      case 'CFDI':
        t.xmlSubtotal = double.tryParse(
            root.getAttribute('SubTotal') ?? root.getAttribute('subTotal') ?? '');
        t.xmlTotal = double.tryParse(
            root.getAttribute('Total') ?? root.getAttribute('total') ?? '');
        t.xmlDiscount = double.tryParse(
            root.getAttribute('Descuento') ?? root.getAttribute('descuento') ?? '');
        // Impuestos
        final impuestos = _findElementDeep(root, ['Impuestos', 'cfdi:Impuestos']);
        if (impuestos != null) {
          t.xmlTax = double.tryParse(
              impuestos.getAttribute('TotalImpuestosTrasladados') ??
              impuestos.getAttribute('totalImpuestosTrasladados') ?? '');
        }
        break;

      case 'UBL':
        final legalTotal = _findElementDeep(root, [
          'LegalMonetaryTotal', 'cac:LegalMonetaryTotal',
        ]);
        if (legalTotal != null) {
          t.xmlSubtotal = _numField(legalTotal, ['LineExtensionAmount', 'cbc:LineExtensionAmount']);
          t.xmlTotal = _numField(legalTotal, ['PayableAmount', 'cbc:PayableAmount']);
        }
        final taxTotal = _findElementDeep(root, ['TaxTotal', 'cac:TaxTotal']);
        if (taxTotal != null) {
          t.xmlTax = _numField(taxTotal, ['TaxAmount', 'cbc:TaxAmount']);
        }
        break;
    }

    // Calculate from items as fallback/verification
    t.calculatedSubtotal = items.fold(0.0, (sum, i) => sum + i.subtotal);
    t.calculatedTax = items.fold(0.0, (sum, i) => sum + i.taxAmount);
    t.calculatedDiscount = items.fold(0.0, (sum, i) => sum + i.discount);
    t.calculatedTotal = t.calculatedSubtotal + t.calculatedTax - t.calculatedDiscount;

    // Validate consistency
    if (t.xmlTotal != null && t.calculatedTotal > 0) {
      final diff = (t.xmlTotal! - t.calculatedTotal).abs();
      t.totalsMatch = diff < 0.05; // tolerate rounding
    }

    return t;
  }

  // ══════════════════════════════════════════════════════════════
  // ── DB STATUS ENRICHMENT ──
  // ══════════════════════════════════════════════════════════════
  Future<void> _enrichWithDbStatus(List<InvoiceItemPreview> items, SupplierPreview supplier) async {
    final dao = _db.productsDao;

    // Check supplier
    if (supplier.ruc != null && supplier.ruc!.isNotEmpty) {
      final existing = await (_db.select(_db.suppliers)
            ..where((s) => s.ruc.equals(supplier.ruc!)))
          .getSingleOrNull();
      if (existing != null) {
        supplier.dbStatus = DbMatchStatus.exists;
        supplier.existingId = existing.id;
      } else {
        supplier.dbStatus = DbMatchStatus.willCreate;
      }
    } else if (supplier.name != null && supplier.name!.isNotEmpty) {
      final allSuppliers = await _db.purchasesDao.getAllSuppliers();
      final match = allSuppliers
          .where((s) => s.name.toLowerCase().trim() == supplier.name!.toLowerCase().trim())
          .firstOrNull;
      if (match != null) {
        supplier.dbStatus = DbMatchStatus.exists;
        supplier.existingId = match.id;
      } else {
        supplier.dbStatus = DbMatchStatus.willCreate;
      }
    }

    // Check each product
    for (final item in items) {
      // 1. Barcode match
      if (item.code != null && item.code!.isNotEmpty) {
        final found = await dao.getProductByBarcode(item.code!);
        if (found != null) {
          item.dbStatus = DbMatchStatus.exists;
          item.existingProductId = found.id;
          item.existingProductName = found.name;
          item.currentStock = found.currentStock;
          continue;
        }
      }

      // 2. Internal code match
      if (item.code != null && item.code!.isNotEmpty) {
        final found = await (_db.select(_db.products)
              ..where((p) => p.internalCode.equals(item.code!)))
            .getSingleOrNull();
        if (found != null) {
          item.dbStatus = DbMatchStatus.exists;
          item.existingProductId = found.id;
          item.existingProductName = found.name;
          item.currentStock = found.currentStock;
          continue;
        }
      }

      // 3. Aux code
      if (item.auxCode != null && item.auxCode!.isNotEmpty) {
        final found = await dao.getProductByBarcode(item.auxCode!);
        if (found != null) {
          item.dbStatus = DbMatchStatus.exists;
          item.existingProductId = found.id;
          item.existingProductName = found.name;
          item.currentStock = found.currentStock;
          continue;
        }
      }

      // 4. Exact name match
      if (item.description.isNotEmpty) {
        final matches = await dao.searchProducts(item.description);
        final exact = matches
            .where((p) => p.name.toLowerCase().trim() == item.description.toLowerCase().trim())
            .firstOrNull;
        if (exact != null) {
          item.dbStatus = DbMatchStatus.exists;
          item.existingProductId = exact.id;
          item.existingProductName = exact.name;
          item.currentStock = exact.currentStock;
          continue;
        }
      }

      item.dbStatus = DbMatchStatus.willCreate;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── DUPLICATE CHECK ──
  // ══════════════════════════════════════════════════════════════
  Future<bool> _checkDuplicateInvoice(InvoiceHeader header) async {
    if (header.invoiceNumber == null || header.invoiceNumber!.isEmpty) return false;
    // Check in purchase orders
    final orders = await _db.purchasesDao.getPurchaseOrders();
    return orders.any((o) =>
        o.orderNumber.toLowerCase().trim() == header.invoiceNumber!.toLowerCase().trim());
  }

  // ══════════════════════════════════════════════════════════════
  // ── FIND/CREATE SUPPLIER ──
  // ══════════════════════════════════════════════════════════════
  Future<String> _findOrCreateSupplier(SupplierPreview s) async {
    if (s.existingId != null) return s.existingId!;

    // Try find by RUC
    if (s.ruc != null && s.ruc!.isNotEmpty) {
      final existing = await (_db.select(_db.suppliers)
            ..where((sup) => sup.ruc.equals(s.ruc!)))
          .getSingleOrNull();
      if (existing != null) return existing.id;
    }

    // Create new
    final id = _uuid.v4();
    await _db.purchasesDao.insertSupplier(SuppliersCompanion(
      id: Value(id),
      name: Value(s.name ?? 'Proveedor XML'),
      ruc: Value(s.ruc),
      address: Value(s.address),
      syncStatus: const Value('pending'),
    ));
    return id;
  }

  // ══════════════════════════════════════════════════════════════
  // ── UPSERT PRODUCT ──
  // ══════════════════════════════════════════════════════════════
  Future<String> _upsertProduct(InvoiceItemPreview item, String? supplierId) async {
    final dao = _db.productsDao;

    if (item.existingProductId != null) {
      // UPDATE existing
      final existing = await (
        _db.select(_db.products)
          ..where((p) => p.id.equals(item.existingProductId!))
      ).getSingle();

      final newStock = existing.currentStock + item.quantity;
      await dao.updateProduct(ProductsCompanion(
        id: Value(existing.id),
        costPrice: Value(item.costPrice > 0 ? item.costPrice : existing.costPrice),
        salePrice: Value(item.costPrice > 0 ? item.costPrice * 1.30 : existing.salePrice),
        currentStock: Value(newStock),
        // Update pharmacy fields only if item has value and existing is empty
        genericName: item.genericName != null && (existing.genericName == null || existing.genericName!.isEmpty)
            ? Value(item.genericName!) : const Value.absent(),
        presentation: item.presentation != null && (existing.presentation == null || existing.presentation!.isEmpty)
            ? Value(item.presentation!) : const Value.absent(),
        concentration: item.concentration != null && (existing.concentration == null || existing.concentration!.isEmpty)
            ? Value(item.concentration!) : const Value.absent(),
        laboratory: item.laboratory != null && (existing.laboratory == null || existing.laboratory!.isEmpty)
            ? Value(item.laboratory!) : const Value.absent(),
        registroSanitario: item.registroSanitario != null && (existing.registroSanitario == null || existing.registroSanitario!.isEmpty)
            ? Value(item.registroSanitario!) : const Value.absent(),
        adminRoute: item.adminRoute != null && (existing.adminRoute == null || existing.adminRoute!.isEmpty)
            ? Value(item.adminRoute!) : const Value.absent(),
        requiresPrescription: item.requiresPrescription != null && existing.requiresPrescription == false
            ? Value(item.requiresPrescription!) : const Value.absent(),
        isControlled: item.isControlled != null && existing.isControlled == false
            ? Value(item.isControlled!) : const Value.absent(),
        isTaxExempt: item.isTaxExempt != null
            ? Value(item.isTaxExempt!) : const Value.absent(),
        taxRate: item.detectedTaxRate != null
            ? Value(item.detectedTaxRate!) : const Value.absent(),
        unitsPerBox: item.unitsPerBox != null && (existing.unitsPerBox == null || existing.unitsPerBox == 0)
            ? Value(item.unitsPerBox!) : const Value.absent(),
        storageCondition: item.storageCondition != null && (existing.storageCondition == null || existing.storageCondition!.isEmpty)
            ? Value(item.storageCondition!) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ));
      return 'updated';
    } else {
      // INSERT new with ALL pharmacy fields
      final productId = _uuid.v4();
      await dao.insertProduct(ProductsCompanion.insert(
        id: productId,
        name: item.description,
        barcode: Value(item.code),
        internalCode: Value(item.auxCode ?? item.code),
        genericName: Value(item.genericName),
        presentation: Value(item.presentation),
        concentration: Value(item.concentration),
        laboratory: Value(item.laboratory),
        registroSanitario: Value(item.registroSanitario),
        adminRoute: Value(item.adminRoute),
        costPrice: Value(item.costPrice),
        salePrice: Value(item.costPrice > 0 ? item.costPrice * 1.30 : 0),
        currentStock: Value(item.quantity),
        unit: Value(item.unit ?? 'unidad'),
        saleType: Value(item.saleType ?? 'Unidad/Pieza'),
        requiresPrescription: Value(item.requiresPrescription ?? false),
        isControlled: Value(item.isControlled ?? false),
        isTaxExempt: Value(item.isTaxExempt ?? true),
        taxRate: Value(item.detectedTaxRate ?? 0),
        unitsPerBox: Value(item.unitsPerBox ?? 0),
        storageCondition: Value(item.storageCondition),
        syncStatus: const Value('pending'),
      ));
      return 'imported';
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── CREATE PURCHASE ORDER ──
  // ══════════════════════════════════════════════════════════════
  Future<String> _createPurchaseOrder({
    required InvoicePreview preview,
    required String supplierId,
  }) async {
    final orderId = _uuid.v4();
    final orderNumber = preview.header.invoiceNumber ?? 'XML-${DateTime.now().millisecondsSinceEpoch}';

    // Get current user — use 'system' as fallback
    final users = await _db.select(_db.users).get();
    final userId = users.isNotEmpty ? users.first.id : 'system';

    final subtotal = preview.totals.xmlSubtotal ?? preview.totals.calculatedSubtotal;
    final tax = preview.totals.xmlTax ?? preview.totals.calculatedTax;
    final total = preview.totals.xmlTotal ?? preview.totals.calculatedTotal;

    await _db.purchasesDao.createPurchaseOrder(
      order: PurchaseOrdersCompanion(
        id: Value(orderId),
        orderNumber: Value(orderNumber),
        supplierId: Value(supplierId),
        createdBy: Value(userId),
        subtotal: Value(subtotal),
        taxAmount: Value(tax),
        total: Value(total),
        status: const Value('received'),
        receivedDate: Value(DateTime.now()),
        notes: Value('Importado desde XML: ${preview.header.fileName ?? "factura"}'),
        syncStatus: const Value('pending'),
      ),
      items: preview.items.map((item) {
        final productId = item.existingProductId ?? _uuid.v4();
        return PurchaseOrderItemsCompanion(
          id: Value(_uuid.v4()),
          purchaseOrderId: Value(orderId),
          productId: Value(productId),
          productName: Value(item.description),
          quantity: Value(item.quantity),
          unitCost: Value(item.costPrice),
          total: Value(item.subtotal),
          receivedQuantity: Value(item.quantity),
        );
      }).toList(),
    );

    return orderId;
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

  XmlElement? _xmlChild(XmlElement parent, String name) {
    for (final child in parent.childElements) {
      if (child.localName.toLowerCase() == name.toLowerCase()) return child;
    }
    return null;
  }

  String? _xmlText(XmlElement parent, String name) {
    final child = _xmlChild(parent, name);
    final text = child?.innerText.trim();
    return (text != null && text.isNotEmpty) ? text : null;
  }

  String? _xmlTextDeep(XmlElement root, List<String> names) {
    for (final name in names) {
      final found = root.findAllElements(name).firstOrNull ??
          root.findAllElements(name.toLowerCase()).firstOrNull;
      if (found != null) {
        final text = found.innerText.trim();
        if (text.isNotEmpty) return text;
      }
    }
    // Also check child elements recursively
    for (final child in root.childElements) {
      if (names.any((n) => child.localName.toLowerCase() == n.toLowerCase())) {
        final text = child.innerText.trim();
        if (text.isNotEmpty) return text;
      }
      for (final grandchild in child.childElements) {
        if (names.any((n) => grandchild.localName.toLowerCase() == n.toLowerCase())) {
          final text = grandchild.innerText.trim();
          if (text.isNotEmpty) return text;
        }
      }
    }
    return null;
  }

  XmlElement? _findElementDeep(XmlElement root, List<String> names) {
    for (final name in names) {
      final found = root.findAllElements(name).firstOrNull;
      if (found != null) return found;
    }
    for (final child in root.childElements) {
      if (names.any((n) => child.localName.toLowerCase() == n.toLowerCase())) {
        return child;
      }
    }
    return null;
  }

  /// Busca un valor en el XML por contexto: recorre todos los nodos buscando
  /// etiquetas cuyo nombre (lowercase, sin separadores) coincida con alguno de los candidates.
  String? _findByContext(XmlElement root, List<String> candidates) {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[_\-\s]'), '');

    String? search(XmlElement el) {
      // Check attributes
      for (final attr in el.attributes) {
        if (candidates.any((c) => norm(attr.localName) == norm(c))) {
          final val = attr.value.trim();
          if (val.isNotEmpty) return val;
        }
      }
      // Check child elements
      for (final child in el.childElements) {
        if (candidates.any((c) => norm(child.localName) == norm(c))) {
          final text = child.innerText.trim();
          if (text.isNotEmpty && text.length < 500) return text;
        }
        final deeper = search(child);
        if (deeper != null) return deeper;
      }
      return null;
    }

    return search(root);
  }

  double? _numFromXml(XmlElement parent, String name) {
    final text = _xmlText(parent, name);
    if (text == null) return null;
    return double.tryParse(text.replaceAll(',', '.').replaceAll('\$', '').trim());
  }

  double? _numField(XmlElement parent, List<String> names) {
    for (final name in names) {
      final el = parent.findAllElements(name).firstOrNull;
      if (el != null) {
        final text = el.innerText.trim();
        if (text.isNotEmpty) {
          return double.tryParse(text.replaceAll(',', '.').replaceAll('\$', '').trim());
        }
      }
    }
    return null;
  }
}

// ══════════════════════════════════════════════════════════════
// ── DATA MODELS ──
// ══════════════════════════════════════════════════════════════

enum PreviewStatus { ready, readyWithWarnings, duplicate, error }
enum DbMatchStatus { unknown, exists, willCreate }

class InvoicePreview {
  final InvoiceHeader header;
  final SupplierPreview supplier;
  final ClientPreview client;
  final List<InvoiceItemPreview> items;
  final InvoiceTotals totals;
  final List<String> warnings;
  final bool isDuplicate;
  final PreviewStatus status;

  InvoicePreview({
    required this.header,
    required this.supplier,
    required this.client,
    required this.items,
    required this.totals,
    this.warnings = const [],
    this.isDuplicate = false,
    this.status = PreviewStatus.ready,
  });

  int get newProducts => items.where((i) => i.dbStatus == DbMatchStatus.willCreate).length;
  int get existingProducts => items.where((i) => i.dbStatus == DbMatchStatus.exists).length;
}

class InvoiceHeader {
  String? invoiceNumber;
  String? issueDate;
  String? invoiceType;
  String? accessKey;
  String? detectedFormat;
  String? fileName;
}

class SupplierPreview {
  String? name;
  String? ruc;
  String? commercialName;
  String? address;
  String? phone;
  String? email;
  DbMatchStatus dbStatus = DbMatchStatus.unknown;
  String? existingId;
}

class ClientPreview {
  String? name;
  String? identification;
  String? address;
}

class InvoiceItemPreview {
  final int index;
  final String? code;
  final String? auxCode;
  final String description;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double taxAmount;
  final double taxPercent;
  final double subtotal;
  final double total;
  final String? unit;
  final double costPrice;

  // ── Pharmacy-specific fields (AI-extracted) ──
  String? genericName;       // Nombre genérico (ej: Amoxicilina)
  String? presentation;      // Presentación (tableta, jarabe, crema, cápsula, ampolla)
  String? concentration;     // Concentración (500mg, 10ml, 0.5%)
  String? laboratory;        // Laboratorio fabricante
  String? registroSanitario; // Registro sanitario
  String? adminRoute;        // Vía administración (Oral, Tópica, IV, IM)
  String? batchNumber;       // Número de lote
  String? expirationDate;    // Fecha de vencimiento
  bool? requiresPrescription; // Requiere receta
  bool? isControlled;        // Sustancia controlada
  bool? isTaxExempt;         // Exento de IVA (medicinas en Ecuador)
  double? detectedTaxRate;   // Tasa IVA detectada (0%, 15%)
  int? unitsPerBox;          // Unidades por caja/empaque
  double? costPerBox;        // Costo total de la caja
  String? saleType;          // Tipo de venta (Unidad/Pieza, Caja)
  String? storageCondition;  // Condición de almacenamiento

  // DB status — filled by _enrichWithDbStatus
  DbMatchStatus dbStatus = DbMatchStatus.unknown;
  String? existingProductId;
  String? existingProductName;
  double currentStock = 0;

  InvoiceItemPreview({
    required this.index,
    this.code,
    this.auxCode,
    required this.description,
    this.quantity = 0,
    this.unitPrice = 0,
    this.discount = 0,
    this.taxAmount = 0,
    this.taxPercent = 0,
    this.subtotal = 0,
    this.total = 0,
    this.unit,
    this.costPrice = 0,
    this.genericName,
    this.presentation,
    this.concentration,
    this.laboratory,
    this.registroSanitario,
    this.adminRoute,
    this.batchNumber,
    this.expirationDate,
    this.requiresPrescription,
    this.isControlled,
    this.isTaxExempt,
    this.detectedTaxRate,
    this.unitsPerBox,
    this.costPerBox,
    this.saleType,
    this.storageCondition,
  });
}

class InvoiceTotals {
  // From XML
  double? xmlSubtotal;
  double? xmlTax;
  double? xmlDiscount;
  double? xmlTotal;

  // Calculated from items
  double calculatedSubtotal = 0;
  double calculatedTax = 0;
  double calculatedDiscount = 0;
  double calculatedTotal = 0;

  bool? totalsMatch;

  double get subtotal => xmlSubtotal ?? calculatedSubtotal;
  double get tax => xmlTax ?? calculatedTax;
  double get discount => xmlDiscount ?? calculatedDiscount;
  double get total => xmlTotal ?? calculatedTotal;
}

class ImportConfirmResult {
  final int imported;
  final int updated;
  final int batches;
  final List<String> errors;
  final bool supplierCreated;
  final String? supplierName;
  final String? invoiceNumber;
  final String? purchaseOrderId;

  ImportConfirmResult({
    this.imported = 0,
    this.updated = 0,
    this.batches = 0,
    this.errors = const [],
    this.supplierCreated = false,
    this.supplierName,
    this.invoiceNumber,
    this.purchaseOrderId,
  });

  bool get hasErrors => errors.isNotEmpty;
  int get totalProducts => imported + updated;
}
