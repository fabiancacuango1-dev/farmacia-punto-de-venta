import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection/native.dart'
    if (dart.library.js_interop) 'connection/web.dart';

// Existing tables
import 'tables/users_table.dart';
import 'tables/products_table.dart';
import 'tables/categories_table.dart';
import 'tables/suppliers_table.dart';
import 'tables/sales_table.dart';
import 'tables/sale_items_table.dart';
import 'tables/product_batches_table.dart';
import 'tables/purchase_orders_table.dart';
import 'tables/purchase_order_items_table.dart';
import 'tables/cash_registers_table.dart';
import 'tables/cash_movements_table.dart';
import 'tables/inventory_movements_table.dart';
import 'tables/sync_log_table.dart';
import 'tables/audit_log_table.dart';
// New tables
import 'tables/customers_table.dart';
import 'tables/customer_credits_table.dart';
import 'tables/credit_payments_table.dart';
import 'tables/promotions_table.dart';
import 'tables/product_combos_table.dart';
import 'tables/prescriptions_table.dart';
import 'tables/quotations_table.dart';
import 'tables/credit_notes_table.dart';
import 'tables/branches_table.dart';
import 'tables/supplier_returns_table.dart';
import 'tables/loyalty_transactions_table.dart';
import 'tables/employee_tables.dart';
import 'tables/label_templates_table.dart';
import 'tables/extra_tables.dart';
import 'tables/inventory_counts_table.dart';
import 'tables/inventory_intelligence_table.dart';

// Existing DAOs
import 'daos/products_dao.dart';
import 'daos/sales_dao.dart';
import 'daos/inventory_dao.dart';
import 'daos/users_dao.dart';
import 'daos/cash_register_dao.dart';
import 'daos/purchases_dao.dart';
import 'daos/reports_dao.dart';
// New DAOs
import 'daos/customers_dao.dart';
import 'daos/promotions_dao.dart';
import 'daos/quotations_dao.dart';
import 'daos/credit_notes_dao.dart';
import 'daos/branches_dao.dart';
import 'daos/prescriptions_dao.dart';
import 'daos/employees_dao.dart';
import 'daos/invoices_dao.dart';

part 'app_database.g.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('Database must be initialized in main()');
});

@DriftDatabase(
  tables: [
    // Core
    Users,
    Products,
    Categories,
    Suppliers,
    Sales,
    SaleItems,
    ProductBatches,
    PurchaseOrders,
    PurchaseOrderItems,
    CashRegisters,
    CashMovements,
    InventoryMovements,
    SyncLog,
    AuditLog,
    // Customers & Loyalty
    Customers,
    CustomerCredits,
    CreditPayments,
    LoyaltyTransactions,
    // Promotions & Combos
    Promotions,
    ProductCombos,
    ComboItems,
    // Prescriptions
    Prescriptions,
    // Quotations
    Quotations,
    QuotationItems,
    // Credit Notes
    CreditNotes,
    CreditNoteItems,
    // Branches & Transfers
    Branches,
    BranchTransfers,
    BranchTransferItems,
    // Supplier Returns
    SupplierReturns,
    SupplierReturnItems,
    // Employee Management
    EmployeeAttendance,
    EmployeeActivities,
    // Labels
    LabelTemplates,
    // Extra
    SupplierPriceHistory,
    ProductSuggestions,
    BackupRecords,
    ElectronicInvoices,
    // Inventory Intelligence
    InventoryCounts,
    InventoryCountItems,
    StockAlerts,
    PurchaseSuggestions,
    InventorySnapshots,
    InventorySnapshotItems,
  ],
  daos: [
    ProductsDao,
    SalesDao,
    InventoryDao,
    UsersDao,
    CashRegisterDao,
    PurchasesDao,
    ReportsDao,
    CustomersDao,
    PromotionsDao,
    QuotationsDao,
    CreditNotesDao,
    BranchesDao,
    PrescriptionsDao,
    EmployeesDao,
    InvoicesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await _seedInitialData();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createAll();
        }
        if (from < 3) {
          // Add inventory intelligence tables for v3
          await m.createTable(inventoryCounts);
          await m.createTable(inventoryCountItems);
          await m.createTable(stockAlerts);
          await m.createTable(purchaseSuggestions);
          await m.createTable(inventorySnapshots);
          await m.createTable(inventorySnapshotItems);
        }
        if (from < 4) {
          // Add productName column to purchase_order_items
          await m.addColumn(purchaseOrderItems, purchaseOrderItems.productName);
        }
        if (from < 5) {
          // Add pharmacy-specific columns to products
          await m.addColumn(products, products.isControlled);
          await m.addColumn(products, products.adminRoute);
          await m.addColumn(products, products.saleType);
          await m.addColumn(products, products.storageCondition);
          await m.addColumn(products, products.storageNotes);
          await m.addColumn(products, products.registroSanitario);
          await m.addColumn(products, products.usesInventory);
        }
        if (from < 6) {
          // Add location tracking columns
          await m.addColumn(products, products.location);
          await m.addColumn(products, products.shelf);
        }
        if (from < 7) {
          // Add multi-price tiers and fractional selling columns
          await m.addColumn(products, products.price2);
          await m.addColumn(products, products.price3);
          await m.addColumn(products, products.unitsPerBox);
          await m.addColumn(products, products.costPerBox);
          await m.addColumn(products, products.allowFractions);
        }
      },
    );
  }

  Future<void> _seedInitialData() async {
    // Create default admin user (password: admin123)
    await into(users).insert(UsersCompanion.insert(
      id: 'usr_admin_001',
      username: 'admin',
      passwordHash: '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9',
      fullName: 'Administrador',
      role: const Value('admin'),
      isActive: const Value(true),
      createdAt: Value(DateTime.now()),
    ));

    // Create default categories
    final defaultCategories = [
      'Medicamentos',
      'Antibióticos',
      'Analgésicos',
      'Vitaminas y Suplementos',
      'Cuidado Personal',
      'Primeros Auxilios',
      'Bebés y Maternidad',
      'Equipos Médicos',
      'Otros',
    ];

    for (var i = 0; i < defaultCategories.length; i++) {
      await into(categories).insert(CategoriesCompanion.insert(
        id: 'cat_${i + 1}'.padLeft(10, '0'),
        name: defaultCategories[i],
        createdAt: Value(DateTime.now()),
      ));
    }

    // Create default main branch
    await into(branches).insert(BranchesCompanion.insert(
      id: 'branch_main_001',
      name: 'Sucursal Principal',
      isMain: const Value(true),
      isActive: const Value(true),
    ));

    // Create default label template
    await into(labelTemplates).insert(LabelTemplatesCompanion.insert(
      id: 'label_default_001',
      name: 'Etiqueta Estándar',
      isDefault: const Value(true),
    ));
  }
}
