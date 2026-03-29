import 'dart:convert';
import '../../utils/platform_io.dart'
    if (dart.library.js_interop) '../../utils/platform_io_web.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../data/database/app_database.dart';

/// Handles import/export of product data from CSV/Excel files
class ImportExportService {
  final AppDatabase _db;

  ImportExportService(this._db);

  /// Import products from CSV content (string)
  Future<ImportResult> importProductsFromCsv(String csvContent) async {
    final lines = const LineSplitter().convert(csvContent);
    if (lines.isEmpty) {
      return ImportResult(imported: 0, errors: ['Archivo vacío']);
    }

    final headers = lines.first.split(',').map((h) => h.trim().toLowerCase()).toList();
    final errors = <String>[];
    var imported = 0;

    for (var i = 1; i < lines.length; i++) {
      try {
        final values = _parseCsvLine(lines[i]);
        if (values.length != headers.length) {
          errors.add('Línea ${i + 1}: columnas no coinciden');
          continue;
        }

        final row = Map<String, String>.fromIterables(headers, values);
        final id = 'prod_import_${DateTime.now().millisecondsSinceEpoch}_$i';

        await _db.productsDao.insertProduct(ProductsCompanion.insert(
          id: id,
          name: row['nombre'] ?? row['name'] ?? 'Sin nombre',
          barcode: Value(row['codigo_barras'] ?? row['barcode']),
          internalCode: Value(row['codigo_interno'] ?? row['internal_code']),
          genericName: Value(row['nombre_generico'] ?? row['generic_name']),
          description: Value(row['descripcion'] ?? row['description']),
          presentation: Value(row['presentacion'] ?? row['presentation']),
          concentration: Value(row['concentracion'] ?? row['concentration']),
          laboratory: Value(row['laboratorio'] ?? row['laboratory']),
          costPrice: Value(double.tryParse(row['precio_costo'] ?? row['cost_price'] ?? '') ?? 0),
          salePrice: Value(double.tryParse(row['precio_venta'] ?? row['sale_price'] ?? '') ?? 0),
          minStock: Value(double.tryParse(row['stock_minimo'] ?? row['min_stock'] ?? '') ?? 10),
          currentStock: Value(double.tryParse(row['stock'] ?? row['current_stock'] ?? '') ?? 0),
          unit: Value(row['unidad'] ?? row['unit'] ?? 'unidad'),
          requiresPrescription: Value(
            (row['requiere_receta'] ?? row['requires_prescription'] ?? 'false').toLowerCase() == 'true' ||
            (row['requiere_receta'] ?? row['requires_prescription'] ?? '0') == '1',
          ),
        ));
        imported++;
      } catch (e) {
        errors.add('Línea ${i + 1}: $e');
      }
    }

    return ImportResult(imported: imported, errors: errors);
  }

  /// Export products to CSV string
  Future<String> exportProductsToCsv() async {
    final products = await _db.productsDao.getAllProducts();
    final buffer = StringBuffer();

    // Header
    buffer.writeln('codigo_barras,codigo_interno,nombre,nombre_generico,presentacion,concentracion,laboratorio,precio_costo,precio_venta,stock,stock_minimo,unidad,requiere_receta');

    for (final p in products) {
      buffer.writeln([
        _escapeCsv(p.barcode ?? ''),
        _escapeCsv(p.internalCode ?? ''),
        _escapeCsv(p.name),
        _escapeCsv(p.genericName ?? ''),
        _escapeCsv(p.presentation ?? ''),
        _escapeCsv(p.concentration ?? ''),
        _escapeCsv(p.laboratory ?? ''),
        p.costPrice.toStringAsFixed(2),
        p.salePrice.toStringAsFixed(2),
        p.currentStock.toStringAsFixed(0),
        p.minStock.toStringAsFixed(0),
        _escapeCsv(p.unit),
        p.requiresPrescription ? '1' : '0',
      ].join(','));
    }

    return buffer.toString();
  }

  /// Save exported file to documents directory
  Future<String> saveExportFile(String content, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'farmapos', 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final file = File(p.join(exportDir.path, filename));
    await file.writeAsString(content);
    return file.path;
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

class ImportResult {
  final int imported;
  final List<String> errors;
  ImportResult({required this.imported, required this.errors});
  bool get hasErrors => errors.isNotEmpty;
}
