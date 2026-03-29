import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';

// ══════════════════════════════════════════════════════
// SEARCH
// ══════════════════════════════════════════════════════

final searchQueryProvider = StateProvider<String>((ref) => '');

final productSearchProvider = FutureProvider<List<Product>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final db = ref.watch(appDatabaseProvider);

  if (query.isEmpty) return [];
  if (query.length < 2) return [];

  return db.productsDao.searchProducts(query);
});

// ══════════════════════════════════════════════════════
// SELECTED CUSTOMER
// ══════════════════════════════════════════════════════

final selectedCustomerProvider = StateProvider<Customer?>((ref) => null);

// ══════════════════════════════════════════════════════
// SELECTED SELLER (vendedor)
// ══════════════════════════════════════════════════════

final selectedSellerProvider = StateProvider<User?>((ref) => null);

// ══════════════════════════════════════════════════════
// ACTIVE CASH REGISTER
// ══════════════════════════════════════════════════════

final activeCashRegisterProvider = StateProvider<String?>((ref) => 'Caja 1');

// ══════════════════════════════════════════════════════
// CART ITEM MODEL
// ══════════════════════════════════════════════════════

enum PriceLevel { regular, wholesale, custom }

class CartItem {
  final Product product;
  final double quantity;
  final double discount; // per-item discount (amount)
  final double discountPercent; // per-item discount (%)
  final PriceLevel priceLevel;
  final double? customPrice;
  final String? tempDescription; // temporary description override
  final String? batchNumber;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.discount = 0,
    this.discountPercent = 0,
    this.priceLevel = PriceLevel.regular,
    this.customPrice,
    this.tempDescription,
    this.batchNumber,
  });

  double get effectivePrice {
    switch (priceLevel) {
      case PriceLevel.wholesale:
        return product.wholesalePrice ?? product.salePrice;
      case PriceLevel.custom:
        return customPrice ?? product.salePrice;
      case PriceLevel.regular:
        return product.salePrice;
    }
  }

  String get displayName => tempDescription ?? product.name;

  double get lineTotal => effectivePrice * quantity;

  double get discountAmount {
    if (discountPercent > 0) return lineTotal * (discountPercent / 100);
    return discount;
  }

  double get subtotal => lineTotal - discountAmount;

  double get taxAmount =>
      product.isTaxExempt ? 0 : subtotal * (product.taxRate / 100);

  double get total => subtotal + taxAmount;

  CartItem copyWith({
    double? quantity,
    double? discount,
    double? discountPercent,
    PriceLevel? priceLevel,
    double? customPrice,
    String? tempDescription,
    String? batchNumber,
  }) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      discount: discount ?? this.discount,
      discountPercent: discountPercent ?? this.discountPercent,
      priceLevel: priceLevel ?? this.priceLevel,
      customPrice: customPrice ?? this.customPrice,
      tempDescription: tempDescription ?? this.tempDescription,
      batchNumber: batchNumber ?? this.batchNumber,
    );
  }
}

// ══════════════════════════════════════════════════════
// CART NOTIFIER
// ══════════════════════════════════════════════════════

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addItem(Product product, {double quantity = 1}) {
    final existingIndex =
        state.indexWhere((item) => item.product.id == product.id);

    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      final newQty = existing.quantity + quantity;
      if (newQty > product.currentStock) return;

      state = [
        ...state.sublist(0, existingIndex),
        existing.copyWith(quantity: newQty),
        ...state.sublist(existingIndex + 1),
      ];
    } else {
      if (quantity > product.currentStock) return;
      state = [...state, CartItem(product: product, quantity: quantity)];
    }
  }

  void removeItem(String productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  void updateQuantity(String productId, double quantity) {
    if (quantity <= 0) {
      removeItem(productId);
      return;
    }
    state = state.map((item) {
      if (item.product.id == productId) {
        return item.copyWith(quantity: quantity);
      }
      return item;
    }).toList();
  }

  void applyDiscount(String productId, double discount) {
    state = state.map((item) {
      if (item.product.id == productId) {
        return item.copyWith(discount: discount, discountPercent: 0);
      }
      return item;
    }).toList();
  }

  void applyDiscountPercent(String productId, double percent) {
    state = state.map((item) {
      if (item.product.id == productId) {
        return item.copyWith(discountPercent: percent, discount: 0);
      }
      return item;
    }).toList();
  }

  void applyGlobalDiscount(double percent) {
    state = state
        .map((item) => item.copyWith(discountPercent: percent, discount: 0))
        .toList();
  }

  void setPriceLevel(String productId, PriceLevel level,
      {double? customPrice}) {
    state = state.map((item) {
      if (item.product.id == productId) {
        return item.copyWith(priceLevel: level, customPrice: customPrice);
      }
      return item;
    }).toList();
  }

  void setTempDescription(String productId, String description) {
    state = state.map((item) {
      if (item.product.id == productId) {
        return item.copyWith(tempDescription: description);
      }
      return item;
    }).toList();
  }

  void clearCart() {
    state = [];
  }

  List<CartItem> get items => state;
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

// ══════════════════════════════════════════════════════
// SELECTED ITEM INDEX (for toolbar operations)
// ══════════════════════════════════════════════════════

final selectedCartIndexProvider = StateProvider<int?>((ref) => null);

// ══════════════════════════════════════════════════════
// DOCUMENT TYPE
// ══════════════════════════════════════════════════════

enum DocumentType { ticket, invoice, saleNote, remission }

final documentTypeProvider =
    StateProvider<DocumentType>((ref) => DocumentType.ticket);

// ══════════════════════════════════════════════════════
// HELD / ON-HOLD SALES
// ══════════════════════════════════════════════════════

class HeldSale {
  final String id;
  final String label;
  final List<CartItem> items;
  final Customer? customer;
  final DocumentType docType;
  final DateTime heldAt;

  HeldSale({
    required this.id,
    required this.label,
    required this.items,
    this.customer,
    required this.docType,
    required this.heldAt,
  });

  double get total => items.fold<double>(0, (s, i) => s + i.total);
}

class HeldSalesNotifier extends StateNotifier<List<HeldSale>> {
  HeldSalesNotifier() : super([]);

  void holdSale(HeldSale sale) {
    state = [...state, sale];
  }

  HeldSale? recoverSale(String id) {
    final sale = state.firstWhere((s) => s.id == id);
    state = state.where((s) => s.id != id).toList();
    return sale;
  }

  void removeSale(String id) {
    state = state.where((s) => s.id != id).toList();
  }
}

final heldSalesProvider =
    StateNotifierProvider<HeldSalesNotifier, List<HeldSale>>((ref) {
  return HeldSalesNotifier();
});
