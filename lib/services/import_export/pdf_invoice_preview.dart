import 'dart:typed_data';

import 'package:drift/drift.dart' hide Column;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/app_database.dart';
import '../ai/gemini_service.dart';
import '../secure_config_service.dart';
import 'xml_invoice_preview.dart';

// ══════════════════════════════════════════════════════════════
// ── PDF INVOICE PREVIEW SERVICE ──
// ══════════════════════════════════════════════════════════════
/// Parses PDF invoices using:
///   1. Syncfusion text extraction
///   2. Gemini AI analysis (if API key configured)
///   3. Local regex/pharma NLP fallback
/// Produces the same InvoicePreview model used by XML parser.
class PdfInvoicePreviewService {
  final AppDatabase _db;
  final _uuid = const Uuid();

  PdfInvoicePreviewService(this._db);

  // ══════════════════════════════════════════════════════════════
  // ── MAIN: Parse PDF → InvoicePreview ──
  // ══════════════════════════════════════════════════════════════
  Future<InvoicePreview> parsePdf(Uint8List bytes, {String? fileName}) async {
    final warnings = <String>[];

    try {
      // 1. Extract raw text from PDF
      final rawText = _extractText(bytes);
      if (rawText.trim().isEmpty) {
        return _errorPreview('El PDF no contiene texto seleccionable. Usa un PDF con texto, no imagen.', fileName);
      }

      // 2. Try Gemini AI analysis first (if key exists)
      final hasKey = await SecureConfigService.instance.hasGeminiKey;
      print('[PDF Parser] hasKey=$hasKey, textLength=${rawText.length}');

      InvoiceHeader header;
      SupplierPreview supplier;
      ClientPreview client;
      List<InvoiceItemPreview> items;

      if (hasKey) {
        try {
          final result = await _parseWithGemini(rawText, fileName: fileName);
          if (result != null) {
            header = result.$1;
            supplier = result.$2;
            client = result.$3;
            items = result.$4;
            if (result.$5.isNotEmpty) warnings.addAll(result.$5);
            warnings.add('✨ Analizado con Gemini AI');
          } else {
            warnings.add('⚠️ Gemini no pudo procesar — usando análisis local');
            final local = _parseLocally(rawText, fileName: fileName);
            header = local.$1;
            supplier = local.$2;
            client = local.$3;
            items = local.$4;
            if (local.$5.isNotEmpty) warnings.addAll(local.$5);
          }
        } catch (e, stack) {
          print('[PDF Parser] Gemini EXCEPTION: $e\n$stack');
          warnings.add('⚠️ Error Gemini: $e — usando análisis local');
          final local = _parseLocally(rawText, fileName: fileName);
          header = local.$1;
          supplier = local.$2;
          client = local.$3;
          items = local.$4;
          if (local.$5.isNotEmpty) warnings.addAll(local.$5);
        }
      } else {
        // Local-only mode
        final local = _parseLocally(rawText, fileName: fileName);
        header = local.$1;
        supplier = local.$2;
        client = local.$3;
        items = local.$4;
        if (local.$5.isNotEmpty) warnings.addAll(local.$5);
        if (!hasKey) {
          warnings.add('💡 Configura Gemini AI en Ajustes para análisis farmacéutico avanzado');
        }
      }

      header.fileName = fileName;

      if (items.isEmpty) {
        return InvoicePreview(
          header: header,
          supplier: supplier,
          client: client,
          items: [],
          totals: InvoiceTotals(),
          warnings: [...warnings, 'No se encontraron productos en el PDF.'],
          status: PreviewStatus.error,
        );
      }

      // 3. Calculate totals
      final totals = _calculateTotals(items);

      // 4. Enrich with DB status
      await _enrichWithDbStatus(items, supplier);

      // 5. Check duplicate
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
            : (warnings.where((w) => w.startsWith('⚠')).isEmpty
                ? PreviewStatus.ready
                : PreviewStatus.readyWithWarnings),
      );
    } catch (e) {
      return _errorPreview('Error al procesar PDF: $e', fileName);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── CONFIRM IMPORT (delegates to same logic as XML) ──
  // ══════════════════════════════════════════════════════════════
  Future<ImportConfirmResult> confirmImport(InvoicePreview preview) async {
    final errors = <String>[];
    var imported = 0;
    var updated = 0;
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
        } catch (e) {
          errors.add('Producto ${i + 1} (${preview.items[i].description}): $e');
        }
      }

