import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/secure_config_service.dart';
import '../../../services/ai/gemini_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _aiEnabled = false;
  bool _hasKey = false;
  bool _testingConnection = false;
  String? _connectionStatus;
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAiConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadAiConfig() async {
    final config = SecureConfigService.instance;
    final enabled = await config.getAiEnabled();
    final hasKey = await config.hasGeminiKey;
    if (mounted) {
      setState(() {
        _aiEnabled = enabled;
        _hasKey = hasKey;
      });
    }
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;
    await SecureConfigService.instance.setGeminiApiKey(key);
    await SecureConfigService.instance.setAiEnabled(true);
    _apiKeyController.clear();
    await _loadAiConfig();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key guardada de forma segura'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _removeApiKey() async {
    await SecureConfigService.instance.removeGeminiApiKey();
    await SecureConfigService.instance.setAiEnabled(false);
    await _loadAiConfig();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key eliminada'), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() { _testingConnection = true; _connectionStatus = null; });
    final ok = await GeminiService.instance.testConnection();
    if (mounted) {
      setState(() {
        _testingConnection = false;
        _connectionStatus = ok ? '✅ Conexión exitosa con Gemini' : '❌ No se pudo conectar. Verifica tu API Key.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuración',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  // General
                  _SettingsSection(
                    title: 'General',
                    icon: Icons.settings,
                    children: [
                      _SettingsTile(
                        title: 'Nombre del Negocio',
                        subtitle: 'Farmacia FarmaPos',
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: () {},
                      ),
                      _SettingsTile(
                        title: 'RUC',
                        subtitle: 'Configure el RUC de la farmacia',
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: () {},
                      ),
                      _SettingsTile(
                        title: 'Dirección',
                        subtitle: 'Configure la dirección',
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Apariencia
                  _SettingsSection(
                    title: 'Apariencia',
                    icon: Icons.palette,
                    children: [
                      _SettingsTile(
                        title: 'Tema',
                        subtitle: themeMode == ThemeMode.dark
                            ? 'Oscuro'
                            : 'Claro',
                        trailing: Switch(
                          value: themeMode == ThemeMode.dark,
                          onChanged: (v) {
                            ref.read(themeModeProvider.notifier).state =
                                v ? ThemeMode.dark : ThemeMode.light;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Tax Configuration (Ecuador)
                  _SettingsSection(
                    title: 'Impuestos (Ecuador)',
                    icon: Icons.receipt_long,
                    children: [
                      _SettingsTile(
                        title: 'IVA',
                        subtitle: '15% (Vigente desde abril 2024)',
                        trailing: const Icon(Icons.info_outline, size: 18),
                      ),
                      _SettingsTile(
                        title: 'Facturación Electrónica SRI',
                        subtitle: 'Configurar conexión con el SRI',
                        trailing: const Icon(Icons.link, size: 18),
                        onTap: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Inteligencia Artificial
                  _SettingsSection(
                    title: 'Inteligencia Artificial (Gemini)',
                    icon: Icons.auto_awesome,
                    children: [
                      _SettingsTile(
                        title: 'Activar IA para importaciones',
                        subtitle: _aiEnabled
                            ? 'Gemini analiza facturas PDF con inteligencia farmacéutica'
                            : 'Desactivado — se usará análisis local',
                        trailing: Switch(
                          value: _aiEnabled,
                          onChanged: _hasKey
                              ? (v) async {
                                  await SecureConfigService.instance.setAiEnabled(v);
                                  setState(() => _aiEnabled = v);
                                }
                              : null,
                        ),
                      ),
                      _SettingsTile(
                        title: 'API Key de Gemini',
                        subtitle: _hasKey
                            ? '••••••••• (guardada de forma encriptada)'
                            : 'No configurada — obtén tu clave en Google AI Studio',
                        trailing: _hasKey
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                onPressed: _removeApiKey,
                              )
                            : const Icon(Icons.key, size: 18),
                      ),
                      if (!_hasKey)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _apiKeyController,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    hintText: 'Pega tu API Key aquí',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(),
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _saveApiKey,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                                child: const Text('Guardar', style: TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      if (_hasKey)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _testingConnection ? null : _testConnection,
                                icon: _testingConnection
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.wifi_tethering, size: 16),
                                label: Text(_testingConnection ? 'Probando...' : 'Probar Conexión',
                                    style: const TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                              ),
                              if (_connectionStatus != null) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(_connectionStatus!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _connectionStatus!.startsWith('✅') ? Colors.green : Colors.red,
                                      )),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Sync
                  _SettingsSection(
                    title: 'Sincronización',
                    icon: Icons.sync,
                    children: [
                      _SettingsTile(
                        title: 'Servidor Remoto',
                        subtitle: 'No configurado',
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: () {},
                      ),
                      _SettingsTile(
                        title: 'Sincronizar Ahora',
                        subtitle: 'Última sync: nunca',
                        trailing: const Icon(Icons.sync, size: 18),
                        onTap: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Backup
                  _SettingsSection(
                    title: 'Respaldo',
                    icon: Icons.backup,
                    children: [
                      _SettingsTile(
                        title: 'Exportar Base de Datos',
                        subtitle: 'Crear respaldo local',
                        trailing: const Icon(Icons.download, size: 18),
                        onTap: () {},
                      ),
                      _SettingsTile(
                        title: 'Importar Base de Datos',
                        subtitle: 'Restaurar desde respaldo',
                        trailing: const Icon(Icons.upload, size: 18),
                        onTap: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // App Info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'FarmaPos v1.0.0 — Sistema de Farmacia',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}
