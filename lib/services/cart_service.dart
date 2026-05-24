import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

class CartService {
  static final CartService _instance = CartService._internal();
  final List<CartItem> _cartItems = [];
  String? _currentUserEmail;

  CartService._internal();
  factory CartService() => _instance;

  static String _cartKey(String email) => 'cart_$email';

  String? get currentUserEmail => _currentUserEmail;

  // ── Per-user loading ────────────────────────────────────────────────────────

  /// Load the saved cart for [email] from SharedPreferences.
  /// Call this right after a successful login.
  Future<void> loadForUser(String email) async {
    _currentUserEmail = email;
    _cartItems.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cartKey(email));
      if (raw == null) return;
      final list = json.decode(raw) as List<dynamic>;
      for (final item in list) {
        _cartItems.add(CartItem.fromJson(item as Map<String, dynamic>));
      }
      developer.log('[CartService] Loaded ${_cartItems.length} items for $email');
    } catch (e) {
      developer.log('[CartService] loadForUser error: $e — starting fresh');
      _cartItems.clear();
    }
  }

  /// Clear the in-memory cart without deleting SharedPreferences data.
  /// Call this on logout so the next login reloads the correct cart.
  void clearInMemory() {
    _cartItems.clear();
    _currentUserEmail = null;
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final email = _currentUserEmail;
    if (email == null) return;
    // Snapshot cart data synchronously before the first await so that a
    // concurrent clearInMemory() call cannot race and wipe the saved list.
    final data = _cartItems.map((i) => i.toJson()).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cartKey(email), json.encode(data));
    } catch (e) {
      developer.log('[CartService] _persist error: $e');
    }
  }

  // ── Cart operations ──────────────────────────────────────────────────────────

  List<CartItem> getCartItems() => _cartItems;

  void addToCart(Product product,
      {String? selectedSize, String? selectedColor}) {
    final newItem = CartItem(
      product: product,
      selectedSize: selectedSize,
      selectedColor: selectedColor,
    );
    final idx =
        _cartItems.indexWhere((item) => item.variantKey == newItem.variantKey);
    if (idx >= 0) {
      _cartItems[idx].quantity++;
    } else {
      _cartItems.add(newItem);
    }
    unawaited(_persist());
  }

  void removeFromCart(dynamic productId) {
    _cartItems.removeWhere((item) => item.product.id == productId);
    unawaited(_persist());
  }

  void removeByVariantKey(String key) {
    _cartItems.removeWhere((item) => item.variantKey == key);
    unawaited(_persist());
  }

  void updateQuantityByVariant(String key, int quantity) {
    final idx = _cartItems.indexWhere((item) => item.variantKey == key);
    if (idx < 0) return;
    if (quantity <= 0) {
      _cartItems.removeAt(idx);
    } else {
      _cartItems[idx].quantity = quantity;
    }
    unawaited(_persist());
  }

  void removeItems(List<String> variantKeys) {
    _cartItems.removeWhere((item) => variantKeys.contains(item.variantKey));
    unawaited(_persist());
  }

  void clearCart() {
    _cartItems.clear();
    unawaited(_persist());
  }

  /// Restores cached stock when an order is cancelled.
  void restoreProductStock(dynamic productId, int quantity) {
    bool changed = false;
    for (int i = 0; i < _cartItems.length; i++) {
      final item = _cartItems[i];
      if (item.product.id == productId ||
          item.product.id.toString() == productId.toString()) {
        _cartItems[i] = CartItem(
          product: item.product.copyWith(stock: item.product.stock + quantity),
          quantity: item.quantity,
          selectedSize: item.selectedSize,
          selectedColor: item.selectedColor,
        );
        changed = true;
      }
    }
    if (changed) unawaited(_persist());
  }

  /// Updates the cached stock for a product after an order is placed,
  /// so the cart immediately reflects the decremented value.
  void updateProductStock(dynamic productId, int decrementBy) {
    bool changed = false;
    for (int i = 0; i < _cartItems.length; i++) {
      final item = _cartItems[i];
      if (item.product.id == productId ||
          item.product.id.toString() == productId.toString()) {
        final newStock = (item.product.stock - decrementBy).clamp(0, item.product.stock);
        _cartItems[i] = CartItem(
          product: item.product.copyWith(stock: newStock),
          quantity: item.quantity,
          selectedSize: item.selectedSize,
          selectedColor: item.selectedColor,
        );
        changed = true;
      }
    }
    if (changed) unawaited(_persist());
  }

  int getCartCount() =>
      _cartItems.fold(0, (sum, item) => sum + item.quantity);

  double getTotalPrice() =>
      _cartItems.fold(0, (sum, item) => sum + item.getTotal());

  bool isInCart(int productId) =>
      _cartItems.any((item) => item.product.id == productId);
}
