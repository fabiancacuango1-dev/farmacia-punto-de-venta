import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../services/auth/auth_service.dart';

// ══════════════════════════════════════════════════════════════
// ── MODULE DEFINITIONS ──
// ══════════════════════════════════════════════════════════════

class _ModuleDef {
  final String path;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String category;

  const _ModuleDef({
    required this.path,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.category,
  });
}

const _kCategories = [
  'Operaciones',
  'Catálogos',
  'Documentos',
  'Reportes',
  'Inventarios',
  'Configuración',
];

final _kModules = <_ModuleDef>[
  // ── Operaciones ──
  _ModuleDef(
    path: '/',
    label: 'Punto de Venta',
    subtitle: 'Operaciones',
    icon: LucideIcons.monitor,
    color: const Color(0xFF2563EB),
    category: 'Operaciones',
  ),
  _ModuleDef(
    path: '/cash-register',
    label: 'Corte de Caja',
    subtitle: 'Caja',
    icon: LucideIcons.calculator,
    color: const Color(0xFF7C3AED),
    category: 'Operaciones',
  ),
  _ModuleDef(
    path: '/purchases',
    label: 'Compras',
    subtitle: 'Entradas',
    icon: LucideIcons.shoppingCart,
    color: const Color(0xFF059669),
    category: 'Operaciones',
  ),
  _ModuleDef(
    path: '/credit-notes',
    label: 'Nota de Crédito',
    subtitle: 'Entradas',
    icon: LucideIcons.receipt,
    color: const Color(0xFF0891B2),
    category: 'Operaciones',
  ),

  // ── Catálogos ──
  _ModuleDef(
    path: '/products',
    label: 'Artículos',
    subtitle: 'Catálogos',
    icon: LucideIcons.package,
    color: const Color(0xFF6366F1),
    category: 'Catálogos',
  ),
  _ModuleDef(
    path: '/customers',
    label: 'Clientes',
    subtitle: 'Catálogos',
    icon: LucideIcons.users,
    color: const Color(0xFF0EA5E9),
    category: 'Catálogos',
  ),
  _ModuleDef(
    path: '/suppliers',
    label: 'Proveedores',
    subtitle: 'Catálogos',
    icon: LucideIcons.truck,
    color: const Color(0xFF2563EB),
    category: 'Catálogos',
  ),
  _ModuleDef(
    path: '/promotions',
    label: 'Promociones',
    subtitle: 'Catálogos',
    icon: LucideIcons.tag,
    color: const Color(0xFFEA580C),
    category: 'Catálogos',
  ),
  _ModuleDef(
    path: '/employees',
    label: 'Empleados',
    subtitle: 'Catálogos',
    icon: LucideIcons.userCheck,
    color: const Color(0xFF7C3AED),
    category: 'Catálogos',
  ),

  // ── Documentos ──
  _ModuleDef(
    path: '/invoicing',
    label: 'Facturación',
    subtitle: 'Documentos',
    icon: LucideIcons.fileText,
    color: const Color(0xFF374151),
    category: 'Documentos',
  ),
  _ModuleDef(
    path: '/quotations',
    label: 'Cotizaciones',
    subtitle: 'Documentos',
    icon: LucideIcons.fileEdit,
    color: const Color(0xFF0891B2),
    category: 'Documentos',
  ),
  _ModuleDef(
    path: '/prescriptions',
    label: 'Recetas',
    subtitle: 'Documentos',
    icon: LucideIcons.heartPulse,
    color: const Color(0xFFDC2626),
    category: 'Documentos',
  ),

  // ── Reportes ──
  _ModuleDef(
    path: '/dashboard',
    label: 'Dashboard',
    subtitle: 'Estadísticas',
    icon: LucideIcons.layoutDashboard,
    color: const Color(0xFF2563EB),
    category: 'Reportes',
  ),
  _ModuleDef(
    path: '/reports',
    label: 'Reportes',
    subtitle: 'Reportes',
    icon: LucideIcons.barChart3,
    color: const Color(0xFF059669),
    category: 'Reportes',
  ),

  // ── Inventarios ──
  _ModuleDef(
    path: '/inventory',
    label: 'Inventario',
    subtitle: 'Inventarios',
    icon: LucideIcons.warehouse,
    color: const Color(0xFF7C3AED),
    category: 'Inventarios',
  ),
  _ModuleDef(
    path: '/labels',
    label: 'Etiquetas',
    subtitle: 'Inventarios',
    icon: LucideIcons.tag,
    color: const Color(0xFF0891B2),
    category: 'Inventarios',
  ),

  // ── Configuración ──
  _ModuleDef(
    path: '/settings',
    label: 'Configuración',
    subtitle: 'Sistema',
    icon: LucideIcons.settings,
    color: const Color(0xFF475569),
    category: 'Configuración',
  ),
  _ModuleDef(
    path: '/users',
    label: 'Usuarios',
    subtitle: 'Sistema',
    icon: LucideIcons.shieldCheck,
    color: const Color(0xFFDC2626),
    category: 'Configuración',
  ),
  _ModuleDef(
    path: '/branches',
    label: 'Sucursales',
    subtitle: 'Sistema',
    icon: LucideIcons.building2,
    color: const Color(0xFF059669),
    category: 'Configuración',
  ),
];

final _kFavorites = ['/', '/products', '/purchases', '/customers', '/reports'];

