import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/platform_io.dart'
    if (dart.library.js_interop) '../utils/platform_io_web.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:path_provider/path_provider.dart';

// ══════════════════════════════════════════════════════════════
// ── SECURE CONFIG SERVICE ──
// ══════════════════════════════════════════════════════════════
/// Stores and retrieves sensitive configuration (API keys, etc.)
/// encrypted on disk using AES-256. Never stores keys in plain text
/// or in source code. On web, uses in-memory storage (session only).
class SecureConfigService {
  static SecureConfigService? _instance;
  static SecureConfigService get instance => _instance ??= SecureConfigService._();
  SecureConfigService._();

  static const _configFileName = '.farmapos_secure.enc';

  // In-memory cache for web fallback
  Map<String, dynamic> _memoryCache = {};

  encrypt_lib.Key get _key {
    final seed = 'FarmaPos_${Platform.localHostname}_SecureVault_2026';
    final hash = sha256.convert(utf8.encode(seed)).bytes;
    return encrypt_lib.Key.fromBase16(
      hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
  }

  encrypt_lib.IV get _iv {
    final seed = 'FarmaPos_IV_Salt';
    final hash = md5.convert(utf8.encode(seed)).bytes;
    return encrypt_lib.IV.fromBase16(
      hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
  }

  Future<Map<String, dynamic>> _readConfig() async {
    if (kIsWeb) return Map<String, dynamic>.from(_memoryCache);
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_configFileName');
      if (!await file.exists()) return {};
      final encrypted = await file.readAsString();
      if (encrypted.trim().isEmpty) return {};
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(_key));
      final decrypted = encrypter.decrypt64(encrypted.trim(), iv: _iv);
      return json.decode(decrypted) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeConfig(Map<String, dynamic> config) async {
    _memoryCache = Map<String, dynamic>.from(config);
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_configFileName');
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(_key));
      final plaintext = json.encode(config);
      final encrypted = encrypter.encrypt(plaintext, iv: _iv);
      await file.writeAsString(encrypted.base64);
    } catch (_) {
      // On platforms without file I/O, config stays in memory only
    }
  }

  // ── Public API ──

  Future<String?> getGeminiApiKey() async {
    final config = await _readConfig();
    return config['gemini_api_key'] as String?;
  }

  Future<void> setGeminiApiKey(String key) async {
    final config = await _readConfig();
    config['gemini_api_key'] = key;
    await _writeConfig(config);
  }

  Future<void> removeGeminiApiKey() async {
    final config = await _readConfig();
    config.remove('gemini_api_key');
    await _writeConfig(config);
  }

  Future<bool> get hasGeminiKey async {
    final key = await getGeminiApiKey();
    return key != null && key.isNotEmpty;
  }

  Future<bool> getAiEnabled() async {
    final config = await _readConfig();
    return config['ai_enabled'] == true;
  }

  Future<void> setAiEnabled(bool enabled) async {
    final config = await _readConfig();
    config['ai_enabled'] = enabled;
    await _writeConfig(config);
  }
}
