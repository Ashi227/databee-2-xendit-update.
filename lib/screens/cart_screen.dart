import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/product.dart';
import '../services/app_state.dart';
import '../services/store_repository.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key, required this.demoMode});

  final bool demoMode;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late final StoreRepository _repository;
  final _state = AppState.instance;

  @override
  void initState() {
    super.initState();
    _repository = StoreRepository(demoMode: widget.demoMode);
  }

  Future<void> _updateCart(void Function() update) async {
    final previous = List<CartItem>.of(_state.cart.value);
    update();
    try {
      await _repository.saveCart(_state.cart.value);
    } catch (error) {
      _state.restoreCart(previous);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save your cart: $error')),
      );
    }
  }

  Future<void> _checkout(List<CartItem> items) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          demoMode: widget.demoMode,
          items: List<CartItem>.of(items),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: ValueListenableBuilder<List<CartItem>>(
        valueListenable: _state.cart,
        builder: (context, items, _) {
          if (items.isEmpty) return const _EmptyCart();
          final total = items.fold<num>(0, (sum, item) => sum + item.lineTotal);
          final count = items.fold<int>(0, (sum, item) => sum + item.quantity);
          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _CartItemCard(
                      item: item,
                      onDecrease: () => _updateCart(
                        () => _state.setCartQuantity(
                          item.product.id,
                          item.quantity - 1,
                        ),
                      ),
                      onIncrease: () => _updateCart(
                        () => _state.setCartQuantity(
                          item.product.id,
                          item.quantity + 1,
                        ),
                      ),
                      onRemove: () => _updateCart(
                        () => _state.removeFromCart(item.product.id),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cart total ($count ${count == 1 ? 'item' : 'items'})',
                            style: const TextStyle(color: mutedInk),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatPhp(total),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => _checkout(items),
                      child: const Text('Checkout'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 54, color: mutedInk),
            const SizedBox(height: 12),
            Text(
              'Your cart is empty',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap "Add to cart" on a component to save it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedInk),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  final CartItem item;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 64,
                  height: 72,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: product.imageUrl.isEmpty
                      ? Icon(
                          categoryIcon(product.category),
                          size: 32,
                          color: ink,
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            product.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.memory, size: 32),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatPhp(product.price),
                        style: const TextStyle(
                          color: mutedInk,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove from cart',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: onDecrease,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${item.quantity}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton.outlined(
                  onPressed: item.quantity >= product.stock ? null : onIncrease,
                  icon: const Icon(Icons.add),
                ),
                const Spacer(),
                Text(
                  formatPhp(item.lineTotal),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
