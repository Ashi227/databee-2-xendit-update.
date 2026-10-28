import 'package:flutter/foundation.dart';

import '../models/product.dart';

class CartItem {
  const CartItem({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  num get lineTotal => product.price * quantity;
}

/// Small shared state used by the cart and the wishlist counters.
class AppState {
  AppState._();

  static final AppState instance = AppState._();

  /// Product ids currently in the signed-in user's wishlist.
  final ValueNotifier<Set<String>> favoriteIds = ValueNotifier<Set<String>>(
    <String>{},
  );

  /// Items currently in the cart.
  final ValueNotifier<List<CartItem>> cart = ValueNotifier<List<CartItem>>(
    <CartItem>[],
  );

  /// Bumped whenever order data may have changed (after a purchase, or when
  /// the Orders / Account tabs are opened) so those screens reload.
  final ValueNotifier<int> ordersVersion = ValueNotifier<int>(0);

  void refreshOrders() => ordersVersion.value++;

  void setFavorites(Set<String> ids) {
    favoriteIds.value = Set<String>.of(ids);
  }

  void restoreCart(List<CartItem> items) {
    cart.value = List<CartItem>.of(items);
  }

  int get cartCount =>
      cart.value.fold<int>(0, (sum, item) => sum + item.quantity);

  int cartQuantityOf(String productId) {
    for (final item in cart.value) {
      if (item.product.id == productId) return item.quantity;
    }
    return 0;
  }

  /// Adds [quantity] of [product] to the cart without going over its stock.
  /// Returns how many units were actually added.
  int addToCart(Product product, {int quantity = 1}) {
    final existing = cartQuantityOf(product.id);
    final room = product.stock - existing;
    final toAdd = quantity < room ? quantity : room;
    if (toAdd <= 0) return 0;

    final items = List<CartItem>.of(cart.value);
    final index = items.indexWhere((item) => item.product.id == product.id);
    if (index == -1) {
      items.add(CartItem(product: product, quantity: toAdd));
    } else {
      items[index] = CartItem(
        product: items[index].product,
        quantity: items[index].quantity + toAdd,
      );
    }
    cart.value = items;
    return toAdd;
  }

  void setCartQuantity(String productId, int quantity) {
    final items = List<CartItem>.of(cart.value);
    final index = items.indexWhere((item) => item.product.id == productId);
    if (index == -1) return;
    if (quantity < 1 || items[index].product.stock < 1) {
      items.removeAt(index);
    } else {
      final stock = items[index].product.stock;
      items[index] = CartItem(
        product: items[index].product,
        quantity: quantity > stock ? stock : quantity,
      );
    }
    cart.value = items;
  }

  void removeFromCart(String productId) {
    cart.value = cart.value
        .where((item) => item.product.id != productId)
        .toList();
  }

  /// Clears everything. Called when the user signs out.
  void clear() {
    favoriteIds.value = <String>{};
    cart.value = <CartItem>[];
  }
}
