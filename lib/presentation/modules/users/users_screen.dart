import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../services/auth/auth_service.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Usuarios',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showUserDialog(context, ref),
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Nuevo Usuario'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                child: StreamBuilder<List<User>>(
                  stream: db.usersDao.watchAllUsers(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final users = snapshot.data!;
                    return SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Usuario')),
                          DataColumn(label: Text('Nombre')),
                          DataColumn(label: Text('Rol')),
                          DataColumn(label: Text('Último Acceso')),
                          DataColumn(label: Text('Estado')),
                          DataColumn(label: Text('Acciones')),
                        ],
                        rows: users.map((user) {
                          return DataRow(cells: [
                            DataCell(Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  child: Text(
                                    user.fullName[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(user.username),
                              ],
                            )),
                            DataCell(Text(user.fullName)),
                            DataCell(_RoleBadge(role: user.role)),
                            DataCell(Text(
                              user.lastLogin?.toString().substring(0, 16) ?? 'Nunca',
                            )),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: user.isActive
                                    ? AppColors.success.withValues(alpha: 0.1)
                                    : AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                user.isActive ? 'Activo' : 'Inactivo',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: user.isActive
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                            )),
                            DataCell(Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () {},
                                  tooltip: 'Editar',
                                ),
                                if (user.username != 'admin')
                                  IconButton(
                                    icon: const Icon(Icons.block, size: 18),
                                    onPressed: () async {
                                      await db.usersDao
                                          .deactivateUser(user.id);
                                    },
                                    tooltip: 'Desactivar',
                                  ),
                              ],
                            )),
                          ]);
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Audit Log
            const Text(
              'Registro de Auditoría',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: FutureBuilder<List<AuditLogData>>(
                  future: db.usersDao.getAuditLog(limit: 50),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text('Sin registros'));
                    }

                    return SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 20,
                        columns: const [
                          DataColumn(label: Text('Fecha')),
                          DataColumn(label: Text('Usuario')),
                          DataColumn(label: Text('Acción')),
                          DataColumn(label: Text('Tabla')),
                          DataColumn(label: Text('Registro')),
                        ],
                        rows: snapshot.data!.map((log) {
                          return DataRow(cells: [
                            DataCell(Text(
                                log.createdAt.toString().substring(0, 16))),
                            DataCell(Text(log.userId)),
                            DataCell(_ActionBadge(action: log.action)),
                            DataCell(Text(log.targetTable ?? '-')),
                            DataCell(Text(log.recordId ?? '-')),
                          ]);
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserDialog(BuildContext context, WidgetRef ref) {
    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final passwordController = TextEditingController();
    String role = 'cashier';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuevo Usuario'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de Usuario',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: const [
                    DropdownMenuItem(
                        value: 'admin', child: Text('Administrador')),
                    DropdownMenuItem(
                        value: 'cashier', child: Text('Cajero')),
                    DropdownMenuItem(
                        value: 'warehouse', child: Text('Bodeguero')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => role = v ?? 'cashier'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final authService = ref.read(authServiceProvider);
                  await authService.createUser(
                    id: const Uuid().v4(),
                    username: usernameController.text.trim(),
                    password: passwordController.text,
                    fullName: fullNameController.text.trim(),
                    role: role,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Usuario creado exitosamente'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final config = _roleConfig[role] ?? ('Usuario', Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: config.$2.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        config.$1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: config.$2,
        ),
      ),
    );
  }

  static const Map<String, (String, Color)> _roleConfig = {
    'admin': ('Administrador', AppColors.error),
    'cashier': ('Cajero', AppColors.primary),
    'warehouse': ('Bodeguero', AppColors.info),
  };
}

class _ActionBadge extends StatelessWidget {
  final String action;
  const _ActionBadge({required this.action});

  @override
  Widget build(BuildContext context) {
    return Text(
      action,
      style: const TextStyle(fontSize: 13),
    );
  }
}