// ══════════════════════════════════════════════════════════════
// ── APP SHELL ──
// ══════════════════════════════════════════════════════════════

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  String _selectedCategory = 'Todos';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  String? _hoveredPath;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final currentUser = ref.watch(currentUserProvider);

    // POS full screen
    if (currentRoute == '/') {
      return Scaffold(
        body: widget.child,
      );
    }

    // /home shows the module grid, all other routes show their content
    final isHome = currentRoute == '/home';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopNav(context, currentUser, currentRoute),
              if (!isHome)
                _buildBreadcrumb(context, currentRoute),
              Expanded(
                child: isHome
                    ? _buildHomeContent(context, currentUser)
                    : widget.child,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── BREADCRUMB BAR ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildBreadcrumb(BuildContext context, String currentRoute) {
    // Find the active module
    final module = _kModules.where((m) => currentRoute.startsWith(m.path) && m.path != '/').firstOrNull;
    final label = module?.label ?? currentRoute.replaceAll('/', ' ').trim();

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => context.go('/home'),
            child: Row(
              children: [
                const Icon(LucideIcons.home, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text('Inicio',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(LucideIcons.chevronRight, size: 14, color: Color(0xFFCBD5E1)),
          ),
          if (module != null)
            Icon(module.icon, size: 14, color: module.color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
          ),
          const Spacer(),
          // Back to home
          TextButton.icon(
            onPressed: () => context.go('/home'),
            icon: const Icon(LucideIcons.layoutGrid, size: 14),
            label: Text('Menú',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── TOP NAV BAR (SICAR-STYLE) ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildTopNav(BuildContext context, User? user, String currentRoute) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF2C5282), Color(0xFF3B6BA5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // ── Logo ──
          InkWell(
            onTap: () => context.go('/home'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.local_pharmacy_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'FarmaPos',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Category tabs ──
          ..._kCategories.map((cat) {
            final isActive = _selectedCategory == cat && currentRoute == '/home';
            return _navTab(
              label: cat,
              isActive: isActive,
              onTap: () {
                setState(() => _selectedCategory = cat);
                if (currentRoute != '/home') context.go('/home');
              },
            );
          }),

          const Spacer(),

          // ── Right actions ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.monitor, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Text('Caja 1',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),

          _topBarIcon(LucideIcons.cloud, 'Nube', () {}, badge: false),
          _topBarIcon(LucideIcons.bell, 'Notificaciones', () {}, badge: true),
          _topBarIcon(LucideIcons.info, 'Info', () {}),

          const SizedBox(width: 4),
          Container(width: 1, height: 28, color: Colors.white24),
          const SizedBox(width: 8),

          // User
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF60A5FA),
                    child: Text(
                      user?.fullName.substring(0, 1).toUpperCase() ?? '?',
                      style: GoogleFonts.inter(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    user?.username ?? 'admin',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                ],
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(currentUserProvider.notifier).state = null;
                context.go('/login');
              } else if (value == 'home') {
                context.go('/home');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'home',
                child: Row(
                  children: [
                    const Icon(LucideIcons.home, size: 16),
                    const SizedBox(width: 10),
                    const Text('Menú Principal'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(LucideIcons.user, size: 16),
                    const SizedBox(width: 10),
                    const Text('Mi Perfil'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(LucideIcons.logOut, size: 16, color: AppColors.error),
                    const SizedBox(width: 10),
                    const Text('Cerrar Sesión',
                        style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _navTab({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
          color: isActive ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
        ),
        height: 56,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _topBarIcon(IconData icon, String tooltip, VoidCallback onTap,
      {bool badge = false}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              if (badge)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ── HOME CONTENT (ICON GRID) ──
  // ══════════════════════════════════════════════════════════════
  Widget _buildHomeContent(BuildContext context, User? user) {
    final isAdmin = user?.role == 'admin';
    var modules = _kModules.where((m) {
      if (!isAdmin && (m.path == '/users' || m.path == '/branches' || m.path == '/employees')) {
        return false;
      }
      return true;
    }).toList();

    if (_selectedCategory != 'Todos') {
      modules = modules.where((m) => m.category == _selectedCategory).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      modules = modules.where((m) =>
          m.label.toLowerCase().contains(q) ||
          m.subtitle.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q)).toList();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Column(
        children: [
          _buildFavoritesRow(context),
          const SizedBox(height: 20),
          _buildSearchBar(),
          const SizedBox(height: 28),
          _buildModuleGrid(context, modules),
        ],
      ),
    );
  }

  Widget _buildFavoritesRow(BuildContext context) {
    final favModules = _kModules.where((m) => _kFavorites.contains(m.path)).toList();

    return Column(
      children: [
        Text(
          'Favoritos',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: favModules.map((m) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Tooltip(
                message: m.label,
                child: InkWell(
                  onTap: () => context.go(m.path),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: m.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: m.color.withValues(alpha: 0.15)),
                    ),
                    child: Icon(m.icon, size: 22, color: m.color),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Center(
      child: SizedBox(
        width: 460,
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Buscar módulo...',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF94A3B8)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                  items: ['Todos', ..._kCategories]
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v ?? 'Todos'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleGrid(BuildContext context, List<_ModuleDef> modules) {
    if (modules.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: [
            Icon(LucideIcons.searchX, size: 48, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(
              'No se encontraron módulos',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 24,
      runSpacing: 24,
      alignment: WrapAlignment.center,
      children: modules.map((m) => _moduleCard(context, m)).toList(),
    );
  }

  Widget _moduleCard(BuildContext context, _ModuleDef module) {
    final isHovered = _hoveredPath == module.path;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredPath = module.path),
      onExit: (_) => setState(() => _hoveredPath = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(module.path),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isHovered ? module.color.withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
              width: isHovered ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isHovered
                    ? module.color.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: isHovered ? 16 : 6,
                offset: Offset(0, isHovered ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: module.color.withValues(alpha: isHovered ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(module.icon, size: 26, color: module.color),
              ),
              const SizedBox(height: 10),
              Text(
                module.label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                module.subtitle,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: const Color(0xFF94A3B8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
