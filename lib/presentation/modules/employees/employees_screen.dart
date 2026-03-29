import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show OrderingTerm;

import '../../../core/theme/app_theme.dart';
import '../../../core/extensions/extensions.dart';
import '../../../data/database/app_database.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            const Text('Empleados',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Empleados'),
                Tab(text: 'Asistencia'),
                Tab(text: 'Actividad'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEmployeesList(db),
                  _buildAttendanceTab(db),
                  _buildActivityTab(db),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeesList(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<User>>(
        stream: (db.usersDao.select(db.users)
              ..where((u) => u.isActive.equals(true))
              ..orderBy([(u) => OrderingTerm.asc(u.fullName)]))
            .watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!;
          if (users.isEmpty) {
            return const Center(child: Text('No hay empleados'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final roleLabel = switch (user.role) {
                'admin' => 'Administrador',
                'cashier' => 'Cajero',
                'warehouse' => 'Bodeguero',
                _ => user.role,
              };

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text(
                      user.fullName[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(user.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$roleLabel | @${user.username}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Quick clock in/out
                      ElevatedButton.icon(
                        onPressed: () => _clockIn(db, user.id),
                        icon: const Icon(Icons.login, size: 16),
                        label: const Text('Entrada'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _clockOut(db, user.id),
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('Salida'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAttendanceTab(AppDatabase db) {
    final today = DateTime.now();
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 20),
                const SizedBox(width: 8),
                Text('Asistencia del ${today.formatted}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<EmployeeAttendanceData>>(
              stream: db.employeesDao.watchTodayAttendance(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final records = snapshot.data!;
                if (records.isEmpty) {
                  return const Center(
                      child: Text('No hay registros de asistencia hoy'));
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Empleado')),
                        DataColumn(label: Text('Entrada')),
                        DataColumn(label: Text('Salida')),
                        DataColumn(label: Text('Tipo')),
                      ],
                      rows: records.map((r) {
                        return DataRow(cells: [
                          DataCell(Text(r.userId)),
                          DataCell(Text(r.timestamp.timeOnly)),
                          DataCell(Text('-')),
                          DataCell(Text(r.type)),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTab(AppDatabase db) {
    return Card(
      child: StreamBuilder<List<EmployeeActivity>>(
        stream: db.employeesDao.watchRecentActivities(limit: 50),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final activities = snapshot.data!;
          if (activities.isEmpty) {
            return const Center(child: Text('No hay actividades registradas'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: activities.length,
            itemBuilder: (context, index) {
              final a = activities[index];
              final actionIcon = switch (a.activityType) {
                'sale' => Icons.point_of_sale,
                'login' => Icons.login,
                'logout' => Icons.logout,
                'inventory' => Icons.inventory,
                'product_edit' => Icons.edit,
                _ => Icons.info_outline,
              };

              return ListTile(
                dense: true,
                leading: Icon(actionIcon, size: 20),
                title: Text('${a.activityType} - ${a.userId}'),
                subtitle: Text(a.description),
                trailing: Text(a.createdAt.formattedWithTime,
                    style: const TextStyle(fontSize: 11)),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _clockIn(AppDatabase db, String userId) async {
    await db.employeesDao.recordAttendance(
      EmployeeAttendanceCompanion.insert(
        id: 'att_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: 'check_in',
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrada registrada')),
      );
      setState(() {});
    }
  }

  Future<void> _clockOut(AppDatabase db, String userId) async {
    // Record a check_out entry
    await db.employeesDao.recordAttendance(
      EmployeeAttendanceCompanion.insert(
        id: 'att_out_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: 'check_out',
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Salida registrada')),
      );
      setState(() {});
    }
  }
}
