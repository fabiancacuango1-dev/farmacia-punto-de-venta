import '../../utils/platform_io.dart'
    if (dart.library.js_interop) '../../utils/platform_io_web.dart';
import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../data/database/app_database.dart';

class ExcelImportService {
  final AppDatabase _db;

  ExcelImportService(this._db);

  // ── Column mapping: Spanish → DB field ──
  static const _columnMap = {
    'codigo_barras': 'barcode',
    'codigo barras': 'barcode',
    'código de barras': 'barcode',
    'barcode': 'barcode',
    'codigo': 'barcode',
    'código': 'barcode',
    'codigo_interno': 'internalCode',
    'codigo interno': 'internalCode',
    'nombre': 'name',
    'descripcion del producto': 'name',
    'descripción del producto': 'name',
    'product name': 'name',
    'name': 'name',
    'nombre_generico': 'genericName',
    'nombre generico': 'genericName',
    'nombre genérico': 'genericName',
    'principio activo': 'genericName',
    'descripcion': 'description',
    'descripción': 'description',
    'departamento': 'category',
    'categoria': 'category',
    'categoría': 'category',
    'category': 'category',
    'presentacion': 'presentation',
    'presentación': 'presentation',
    'concentracion': 'concentration',
    'concentración': 'concentration',
    'laboratorio': 'laboratory',
    'laboratory': 'laboratory',
    'costo': 'costPrice',
    'precio_costo': 'costPrice',
    'precio costo': 'costPrice',
    'cost': 'costPrice',
    'precio_venta': 'salePrice',
    'precio venta': 'salePrice',
    'p. venta': 'salePrice',
    'price': 'salePrice',
    'p venta': 'salePrice',
    'precio_mayoreo': 'wholesalePrice',
    'precio mayoreo': 'wholesalePrice',
    'p. mayoreo': 'wholesalePrice',
    'p mayoreo': 'wholesalePrice',
    'existencia': 'currentStock',
    'stock': 'currentStock',
    'inventario': 'currentStock',
    'stock_minimo': 'minStock',
    'stock minimo': 'minStock',
    'inv. mínimo': 'minStock',
    'inv. minimo': 'minStock',
    'inv minimo': 'minStock',
    'stock_maximo': 'maxStock',
    'stock maximo': 'maxStock',
    'inv. máximo': 'maxStock',
    'inv. maximo': 'maxStock',
    'inv maximo': 'maxStock',
    'unidad': 'unit',
    'tipo_venta': 'saleType',
    'tipo venta': 'saleType',
    'tipo de venta': 'saleType',
    'ubicacion': 'location',
    'ubicación': 'location',
    'location': 'location',
    'estante': 'shelf',
    'anaquel': 'shelf',
    'pasillo': 'shelf',
    'shelf': 'shelf',
    'fecha_caducidad': 'expirationDate',
    'fecha caducidad': 'expirationDate',
    'caducidad': 'expirationDate',
    'vencimiento': 'expirationDate',
    'lote': 'batchNumber',
    'batch': 'batchNumber',
    'numero de lote': 'batchNumber',
    'receta': 'requiresPrescription',
    'requiere_receta': 'requiresPrescription',
  };

  /// Generate and save an Excel template for bulk product import
  Future<String> generateTemplate() async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Productos';

    // Headers
    final headers = [
      'Código de Barras',
      'Nombre',
      'Nombre Genérico',
      'Descripción',
      'Departamento',
      'Presentación',
      'Concentración',
      'Laboratorio',
      'Precio Costo',
      'Precio Venta',
      'Precio Mayoreo',
      'Existencia',
      'Inv. Mínimo',
      'Inv. Máximo',
      'Unidad',
      'Tipo Venta',
      'Ubicación',
      'Estante',
      'Lote',
      'Fecha Caducidad',
      'Requiere Receta',
    ];

