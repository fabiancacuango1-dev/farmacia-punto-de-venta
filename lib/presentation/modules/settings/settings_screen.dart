import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
