import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth/auth_service.dart';
import '../modules/auth/login_screen.dart';
import '../modules/dashboard/dashboard_screen.dart';
import '../modules/pos/pos_screen.dart';
import '../modules/products/products_screen.dart';
import '../modules/products/product_form_screen.dart';
import '../modules/inventory/inventory_screen.dart';
import '../modules/purchases/purchases_screen.dart';
import '../modules/purchases/supplier_screen.dart';
import '../modules/suppliers/suppliers_screen.dart';
import '../modules/cash_register/cash_register_screen.dart';
import '../modules/reports/reports_screen.dart';
import '../modules/users/users_screen.dart';
import '../modules/settings/settings_screen.dart';
import '../modules/customers/customers_screen.dart';
import '../modules/quotations/quotations_screen.dart';
import '../modules/promotions/promotions_screen.dart';
import '../modules/credit_notes/credit_notes_screen.dart';
import '../modules/branches/branches_screen.dart';
import '../modules/prescriptions/prescriptions_screen.dart';
import '../modules/employees/employees_screen.dart';
import '../modules/labels/labels_screen.dart';
import '../modules/invoicing/invoicing_screen.dart';
import '../shell/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);

  return GoRouter(
    initialLocation: isAuthenticated ? '/home' : '/login',
    redirect: (context, state) {
      final loggedIn = ref.read(isAuthenticatedProvider);
      final loggingIn = state.matchedLocation == '/login';

      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const SizedBox.shrink(), // Handled by AppShell
          ),
          GoRoute(
            path: '/',
            builder: (context, state) => const PosScreen(),
          ),
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const ProductFormScreen(),
              ),
              GoRoute(
                path: 'edit/:id',
                builder: (context, state) => ProductFormScreen(
                  productId: state.pathParameters['id'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const InventoryScreen(),
          ),
          GoRoute(
            path: '/suppliers',
            builder: (context, state) => const SuppliersScreen(),
          ),
          GoRoute(
            path: '/purchases',
            builder: (context, state) => const PurchasesScreen(),
            routes: [
              GoRoute(
                path: 'suppliers',
                builder: (context, state) => const SupplierScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/cash-register',
            builder: (context, state) => const CashRegisterScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/users',
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/customers',
            builder: (context, state) => const CustomersScreen(),
          ),
          GoRoute(
            path: '/quotations',
            builder: (context, state) => const QuotationsScreen(),
          ),
          GoRoute(
            path: '/promotions',
            builder: (context, state) => const PromotionsScreen(),
          ),
          GoRoute(
            path: '/credit-notes',
            builder: (context, state) => const CreditNotesScreen(),
          ),
          GoRoute(
            path: '/branches',
            builder: (context, state) => const BranchesScreen(),
          ),
          GoRoute(
            path: '/prescriptions',
            builder: (context, state) => const PrescriptionsScreen(),
          ),
          GoRoute(
            path: '/employees',
            builder: (context, state) => const EmployeesScreen(),
          ),
          GoRoute(
            path: '/labels',
            builder: (context, state) => const LabelsScreen(),
          ),
          GoRoute(
            path: '/invoicing',
            builder: (context, state) => const InvoicingScreen(),
          ),
        ],
      ),
    ],
  );
});