    // Header style
    final headerStyle = xlsio.CellStyle(workbook);
    headerStyle.bold = true;
    headerStyle.fontColor = '#FFFFFF';
    headerStyle.backColor = '#D97706';
    headerStyle.fontSize = 11;
    headerStyle.hAlign = xlsio.HAlignType.center;

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle = headerStyle;
      sheet.autoFitColumn(i + 1);
    }

    // Example row
    final exampleData = [
      '7501234567890',
      'Paracetamol 500mg',
      'Paracetamol',
      'Analgésico antipirético',
      'Analgésicos',
      'Tableta',
      '500mg',
      'Genérico',
      '2.50',
      '8.00',
      '6.50',
      '100',
      '20',
      '200',
      'caja',
      'Unidad/Pieza',
      'Estante A-1',
      'Pasillo 2',
      'LOT2024-001',
      '2026-12-31',
      'No',
    ];

    final exampleStyle = xlsio.CellStyle(workbook);
    exampleStyle.fontColor = '#94A3B8';
    exampleStyle.italic = true;

    for (var i = 0; i < exampleData.length; i++) {
      final cell = sheet.getRangeByIndex(2, i + 1);
      cell.setText(exampleData[i]);
      cell.cellStyle = exampleStyle;
    }

    // Instructions sheet
    final instrSheet = workbook.worksheets.addWithName('Instrucciones');
    instrSheet.getRangeByIndex(1, 1).setText('INSTRUCCIONES DE IMPORTACIÓN');
    instrSheet.getRangeByIndex(1, 1).cellStyle.bold = true;
    instrSheet.getRangeByIndex(1, 1).cellStyle.fontSize = 14;

    final instructions = [
      '',
      '1. Llene sus productos en la hoja "Productos" a partir de la fila 2.',
      '2. La fila 2 es un ejemplo, puede eliminarla o reemplazarla.',
      '3. Solo el campo "Nombre" es obligatorio.',
      '4. Precios deben ser números (ej: 15.50).',
      '5. "Tipo Venta" puede ser: Unidad/Pieza, A Granel (Decimales), Paquete/Kit.',
      '6. "Requiere Receta" puede ser: Sí/No, 1/0, true/false.',
      '7. "Fecha Caducidad" debe ser formato YYYY-MM-DD (ej: 2026-12-31).',
      '8. Si incluye Lote y Fecha Caducidad, se creará un lote automáticamente.',
      '9. Si el código de barras ya existe, se ACTUALIZA el producto existente.',
      '',
      'UNIDADES VÁLIDAS:',
      'unidad, caja, frasco, tubo, sobre, ampolla, vial, blíster, tira, rollo, litro, galón, gramo, kilogramo',
      '',
      'PRESENTACIONES VÁLIDAS:',
      'Tableta, Cápsula, Jarabe, Inyectable, Crema, Gel, Gotas, Suspensión, Polvo, Sobre, Aerosol, Parche, Otro',
    ];

    for (var i = 0; i < instructions.length; i++) {
      instrSheet.getRangeByIndex(i + 2, 1).setText(instructions[i]);
    }

    instrSheet.autoFitColumn(1);

    // Save
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'farmapos', 'templates'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final filePath = p.join(exportDir.path, 'plantilla_productos.xlsx');
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  /// Import products from an Excel file
  Future<ImportExcelResult> importFromExcel(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final errors = <String>[];
    var imported = 0;
    var updated = 0;
    var skipped = 0;

    // Find the first sheet with data
    final sheetName = excel.tables.keys.firstWhere(
      (k) => k.toLowerCase() != 'instrucciones',
      orElse: () => excel.tables.keys.first,
    );
    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.rows.isEmpty) {
      return ImportExcelResult(
        imported: 0,
        updated: 0,
        skipped: 0,
        errors: ['No se encontraron datos en el archivo'],
      );
    }

    // Parse headers from first row
    final headerRow = sheet.rows[0];
    final colMapping = <int, String>{}; // column index → DB field name
    for (var i = 0; i < headerRow.length; i++) {
      final cellValue = headerRow[i]?.value?.toString().trim().toLowerCase() ?? '';
      if (cellValue.isEmpty) continue;
      final dbField = _columnMap[cellValue];
      if (dbField != null) {
        colMapping[i] = dbField;
      }
    }

    if (!colMapping.containsValue('name') && !colMapping.containsValue('barcode')) {
      return ImportExcelResult(
        imported: 0,
        updated: 0,
        skipped: 0,
        errors: [
          'No se encontraron columnas reconocidas.\n'
              'Asegúrese de que la primera fila contenga encabezados como:\n'
              'Nombre, Código de Barras, Precio Venta, Existencia, etc.'
        ],
      );
    }

    // Get existing categories for matching
    final allCategories = await _db.productsDao.getAllCategories();
    final categoryMap = {
      for (final c in allCategories) c.name.toLowerCase(): c.id,
    };

    // Process each data row (skip header row 0)
    for (var rowIdx = 1; rowIdx < sheet.rows.length; rowIdx++) {
      final row = sheet.rows[rowIdx];
      if (row.every((c) => c?.value == null || c!.value.toString().trim().isEmpty)) {
        continue; // Skip empty rows
      }

      try {
        final data = <String, String>{};
        for (final entry in colMapping.entries) {
          final cell = rowIdx < row.length && entry.key < row.length ? row[entry.key] : null;
          if (cell?.value != null) {
            data[entry.value] = cell!.value.toString().trim();
          }
        }

        final name = data['name'] ?? '';
        if (name.isEmpty) {
          skipped++;
          continue;
        }

        final barcode = data['barcode'];
        final costPrice = double.tryParse(data['costPrice']?.replaceAll('\$', '').replaceAll(',', '') ?? '') ?? 0;
        final salePrice = double.tryParse(data['salePrice']?.replaceAll('\$', '').replaceAll(',', '') ?? '') ?? 0;
        final wholesalePrice = double.tryParse(data['wholesalePrice']?.replaceAll('\$', '').replaceAll(',', '') ?? '');
        final stock = double.tryParse(data['currentStock'] ?? '') ?? 0;
        final minStock = double.tryParse(data['minStock'] ?? '') ?? 10;
        final maxStock = double.tryParse(data['maxStock'] ?? '');
        final requiresRx = _parseBool(data['requiresPrescription']);

        // Match category
        String? categoryId;
        if (data['category'] != null) {
          final catLower = data['category']!.toLowerCase();
          categoryId = categoryMap[catLower];
          if (categoryId == null) {
            // Create new category
            categoryId = 'cat_import_${DateTime.now().millisecondsSinceEpoch}_$rowIdx';
            await _db.productsDao.insertCategory(CategoriesCompanion(
              id: Value(categoryId),
              name: Value(data['category']!),
            ));
            categoryMap[catLower] = categoryId;
          }
        }

        // Check if product exists (by barcode)
        Product? existing;
        if (barcode != null && barcode.isNotEmpty) {
          existing = await _db.productsDao.getProductByBarcode(barcode);
        }

        if (existing != null) {
          // Update existing product
          await (_db.update(_db.products)..where((p) => p.id.equals(existing!.id))).write(
            ProductsCompanion(
              name: Value(name),
              genericName: Value(data['genericName']),
              description: Value(data['description']),
              categoryId: Value(categoryId),
              presentation: Value(data['presentation']),
              concentration: Value(data['concentration']),
              laboratory: Value(data['laboratory']),
              costPrice: Value(costPrice),
              salePrice: Value(salePrice),
              wholesalePrice: Value(wholesalePrice),
              currentStock: Value(stock),
              minStock: Value(minStock),
              maxStock: Value(maxStock),
              unit: Value(data['unit'] ?? existing.unit),
              saleType: Value(data['saleType'] ?? existing.saleType),
              location: Value(data['location']),
              shelf: Value(data['shelf']),
              requiresPrescription: Value(requiresRx),
              updatedAt: Value(DateTime.now()),
              syncStatus: const Value('pending'),
            ),
          );
          updated++;
        } else {
          // Insert new product
          final id = 'prod_xl_${DateTime.now().millisecondsSinceEpoch}_$rowIdx';
          await _db.productsDao.insertProduct(ProductsCompanion.insert(
            id: id,
            name: name,
            barcode: Value(barcode),
            internalCode: Value(data['internalCode']),
            genericName: Value(data['genericName']),
            description: Value(data['description']),
            categoryId: Value(categoryId),
            presentation: Value(data['presentation']),
            concentration: Value(data['concentration']),
            laboratory: Value(data['laboratory']),
            costPrice: Value(costPrice),
            salePrice: Value(salePrice),
            wholesalePrice: Value(wholesalePrice),
            currentStock: Value(stock),
            minStock: Value(minStock),
            maxStock: Value(maxStock),
            unit: Value(data['unit'] ?? 'unidad'),
            saleType: Value(data['saleType'] ?? 'Unidad/Pieza'),
            location: Value(data['location']),
            shelf: Value(data['shelf']),
            requiresPrescription: Value(requiresRx),
          ));
          imported++;

          // If batch info is present, create a batch
          if (data['batchNumber'] != null || data['expirationDate'] != null) {
            DateTime? expiry;
            if (data['expirationDate'] != null) {
              expiry = DateTime.tryParse(data['expirationDate']!);
            }
            await _db.productsDao.insertBatch(ProductBatchesCompanion(
              id: Value('batch_xl_${DateTime.now().millisecondsSinceEpoch}_$rowIdx'),
              productId: Value(id),
              batchNumber: Value(data['batchNumber'] ?? 'IMP-$rowIdx'),
              expirationDate: Value(expiry ?? DateTime.now().add(const Duration(days: 365))),
              quantity: Value(stock),
              costPrice: Value(costPrice),
            ));
          }
        }
      } catch (e) {
        errors.add('Fila ${rowIdx + 1}: $e');
      }
    }

    return ImportExcelResult(
      imported: imported,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  /// Export all products to Excel
  Future<String> exportToExcel() async {
    final products = await _db.productsDao.getAllProducts();
    final categories = await _db.productsDao.getAllCategories();
    final categoryMap = {for (final c in categories) c.id: c.name};

    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Productos';

    final headers = [
      'Código de Barras', 'Nombre', 'Nombre Genérico', 'Descripción',
      'Departamento', 'Presentación', 'Concentración', 'Laboratorio',
      'Costo', 'P. Venta', 'P. Mayoreo', 'Existencia',
      'Inv. Mínimo', 'Inv. Máximo', 'Unidad', 'Tipo Venta',
      'Ubicación', 'Estante', 'Receta',
    ];

    final headerStyle = xlsio.CellStyle(workbook);
    headerStyle.bold = true;
    headerStyle.fontColor = '#FFFFFF';
    headerStyle.backColor = '#2563EB';
    headerStyle.fontSize = 11;

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (var r = 0; r < products.length; r++) {
      final prod = products[r];
      final row = r + 2;
      sheet.getRangeByIndex(row, 1).setText(prod.barcode ?? '');
      sheet.getRangeByIndex(row, 2).setText(prod.name);
      sheet.getRangeByIndex(row, 3).setText(prod.genericName ?? '');
      sheet.getRangeByIndex(row, 4).setText(prod.description ?? '');
      sheet.getRangeByIndex(row, 5).setText(categoryMap[prod.categoryId] ?? '');
      sheet.getRangeByIndex(row, 6).setText(prod.presentation ?? '');
      sheet.getRangeByIndex(row, 7).setText(prod.concentration ?? '');
      sheet.getRangeByIndex(row, 8).setText(prod.laboratory ?? '');
      sheet.getRangeByIndex(row, 9).setNumber(prod.costPrice);
      sheet.getRangeByIndex(row, 10).setNumber(prod.salePrice);
      sheet.getRangeByIndex(row, 11).setNumber(prod.wholesalePrice ?? 0);
      sheet.getRangeByIndex(row, 12).setNumber(prod.currentStock);
      sheet.getRangeByIndex(row, 13).setNumber(prod.minStock);
      sheet.getRangeByIndex(row, 14).setNumber(prod.maxStock ?? 0);
      sheet.getRangeByIndex(row, 15).setText(prod.unit);
      sheet.getRangeByIndex(row, 16).setText(prod.saleType);
      sheet.getRangeByIndex(row, 17).setText(prod.location ?? '');
      sheet.getRangeByIndex(row, 18).setText(prod.shelf ?? '');
      sheet.getRangeByIndex(row, 19).setText(prod.requiresPrescription ? 'Sí' : 'No');
    }

    // Auto-fit columns
    for (var i = 1; i <= headers.length; i++) {
      sheet.autoFitColumn(i);
    }

    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'farmapos', 'exports'));
    if (!await exportDir.exists()) await exportDir.create(recursive: true);

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final filePath = p.join(exportDir.path, 'productos_$timestamp.xlsx');
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  bool _parseBool(String? value) {
    if (value == null) return false;
    final v = value.toLowerCase().trim();
    return v == 'true' || v == '1' || v == 'sí' || v == 'si' || v == 'yes';
  }
}

class ImportExcelResult {
  final int imported;
  final int updated;
  final int skipped;
  final List<String> errors;

  ImportExcelResult({
    required this.imported,
    required this.updated,
    required this.skipped,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
  int get total => imported + updated;
}