      // 3. Create purchase order
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
        errors: errors,
        supplierCreated: preview.supplier.dbStatus == DbMatchStatus.willCreate,
        supplierName: preview.supplier.name,
        invoiceNumber: preview.header.invoiceNumber,
        purchaseOrderId: purchaseOrderId,
      );
    } catch (e) {
      errors.add('Error general: $e');
      return ImportConfirmResult(imported: imported, updated: updated, errors: errors);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── TEXT EXTRACTION (Syncfusion) ──
  // ══════════════════════════════════════════════════════════════
  String _extractText(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    final buffer = StringBuffer();
    for (var i = 0; i < document.pages.count; i++) {
      final text = PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i);
      buffer.writeln(text);
    }
    document.dispose();
    return buffer.toString();
  }

  // ══════════════════════════════════════════════════════════════
  // ── GEMINI AI PARSING ──
  // ══════════════════════════════════════════════════════════════
  Future<(InvoiceHeader, SupplierPreview, ClientPreview, List<InvoiceItemPreview>, List<String>)?> _parseWithGemini(
    String rawText, {
    String? fileName,
  }) async {
    final gemini = GeminiService.instance;
    final warnings = <String>[];

    // Extract header info
    final headerData = await gemini.analyzeInvoiceHeader(rawText);
    final header = InvoiceHeader();
    final supplier = SupplierPreview();
    final client = ClientPreview();

    if (headerData != null) {
      header.invoiceNumber = headerData['invoiceNumber'] as String?;
      header.issueDate = headerData['issueDate'] as String?;
      header.invoiceType = headerData['invoiceType'] as String?;
      header.accessKey = headerData['accessKey'] as String?;
      header.detectedFormat = 'PDF-AI';

      supplier.name = headerData['supplierName'] as String?;
      supplier.ruc = headerData['supplierRuc'] as String?;
      supplier.commercialName = headerData['supplierCommercialName'] as String?;
      supplier.address = headerData['supplierAddress'] as String?;
      supplier.phone = headerData['supplierPhone'] as String?;

      client.name = headerData['clientName'] as String?;
      client.identification = headerData['clientId'] as String?;
    } else {
      header.detectedFormat = 'PDF-AI';
      warnings.add('No se pudo extraer encabezado con AI');
      // Fallback to local header extraction
      _extractHeaderLocally(rawText, header, supplier, client);
    }

    // Extract products
    final productsData = await gemini.analyzeInvoiceText(
      rawText,
      supplierName: supplier.name,
    );

    print('[PDF Parser] Gemini products: ${productsData?.length ?? 'null'}');
    if (productsData == null || productsData.isEmpty) return null;

    final items = <InvoiceItemPreview>[];
    for (var i = 0; i < productsData.length; i++) {
      try {
        items.add(_mapGeminiProduct(productsData[i], i));
      } catch (e) {
        warnings.add('Producto ${i + 1}: error mapping AI data');
      }
    }

    if (items.isEmpty) return null;

    return (header, supplier, client, items, warnings);
  }

  InvoiceItemPreview _mapGeminiProduct(Map<String, dynamic> data, int index) {
    double toDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.').replaceAll('\$', '')) ?? 0;
      return 0;
    }

    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    bool? toBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true' || v == '1' || v.toLowerCase() == 'sí';
      return null;
    }

    final unitPrice = toDouble(data['unitPrice']);
    final quantity = toDouble(data['quantity']);
    final discount = toDouble(data['discount']);
    final taxAmount = toDouble(data['taxAmount']);
    final costPrice = toDouble(data['costPrice']);
    final subtotalVal = toDouble(data['subtotal']);
    final subtotal = subtotalVal > 0 ? subtotalVal : (quantity * unitPrice - discount);

    return InvoiceItemPreview(
      index: index,
      code: data['code'] as String?,
      auxCode: data['auxCode'] as String?,
      description: (data['description'] as String?) ?? 'Producto ${index + 1}',
      quantity: quantity,
      unitPrice: unitPrice,
      discount: discount,
      taxAmount: taxAmount,
      taxPercent: toDouble(data['taxPercent']),
      subtotal: subtotal,
      total: toDouble(data['total']),
      unit: data['unit'] as String?,
      costPrice: costPrice > 0 ? costPrice : unitPrice,
      genericName: data['genericName'] as String?,
      presentation: data['presentation'] as String?,
      concentration: data['concentration'] as String?,
      laboratory: data['laboratory'] as String?,
      registroSanitario: data['registroSanitario'] as String?,
      adminRoute: data['adminRoute'] as String?,
      batchNumber: data['batchNumber'] as String?,
      expirationDate: data['expirationDate'] as String?,
      requiresPrescription: toBool(data['requiresPrescription']),
      isControlled: toBool(data['isControlled']),
      isTaxExempt: toBool(data['isTaxExempt']),
      detectedTaxRate: toDouble(data['detectedTaxRate']),
      unitsPerBox: toInt(data['unitsPerBox']),
      costPerBox: toDouble(data['costPerBox']),
      saleType: data['saleType'] as String? ?? 'Unidad/Pieza',
      storageCondition: data['storageCondition'] as String?,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── LOCAL PARSING (fallback) ──
  // ══════════════════════════════════════════════════════════════
  (InvoiceHeader, SupplierPreview, ClientPreview, List<InvoiceItemPreview>, List<String>) _parseLocally(
    String rawText, {
    String? fileName,
  }) {
    final warnings = <String>[];
    final header = InvoiceHeader()..detectedFormat = 'PDF-Local';
    final supplier = SupplierPreview();
    final client = ClientPreview();

    _extractHeaderLocally(rawText, header, supplier, client);

    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final items = <InvoiceItemPreview>[];

    // Find the product table zone — look for header row markers
    int tableStart = -1;
    int tableEnd = lines.length;

    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      // Detect product table header
      if ((lower.contains('descripci') || lower.contains('detalle') || lower.contains('producto')) &&
          (lower.contains('cant') || lower.contains('precio') || lower.contains('valor'))) {
        tableStart = i + 1;
      }
      // Detect end of table
      if (tableStart > 0 && i > tableStart) {
        if (lower.contains('subtotal') && !lower.contains('sin') ||
            lower.contains('total factura') ||
            lower.contains('información adicional') ||
            lower.contains('forma de pago')) {
          tableEnd = i;
          break;
        }
      }
    }

    // Strategy 1: Parse product table zone
    if (tableStart > 0) {
      for (var i = tableStart; i < tableEnd; i++) {
        final item = _tryParseProductLine(lines[i], items.length, lines, i);
        if (item != null) {
          _enrichWithPharmaData(item);
          items.add(item);
        }
      }
    }

    // Strategy 2: If no table zone found, scan all lines
    if (items.isEmpty) {
      for (var i = 0; i < lines.length; i++) {
        final item = _tryParseProductLine(lines[i], items.length, lines, i);
        if (item != null) {
          _enrichWithPharmaData(item);
          items.add(item);
        }
      }
    }

    // Strategy 3: Multi-line grouping — some PDFs split product across lines
    if (items.isEmpty) {
      final multiItems = _tryMultiLineParsing(lines, tableStart > 0 ? tableStart : 0, tableEnd);
      for (final item in multiItems) {
        _enrichWithPharmaData(item);
        items.add(item);
      }
    }

    // Strategy 4: RIDE jumbled text — find product descriptions in mixed columns
    if (items.isEmpty) {
      final rideItems = _parseRideFormat(lines, tableStart > 0 ? tableStart : 0, tableEnd);
      for (final item in rideItems) {
        _enrichWithPharmaData(item);
        items.add(item);
      }
    }

    if (items.isEmpty) {
      warnings.add('Análisis local no encontró productos — se recomienda activar Gemini AI');
    }

    return (header, supplier, client, items, warnings);
  }

  /// Checks if a line is a RIDE header/label (not product data)
  bool _isRideLabel(String line) {
    final lower = line.toLowerCase().trim();
    const labels = [
      'factura', 'fecha', 'r.u.c', 'ruc:', 'clave', 'acceso', 'autorización',
      'autorizacion', 'identificación', 'identificacion', 'comprobante', 'sri',
      'ride', 'ambiente', 'emisión', 'emision', 'obligado', 'contabilidad',
      'dirección', 'direccion', 'matriz', 'sucursal', 'agente', 'retención',
      'resolución', 'número', 'normal', 'producción', 'produccion', 'guía',
      'guia', 'placa', 'matrícula', 'matricula', 'teléfono', 'telefono',
      'email', 'elaborado', 'forma de pago', 'información adicional',
      'nombres y apellidos', 'cod.', 'cantidad', 'descripción', 'precio',
      'subsidio', 'descuento', 'detalle adicional', 'valor',
    ];
    return labels.any((l) => lower.contains(l));
  }

  void _extractHeaderLocally(
    String text,
    InvoiceHeader header,
    SupplierPreview supplier,
    ClientPreview client,
  ) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // 1. Invoice number (SRI format: 001-001-000000001)
    final invMatch = RegExp(r'(\d{3}-\d{3}-\d{9})').firstMatch(text);
    if (invMatch != null) {
      header.invoiceNumber = invMatch.group(1);
    }

    // 2. Access key (49 digits)
    final keyMatch = RegExp(r'(\d{49})').firstMatch(text);
    if (keyMatch != null) {
      header.accessKey = keyMatch.group(1);
    }

    // 3. Date — look for labeled date first, then standalone DD/MM/YYYY
    final dateLabeled = RegExp(
      r'(?:fecha[^:]*)[:\s]+(\d{1,2}/\d{1,2}/\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (dateLabeled != null) {
      header.issueDate = dateLabeled.group(1);
    } else {
      final dateMatch = RegExp(r'(\d{2}/\d{2}/\d{4})').firstMatch(text);
      if (dateMatch != null) {
        header.issueDate = dateMatch.group(1);
      }
    }

    // 4. RUC — find 13-digit number that is NOT part of the 49-digit access key
    //    In Ecuador, RUC is 13 digits, access key is 49 digits
    for (final line in lines) {
      final m = RegExp(r'(?<!\d)(\d{13})(?!\d)').firstMatch(line);
      if (m != null) {
        final candidate = m.group(1)!;
        // Skip if this is part of the access key
        if (header.accessKey != null && header.accessKey!.contains(candidate)) continue;
        supplier.ruc = candidate;
        break;
      }
    }
    // Also try labeled RUC (R.U.C.: 0602570863001)
    if (supplier.ruc == null) {
      final rucMatch = RegExp(r'R\.?U\.?C\.?[:\s]+(\d{10,13})', caseSensitive: false).firstMatch(text);
      if (rucMatch != null) {
        supplier.ruc = rucMatch.group(1);
      }
    }

    // 5. Supplier name — in RIDE format, appears right AFTER the RUC line
    //    The extracted text typically has: ...RUC_NUMBER\nSUPPLIER_NAME\nADDRESS...
    if (supplier.ruc != null) {
      var foundRuc = false;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains(supplier.ruc!)) {
          foundRuc = true;
          continue;
        }
        if (foundRuc) {
          final line = lines[i];
          // Supplier name: has uppercase letters, doesn't start with digit, not a label
          if (line.isNotEmpty &&
              line.length > 3 &&
              line.length < 120 &&
              RegExp(r'[A-ZÁÉÍÓÚÑ]{2,}').hasMatch(line) &&
              !RegExp(r'^\d').hasMatch(line) &&
              !_isRideLabel(line)) {
            supplier.name = line;

            // Next line(s) for address
            for (var j = i + 1; j < lines.length && j < i + 4; j++) {
              final addrLine = lines[j];
              if (addrLine.isNotEmpty &&
                  addrLine.length > 5 &&
                  !_isRideLabel(addrLine) &&
                  !RegExp(r'^(SI|NO)$', caseSensitive: false).hasMatch(addrLine)) {
                supplier.address ??= addrLine;
              } else {
                break;
              }
            }
            break;
          }
        }
      }
    }

    // 6. Commercial name — in RIDE, appears after "PRODUCCIÓN" or "PRUEBAS"
    //    Example text: "PRODUCCIÓN COFARI" → commercial name = "COFARI"
    final prodMatch = RegExp(
      r'(?:PRODUCCI[OÓ]N|PRUEBAS)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (prodMatch != null) {
      final cn = prodMatch.group(1)!.trim();
      if (cn.isNotEmpty && cn.length < 60 && !_isRideLabel(cn)) {
        supplier.commercialName = cn;
      }
    }

    // 7. If no supplier found from RUC-based search, try labeled "Nombre Comercial"
    if (supplier.commercialName == null) {
      final comercialMatch = RegExp(
        r'(?:nombre\s*comercial)[:\s]*(.+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (comercialMatch != null) {
        final cn = comercialMatch.group(1)!.trim().split('\n').first.trim();
        if (cn.isNotEmpty && cn.length > 2 && cn.length < 100) {
          supplier.commercialName = cn;
        }
      }
    }

    // 8. Supplier address from labeled field (fallback)
    if (supplier.address == null) {
      final addrMatch = RegExp(
        r'(?:direcci[oó]n\s*(?:matriz|sucursal)?)[:\s]*(.{10,})',
        caseSensitive: false,
      ).firstMatch(text);
      if (addrMatch != null) {
        supplier.address = addrMatch.group(1)!.trim().split('\n').first.trim();
      }
    }

    // 9. Client — in RIDE, "Razón Social / Nombres y Apellidos:" is the CLIENT label
    //    The actual client name is on a SUBSEQUENT line (not the same line)
    for (var i = 0; i < lines.length; i++) {
      if (RegExp(r'raz[oó]n\s*social.*nombres.*apellidos', caseSensitive: false).hasMatch(lines[i]) ||
          RegExp(r'raz[oó]n\s*social.*comprador', caseSensitive: false).hasMatch(lines[i])) {
        // Look at following lines for the actual client name
        for (var j = i + 1; j < lines.length && j < i + 6; j++) {
          final line = lines[j];
          if (line.isNotEmpty &&
              line.length > 3 &&
              RegExp(r'[A-ZÁÉÍÓÚÑ]{2,}\s+[A-ZÁÉÍÓÚÑ]').hasMatch(line) &&
              !RegExp(r'^\d').hasMatch(line) &&
              !_isRideLabel(line)) {
            client.name = line;
            break;
          }
        }
        break;
      }
    }

    // 10. Client identification — 10-13 digits after client name or "Identificación" label
    if (client.name != null) {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i] == client.name && i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          final m = RegExp(r'^(\d{10,13})$').firstMatch(nextLine);
          if (m != null) {
            client.identification = m.group(1);
          }
          break;
        }
      }
    }
    if (client.identification == null) {
      final idMatch = RegExp(
        r'(?:identificaci[oó]n)[:\s]*(\d{10,13})',
        caseSensitive: false,
      ).firstMatch(text);
      if (idMatch != null) {
        client.identification = idMatch.group(1);
      }
    }

    print('[PDF Parser] Header: inv=${header.invoiceNumber}, ruc=${supplier.ruc}, '
        'supplier=${supplier.name}, commercial=${supplier.commercialName}, '
        'client=${client.name}, clientId=${client.identification}');
  }

  InvoiceItemPreview? _tryParseProductLine(String line, int index, List<String> allLines, int lineIndex) {
    if (line.length < 10) return null;

    final lower = line.toLowerCase();
    // Skip header/footer/summary lines
    const skipPatterns = [
      'subtotal', 'total sin', 'total con', 'total factura', 'descuento',
      'iva', 'fecha', 'factura', 'código', 'cantidad', 'precio unitario',
      'descripción', 'información adicional', 'forma de pago', 'clave de acceso',
      'autorización', 'ambiente', 'emisión', 'razón social', 'ruc:', 'dirección',
      'obligado a llevar', 'contribuyente', 'página', 'comprobante',
      'teléfono', 'telefono', 'email', 'elaborado por', 'sri ::', 'declare',
      'placa', 'matrícula', 'matricula', 'agente de retención', 'resolución',
      'impuesto a la renta', 'propina', 'irbpnr', 'ice', 'valor total',
      'ahorro por subsidio', 'incluye iva', 'precio sin', 'cod.principal',
      'cod.auxiliar', 'detalle adicional', 'precio total', 'no objeto',
      'exento de iva', 'sin impuestos', 'producción', 'direccion:',
    ];
    for (final skip in skipPatterns) {
      if (lower.contains(skip)) return null;
    }

    // Extract all decimal numbers from the line
    final allNums = RegExp(r'(\d+(?:[.,]\d+)?)').allMatches(line).toList();
    if (allNums.length < 2) return null;

    // Parse all numbers
    final numericValues = <(double, int, int)>[]; // value, start, end
    for (final m in allNums) {
      final raw = m.group(1)!.replaceAll(',', '.');
      final val = double.tryParse(raw);
      if (val != null) {
        numericValues.add((val, m.start, m.end));
      }
    }

    if (numericValues.length < 2) return null;

    // Heuristic: The rightmost numbers are financial (subtotal, tax, price)
    // and a quantity is usually a small integer or decimal

    String? code;
    String description;
    double quantity = 0;
    double unitPrice = 0;
    double discount = 0;
    double taxAmount = 0;
    double subtotal = 0;

    // Check if line starts with a product code
    final codeMatch = RegExp(r'^([A-Za-z0-9]{2,20})\s+').firstMatch(line);
    int descStart = 0;
    if (codeMatch != null) {
      final potentialCode = codeMatch.group(1)!;
      // Ensure it's not just a number that's part of the data
      if (!RegExp(r'^\d+[.,]\d+$').hasMatch(potentialCode)) {
        code = potentialCode;
        descStart = codeMatch.end;
      }
    }

    // Find where the text description ends — last alphabetic segment before numeric columns
    int textEndPos = 0;
    for (var i = numericValues.length - 1; i >= 0; i--) {
      final beforeNum = line.substring(0, numericValues[i].$2).trimRight();
      // Check if there's text (letters) right before this number
      if (RegExp(r'[a-zA-ZáéíóúñÁÉÍÓÚÑ]').hasMatch(beforeNum)) {
        textEndPos = numericValues[i].$2;
        break;
      }
    }
    // If we didn't find a good split, use first number position
    if (textEndPos == 0 && numericValues.isNotEmpty) {
      textEndPos = numericValues.first.$2;
    }

    description = line.substring(descStart, textEndPos).trim();
    // Remove trailing spaces and common separators
    description = description.replaceAll(RegExp(r'[\s]+$'), '').trim();
    if (description.isEmpty) return null;
    if (description.length < 3) return null;

    // Get the rightmost numeric values (these are the financial columns)
    final financialNums = <double>[];
    for (final nv in numericValues) {
      if (nv.$2 >= textEndPos) {
        financialNums.add(nv.$1);
      }
    }

    if (financialNums.isEmpty) return null;

    // Assign based on column count — Ecuadorian RIDE typically has:
    // Cant. | Precio Unit. | Descuento | Precio Total
    // Or: Cant. | Precio Unit. | Precio Total
    // Or lines with: code desc qty price discount tax subtotal
    if (financialNums.length >= 6) {
      quantity = financialNums[0];
      unitPrice = financialNums[1];
      discount = financialNums[2];
      taxAmount = financialNums[3];
      // financialNums[4] could be tax percent
      subtotal = financialNums[financialNums.length - 1];
    } else if (financialNums.length >= 5) {
      quantity = financialNums[0];
      unitPrice = financialNums[1];
      discount = financialNums[2];
      taxAmount = financialNums[3];
      subtotal = financialNums[4];
    } else if (financialNums.length >= 4) {
      quantity = financialNums[0];
      unitPrice = financialNums[1];
      discount = financialNums[2];
      subtotal = financialNums[3];
    } else if (financialNums.length >= 3) {
      quantity = financialNums[0];
      unitPrice = financialNums[1];
      subtotal = financialNums[2];
    } else if (financialNums.length >= 2) {
      // Could be qty+price or price+total
      if (financialNums[0] <= 1000 && financialNums[1] > financialNums[0]) {
        quantity = financialNums[0];
        unitPrice = financialNums[1];
        subtotal = quantity * unitPrice;
      } else {
        unitPrice = financialNums[0];
        subtotal = financialNums[1];
        quantity = unitPrice > 0 ? subtotal / unitPrice : 1;
      }
    }

    // Sanity checks
    if (quantity <= 0) quantity = 1;
    if (quantity > 99999) return null;
    if (unitPrice <= 0 && subtotal <= 0) return null;
    if (unitPrice > 999999 || subtotal > 999999) return null;

    // Infer missing values
    if (unitPrice <= 0 && subtotal > 0 && quantity > 0) {
      unitPrice = subtotal / quantity;
    }
    if (subtotal <= 0 && unitPrice > 0) {
      subtotal = quantity * unitPrice - discount;
    }

    final costPrice = unitPrice > 0
        ? unitPrice - (quantity > 0 && discount > 0 ? discount / quantity : 0)
        : subtotal / (quantity > 0 ? quantity : 1);

    return InvoiceItemPreview(
      index: index,
      code: code,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      discount: discount,
      taxAmount: taxAmount,
      taxPercent: subtotal > 0 && taxAmount > 0 ? (taxAmount / subtotal * 100) : 0,
      subtotal: subtotal > 0 ? subtotal : quantity * costPrice,
      total: subtotal + taxAmount - discount,
      costPrice: costPrice > 0 ? costPrice : unitPrice,
    );
  }

  /// Multi-line parsing: some PDFs put description on one line, numbers on next
  List<InvoiceItemPreview> _tryMultiLineParsing(List<String> lines, int start, int end) {
    final items = <InvoiceItemPreview>[];
    var i = start;

    while (i < end - 1) {
      final line = lines[i];
      final nextLine = i + 1 < end ? lines[i + 1] : '';

      // Current line is mostly text (description), next line is mostly numbers
      final hasText = RegExp(r'[a-zA-ZáéíóúñÁÉÍÓÚÑ]{3,}').hasMatch(line);
      final nextNums = RegExp(r'(\d+[.,]?\d*)').allMatches(nextLine).toList();
      final nextHasMainlyNumbers = nextNums.length >= 2 &&
          nextLine.replaceAll(RegExp(r'[\d.,\s\$]'), '').length < nextLine.length * 0.3;

      if (hasText && nextHasMainlyNumbers) {
        // Extract code from beginning of description line
        String? code;
        String description = line.trim();
        final codeMatch = RegExp(r'^([A-Za-z0-9]{3,15})\s+(.+)').firstMatch(description);
        if (codeMatch != null) {
          code = codeMatch.group(1);
          description = codeMatch.group(2)!.trim();
        }

        // Parse numbers from next line
        final values = <double>[];
        for (final m in nextNums) {
          final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
          if (v != null) values.add(v);
        }

        if (values.length >= 2 && description.length >= 3) {
          double quantity, unitPrice, discount = 0, subtotal = 0;

          if (values.length >= 4) {
            quantity = values[0];
            unitPrice = values[1];
            discount = values[2];
            subtotal = values[3];
          } else if (values.length >= 3) {
            quantity = values[0];
            unitPrice = values[1];
            subtotal = values[2];
          } else {
            quantity = values[0];
            unitPrice = values[1];
            subtotal = quantity * unitPrice;
          }

          if (quantity > 0 && quantity < 100000 && unitPrice > 0) {
            final costPrice = unitPrice - (quantity > 0 && discount > 0 ? discount / quantity : 0);
            items.add(InvoiceItemPreview(
              index: items.length,
              code: code,
              description: description,
              quantity: quantity,
              unitPrice: unitPrice,
              discount: discount,
              subtotal: subtotal > 0 ? subtotal : quantity * costPrice,
              total: subtotal,
              costPrice: costPrice > 0 ? costPrice : unitPrice,
            ));
            i += 2; // Skip both lines
            continue;
          }
        }
      }
      i++;
    }

    return items;
  }

  // ══════════════════════════════════════════════════════════════
  // ── RIDE JUMBLED TEXT PARSER ──
  // ══════════════════════════════════════════════════════════════
  /// Parses Ecuadorian SRI RIDE invoices where Syncfusion text extraction
  /// produces jumbled multi-column text. Finds product descriptions
  /// (uppercase text sequences) and extracts surrounding numbers.
  ///
  /// RIDE tables produce lines like:
  ///   "7-16CO 3.95 1.42 LISTERINE ANTICARIES*180ML 2.00"
  /// where [price] [discount] [DESCRIPTION] [quantity] are on same line.
  List<InvoiceItemPreview> _parseRideFormat(List<String> lines, int start, int end) {
    final items = <InvoiceItemPreview>[];

    // Skip labels in RIDE format
    const skipWords = {
      'SUBTOTAL', 'TOTAL', 'IVA', 'DESCUENTO', 'ICE', 'IRBPNR', 'PROPINA',
      'FORMA', 'VALOR', 'INFORMACIÓN', 'ADICIONAL', 'DIRECCIÓN', 'DIRECCION',
      'TELÉFONO', 'TELEFONO', 'EMAIL', 'ELABORADO', 'PRODUCCIÓN', 'PRODUCCION',
      'EMISIÓN', 'EMISION', 'FACTURA', 'AMBIENTE', 'NORMAL', 'OBLIGADO',
      'DECLARE', 'AHORRO', 'SUBSIDIO', 'SRI', 'LATACUNGA', 'COD',
    };

    for (var i = start; i < end; i++) {
      final line = lines[i];
      if (line.length < 10) continue;

      // Find product description: uppercase text with 2+ words and ≥8 chars
      // Allows *, digits (for sizes like 180ML), hyphens, slashes
      final descMatches = RegExp(
        r'([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s\*\-/\.]+(?:\*?\d+[A-ZÁÉÍÓÚÑ]*)?)',
      ).allMatches(line);

      for (final dm in descMatches) {
        var desc = dm.group(1)!.trim();
        if (desc.length < 8) continue;

        // Must contain at least 2 words with ≥2 letters each
        final words = desc.split(RegExp(r'\s+'))
            .where((w) => RegExp(r'[A-ZÁÉÍÓÚÑ]{2,}').hasMatch(w))
            .toList();
        if (words.length < 2) continue;

        // Skip if first word is a known label
        if (skipWords.contains(words[0])) continue;

        // Extract decimal numbers (X.XX format) from same line
        final beforeDesc = line.substring(0, dm.start);
        final afterDesc = line.substring(dm.end);

        final numsBefore = RegExp(r'(\d+\.\d{1,2})')
            .allMatches(beforeDesc)
            .map((m) => double.parse(m.group(1)!))
            .where((v) => v > 0)
            .toList();

        final numsAfter = RegExp(r'(\d+\.\d{1,2})')
            .allMatches(afterDesc)
            .map((m) => double.parse(m.group(1)!))
            .where((v) => v > 0)
            .toList();

        // Also check for integer quantity after description (e.g., "PRODUCT 2")
        if (numsAfter.isEmpty) {
          final intMatch = RegExp(r'^\s*(\d{1,4})(?:\s|$)').firstMatch(afterDesc);
          if (intMatch != null) {
            numsAfter.add(double.parse(intMatch.group(1)!));
          }
        }

        if (numsBefore.isEmpty && numsAfter.isEmpty) continue;

        // RIDE pattern: [price] [discount] DESCRIPTION [quantity]
        double quantity = 1, unitPrice = 0, discount = 0;

        // Quantity: first number after description
        if (numsAfter.isNotEmpty) {
          quantity = numsAfter[0];
        }

        // Price and discount: last 2 decimals before description
        if (numsBefore.length >= 2) {
          unitPrice = numsBefore[numsBefore.length - 2];
          discount = numsBefore[numsBefore.length - 1];
        } else if (numsBefore.length == 1) {
          unitPrice = numsBefore[0];
        }

        // Validate reasonable values
        if (unitPrice <= 0 || unitPrice > 50000) continue;
        if (quantity <= 0 || quantity > 50000) continue;
        if (discount < 0 || discount >= quantity * unitPrice) {
          // discount can't be >= total, might be misidentified
          // Try swapping: maybe numsBefore has [discount, price] instead
          if (numsBefore.length >= 2 && numsBefore[numsBefore.length - 1] > numsBefore[numsBefore.length - 2]) {
            unitPrice = numsBefore[numsBefore.length - 1];
            discount = numsBefore[numsBefore.length - 2];
          } else {
            discount = 0;
          }
        }

        // Try to find product code from previous lines
        String? code;
        if (i > start) {
          final prevLine = lines[i - 1];
          // Look for alphanumeric codes like PR87991, 770203197
          final codeMatch = RegExp(r'([A-Z]{1,3}\d{3,10}|\d{6,13})').firstMatch(prevLine);
          if (codeMatch != null) {
            code = codeMatch.group(1);
          }
        }
        // Also check beginning of current line for code
        final lineCodeMatch = RegExp(r'^([A-Z]{1,3}\d{3,10})\s').firstMatch(line);
        if (lineCodeMatch != null) {
          code ??= lineCodeMatch.group(1);
        }

        // Try to find expiry date from next line
        String? expiryDate;
        if (i + 1 < end) {
          final nextLine = lines[i + 1];
          final expiryMatch = RegExp(r'(\d{2}/\d{2}/\d{4})').firstMatch(nextLine);
          if (expiryMatch != null) {
            expiryDate = expiryMatch.group(1);
          }
        }

        final subtotal = quantity * unitPrice;
        final total = subtotal - discount;
        final costPrice = unitPrice - (discount > 0 ? discount / quantity : 0);

        items.add(InvoiceItemPreview(
          index: items.length,
          code: code,
          description: desc,
          quantity: quantity,
          unitPrice: unitPrice,
          discount: discount,
          subtotal: subtotal,
          total: total,
          costPrice: costPrice > 0 ? costPrice : unitPrice,
          expirationDate: expiryDate,
        ));

        break; // One product per line at most
      }
    }

    print('[PDF Parser] RIDE format found ${items.length} products');
    return items;
  }

  // ══════════════════════════════════════════════════════════════
  // ── PHARMACEUTICAL INTELLIGENCE (local enrichment) ──
  // ══════════════════════════════════════════════════════════════
  void _enrichWithPharmaData(InvoiceItemPreview item) {
    final desc = item.description.toUpperCase();

    // Concentration extraction
    final concMatch = RegExp(
      r'(\d+(?:[,.]\d+)?)\s*(MG|G|ML|MCG|UG|UI|%|MG/ML|G/ML|MG/5ML|MG/DL)',
      caseSensitive: false,
    ).firstMatch(desc);
    if (concMatch != null) {
      item.concentration = '${concMatch.group(1)}${concMatch.group(2)!.toLowerCase()}';
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
    for (final entry in presentations.entries) {
      if (desc.contains(entry.key)) {
        item.presentation = entry.value;
        break;
      }
    }

    // Admin route from presentation
    if (item.presentation != null) {
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

    // Units per box
    final unitsMatch = RegExp(r'[Xx]\s*(\d+)\s*(?:UND|UNID|TAB|CAP|AMP|COMP)?', caseSensitive: false).firstMatch(desc);
    if (unitsMatch != null) {
      item.unitsPerBox = int.tryParse(unitsMatch.group(1)!);
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
    for (final lab in labs) {
      if (desc.contains(lab)) {
        item.laboratory = lab[0] + lab.substring(1).toLowerCase();
        break;
      }
    }

    // Known controlled substances
    const controlled = [
      'TRAMADOL', 'MORFINA', 'CODEINA', 'FENTANILO', 'DIAZEPAM',
      'CLONAZEPAM', 'ALPRAZOLAM', 'LORAZEPAM', 'MIDAZOLAM', 'FENOBARBITAL',
      'METILFENIDATO', 'OXICODONA', 'METADONA', 'ZOLPIDEM', 'PREGABALINA',
    ];
    for (final sub in controlled) {
      if (desc.contains(sub)) {
        item.isControlled = true;
        item.requiresPrescription = true;
        break;
      }
    }

    // Prescription medicines (not controlled but require prescription)
    const prescriptionRequired = [
      'ANTIBIOTICO', 'ANTIBIÓTICO', 'AMOXICILINA', 'AZITROMICINA',
      'CIPROFLOXACIN', 'METFORMINA', 'LOSARTAN', 'ENALAPRIL', 'ATORVASTATIN',
      'OMEPRAZOL', 'INSULINA', 'WARFARINA', 'PREDNISONA', 'DEXAMETASONA',
      'FLUOXETINA', 'SERTRALINA', 'LEVOTIROXINA',
    ];
    if (item.requiresPrescription != true) {
      for (final med in prescriptionRequired) {
        if (desc.contains(med)) {
          item.requiresPrescription = true;
          break;
        }
      }
    }

    // Tax detection — in Ecuador medicines for human use are IVA 0%
    if (item.taxAmount == 0 || item.taxPercent == 0) {
      item.isTaxExempt = true;
      item.detectedTaxRate = 0;
    } else {
      item.isTaxExempt = false;
      item.detectedTaxRate = item.taxPercent > 0 ? item.taxPercent : 15.0;
    }

    // Storage conditions
    const refrigeration = [
      'INSULINA', 'VACUNA', 'BIOLÓGICO', 'BIOLOGICO', 'REFRIGER',
    ];
    for (final kw in refrigeration) {
      if (desc.contains(kw)) {
        item.storageCondition = 'Refrigeración';
        break;
      }
    }
    item.storageCondition ??= 'Ambiente';

    // Sale type
    item.saleType ??= 'Unidad/Pieza';

    // Generic name extraction (first word that looks pharmaceutical)
    final words = item.description.split(RegExp(r'\s+'));
    if (words.isNotEmpty && words[0].length > 3) {
      item.genericName ??= words[0][0].toUpperCase() + words[0].substring(1).toLowerCase();
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ── TOTALS ──
  // ══════════════════════════════════════════════════════════════
  InvoiceTotals _calculateTotals(List<InvoiceItemPreview> items) {
    final t = InvoiceTotals();
    t.calculatedSubtotal = items.fold(0.0, (sum, i) => sum + i.subtotal);
    t.calculatedTax = items.fold(0.0, (sum, i) => sum + i.taxAmount);
    t.calculatedDiscount = items.fold(0.0, (sum, i) => sum + i.discount);
    t.calculatedTotal = t.calculatedSubtotal + t.calculatedTax - t.calculatedDiscount;
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
      if (item.code != null && item.code!.isNotEmpty) {
        final found = await dao.getProductByBarcode(item.code!);
        if (found != null) {
          item.dbStatus = DbMatchStatus.exists;
          item.existingProductId = found.id;
          item.existingProductName = found.name;
          item.currentStock = found.currentStock;
          continue;
        }
        final byInternal = await (_db.select(_db.products)
              ..where((p) => p.internalCode.equals(item.code!)))
            .getSingleOrNull();
        if (byInternal != null) {
          item.dbStatus = DbMatchStatus.exists;
          item.existingProductId = byInternal.id;
          item.existingProductName = byInternal.name;
          item.currentStock = byInternal.currentStock;
          continue;
        }
      }

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
    final orders = await _db.purchasesDao.getPurchaseOrders();
    return orders.any((o) =>
        o.orderNumber.toLowerCase().trim() == header.invoiceNumber!.toLowerCase().trim());
  }

  // ══════════════════════════════════════════════════════════════
  // ── FIND/CREATE SUPPLIER ──
  // ══════════════════════════════════════════════════════════════
  Future<String> _findOrCreateSupplier(SupplierPreview s) async {
    if (s.existingId != null) return s.existingId!;

    if (s.ruc != null && s.ruc!.isNotEmpty) {
      final existing = await (_db.select(_db.suppliers)
            ..where((sup) => sup.ruc.equals(s.ruc!)))
          .getSingleOrNull();
      if (existing != null) return existing.id;
    }

    final id = _uuid.v4();
    await _db.purchasesDao.insertSupplier(SuppliersCompanion(
      id: Value(id),
      name: Value(s.name ?? 'Proveedor PDF'),
      ruc: Value(s.ruc),
      address: Value(s.address),
      syncStatus: const Value('pending'),
    ));
    return id;
  }

  // ══════════════════════════════════════════════════════════════
  // ── UPSERT PRODUCT (with ALL pharmacy fields) ──
  // ══════════════════════════════════════════════════════════════
  Future<String> _upsertProduct(InvoiceItemPreview item, String? supplierId) async {
    final dao = _db.productsDao;

    if (item.existingProductId != null) {
      // UPDATE existing
      final existing = await (_db.select(_db.products)
            ..where((p) => p.id.equals(item.existingProductId!)))
          .getSingle();

      final newStock = existing.currentStock + item.quantity;
      await dao.updateProduct(ProductsCompanion(
        id: Value(existing.id),
        costPrice: Value(item.costPrice > 0 ? item.costPrice : existing.costPrice),
        salePrice: Value(item.costPrice > 0 ? item.costPrice * 1.30 : existing.salePrice),
        currentStock: Value(newStock),
        // Update pharmacy fields only if new value exists and old was empty
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
      // INSERT new
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
    final orderNumber = preview.header.invoiceNumber ?? 'PDF-${DateTime.now().millisecondsSinceEpoch}';

    final users = await _db.select(_db.users).get();
    final userId = users.isNotEmpty ? users.first.id : 'system';

    final subtotal = preview.totals.subtotal;
    final tax = preview.totals.tax;
    final total = preview.totals.total;

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
        notes: Value('Importado desde PDF: ${preview.header.fileName ?? "factura"}'),
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
  // ── HELPER ──
  // ══════════════════════════════════════════════════════════════
  InvoicePreview _errorPreview(String message, String? fileName) {
    return InvoicePreview(
      header: InvoiceHeader()
        ..detectedFormat = 'PDF'
        ..fileName = fileName,
      supplier: SupplierPreview(),
      client: ClientPreview(),
      items: [],
      totals: InvoiceTotals(),
      warnings: [message],
      status: PreviewStatus.error,
    );
  }
}
