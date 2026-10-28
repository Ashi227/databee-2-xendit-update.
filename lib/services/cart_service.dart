import 'package:flutter/foundation.dart';

import '../models/product.dart';

/// In-memory cart for the current app session. Connect this to an orders/cart
/// table when the team's backend schema is ready.
class CartService extends ChangeNotifier {
  CartService._();
  static final CartService instance = CartService._();

  final Map<String, _CartLine> _lines = {};
  List<CartLineView> get items => _lines.values
      .map((line) => CartLineView(product: line.product, quantity: line.quantity))
      .toList(growable: false);
  int get itemCount => _lines.values.fold(0, (sum, line) => sum + line.quantity);
  num get subtotal => _lines.values.fold<num>(
      0, (sum, line) => sum + line.product.price * line.quantity);

  void add(Product product, {int quantity = 1}) {
    if (quantity < 1 || product.stock < 1) return;
    final current = _lines[product.id];
    final nextQuantity = (current?.quantity ?? 0) + quantity;
    _lines[product.id] = _CartLine(
      product,
      nextQuantity > product.stock ? product.stock : nextQuantity,
    );
    notifyListeners();
  }

  void setQuantity(String productId, int quantity) {
    final line = _lines[productId];
    if (line == null) return;
    if (quantity < 1) {
      _lines.remove(productId);
    } else {
      line.quantity = quantity > line.product.stock ? line.product.stock : quantity;
    }
    notifyListeners();
  }

  void remove(String productId) {
    _lines.remove(productId);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}

class _CartLine {
  _CartLine(this.product, this.quantity);
  final Product product;
  int quantity;
}

class CartLineView {
  const CartLineView({required this.product, required this.quantity});
  final Product product;
  final int quantity;
}
