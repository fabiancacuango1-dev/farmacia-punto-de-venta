import 'dart:convert';

import 'package:dio/dio.dart';

import '../secure_config_service.dart';

// ══════════════════════════════════════════════════════════════
// ── GEMINI AI SERVICE ──
// ══════════════════════════════════════════════════════════════
/// Calls Google Gemini API for pharmaceutical PDF analysis.
/// Extracts structured product data from raw invoice text.
class GeminiService {
  static GeminiService? _instance;
  static GeminiService get instance => _instance ??= GeminiService._();
  GeminiService._();

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
  ));

  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const _model = 'gemini-2.0-flash';

  /// Tests if the API key is valid by making a small request.
  Future<bool> testConnection() async {
    try {
      final apiKey = await SecureConfigService.instance.getGeminiApiKey();
      if (apiKey == null || apiKey.isEmpty) return false;

      final response = await _dio.post(
        '$_baseUrl/$_model:generateContent?key=$apiKey',
        data: {
          'contents': [
            {
              'parts': [
                {'text': 'Responde solo: OK'}
              ]
            }
          ],
          'generationConfig': {'maxOutputTokens': 10},
        },
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Analyzes raw text extracted from a PDF invoice and returns
  /// structured pharmaceutical product data as a JSON list.
  Future<List<Map<String, dynamic>>?> analyzeInvoiceText(
    String rawText, {
    String? supplierName,
  }) async {
    final apiKey = await SecureConfigService.instance.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    final prompt = _buildPrompt(rawText, supplierName: supplierName);

    try {
      final response = await _dio.post(
        '$_baseUrl/$_model:generateContent?key=$apiKey',
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 8192,
            'responseMimeType': 'application/json',
          },
        },
      );

      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;

      final text = parts[0]['text'] as String?;
      if (text == null || text.trim().isEmpty) return null;

      // Parse JSON response
      final parsed = json.decode(text.trim());
      if (parsed is List) {
        return parsed.cast<Map<String, dynamic>>();
      }
      if (parsed is Map && parsed.containsKey('products')) {
        return (parsed['products'] as List).cast<Map<String, dynamic>>();
      }
      if (parsed is Map && parsed.containsKey('items')) {
        return (parsed['items'] as List).cast<Map<String, dynamic>>();
      }

      return null;
    } on DioException catch (e) {
      print('[Gemini] DioException in analyzeInvoiceText: ${e.type} ${e.message}');
      return null;
    } catch (e) {
      print('[Gemini] Error in analyzeInvoiceText: $e');
      return null;
    }
  }

  /// Extracts supplier/header info from invoice text.
  Future<Map<String, dynamic>?> analyzeInvoiceHeader(String rawText) async {
    final apiKey = await SecureConfigService.instance.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    try {
      final response = await _dio.post(
        '$_baseUrl/$_model:generateContent?key=$apiKey',
        data: {
          'contents': [
            {
              'parts': [
                {
                  'text': '''Analiza este texto de factura y extrae SOLO la información del encabezado y proveedor.
Responde SOLO en JSON con esta estructura exacta:
{
  "invoiceNumber": "string o null",
  "issueDate": "string o null (formato DD/MM/YYYY)",
  "invoiceType": "string o null",
  "accessKey": "string o null (clave de acceso SRI 49 dígitos)",
  "supplierName": "string o null (razón social del emisor)",
  "supplierRuc": "string o null (RUC/cédula del emisor)",
  "supplierCommercialName": "string o null",
  "supplierAddress": "string o null",
  "supplierPhone": "string o null",
  "clientName": "string o null",
  "clientId": "string o null"
}

TEXTO DE LA FACTURA:
$rawText'''
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 2048,
            'responseMimeType': 'application/json',
          },
        },
      );

      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      final text = parts[0]['text'] as String?;
      if (text == null) return null;

      return json.decode(text.trim()) as Map<String, dynamic>;
    } catch (e) {
      print('[Gemini] Error in analyzeInvoiceHeader: $e');
      return null;
    }
  }

  String _buildPrompt(String rawText, {String? supplierName}) {
    return '''Eres un experto farmacéutico ecuatoriano analizando una factura de compra de medicamentos.
Analiza el siguiente texto extraído de un PDF de factura y extrae TODOS los productos como una lista JSON.

REGLAS IMPORTANTES:
1. Cada producto debe tener TODOS estos campos (usa null si no encuentras el dato):
2. Los precios deben ser números decimales, NO strings
3. Si un producto tiene nombre compuesto como "AMOXICILINA 500MG TABLETAS X 20", separa:
   - description: nombre completo tal como aparece
   - genericName: solo el principio activo (ej: "Amoxicilina")
   - concentration: la concentración (ej: "500mg")
   - presentation: la forma farmacéutica (ej: "Tabletas")
   - unitsPerBox: las unidades por caja si se indica (ej: 20)
4. Detecta si es medicamento GENÉRICO o de MARCA
5. En Ecuador: medicinas de uso humano tienen IVA 0%. Si el IVA es 0%, isTaxExempt = true
6. Identifica sustancias controladas (psicotrópicos, estupefacientes)
7. Detecta si requiere receta médica según la normativa ecuatoriana
8. Para vía de administración, infiere del tipo de presentación (tableta=Oral, crema=Tópica, inyectable=Parenteral, etc.)

${supplierName != null ? 'PROVEEDOR: $supplierName\n' : ''}
ESTRUCTURA JSON REQUERIDA para cada producto:
[
  {
    "code": "código principal del producto",
    "auxCode": "código auxiliar/barras",
    "description": "nombre completo tal como aparece en la factura",
    "genericName": "nombre genérico/principio activo",
    "presentation": "Tableta|Cápsula|Jarabe|Crema|Ampolla|Inyectable|Suspensión|Gotas|Supositorio|Parche|Gel|Pomada|Polvo|Solución|Óvulo",
    "concentration": "concentración con unidad (ej: 500mg, 10ml, 0.5%)",
    "laboratory": "laboratorio fabricante si se identifica",
    "quantity": 0.0,
    "unitPrice": 0.0,
    "discount": 0.0,
    "taxAmount": 0.0,
    "taxPercent": 0.0,
    "subtotal": 0.0,
    "total": 0.0,
    "unit": "unidad de medida",
    "costPrice": 0.0,
    "registroSanitario": "registro sanitario si aparece",
    "adminRoute": "Oral|Tópica|Parenteral|Oftálmica|Ótica|Nasal|Rectal|Vaginal|Inhalatoria|Sublingual",
    "batchNumber": "número de lote si aparece",
    "expirationDate": "fecha de vencimiento si aparece (DD/MM/YYYY)",
    "requiresPrescription": false,
    "isControlled": false,
    "isTaxExempt": true,
    "unitsPerBox": null,
    "costPerBox": null,
    "saleType": "Unidad/Pieza",
    "storageCondition": "Ambiente|Refrigeración|Congelación"
  }
]

TEXTO DE LA FACTURA:
$rawText''';
  }
}
