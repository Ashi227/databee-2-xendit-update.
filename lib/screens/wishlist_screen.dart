import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/product.dart';
import '../services/app_state.dart';
import '../services/store_repository.dart';
import 'catalog_screen.dart';
import 'product_detail_screen.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key, required this.demoMode});

  final bool demoMode;

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  late final StoreRepository _repository;
  late Future<List<Product>> _productsFuture;
  final _itemCount = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _repository = StoreRepository(demoMode: widget.demoMode);
    _productsFuture = _loadWishlist();
  }

  @override
  void dispose() {
    _itemCount.dispose();
    super.dispose();
  }

  Future<List<Product>> _loadWishlist() async {
    final favoriteIds = await _repository.fetchFavoriteIds();
    final products = await _repository.fetchProducts();
    final wishlist = products
        .where((product) => favoriteIds.contains(product.id))
        .toList();
    if (mounted) _itemCount.value = wishlist.length;
    return wishlist;
  }

  Future<void> _addToCart(Product product) async {
    final previous = List<CartItem>.of(AppState.instance.cart.value);
    final added = AppState.instance.addToCart(product);
    if (added == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} is out of stock.')),
      );
      return;
    }
    try {
      await _repository.saveCart(AppState.instance.cart.value);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Added to cart.')));
    } catch (error) {
      AppState.instance.restoreCart(previous);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save your cart: $error')),
      );
    }
  }

  void _refresh() {
    setState(() => _productsFuture = _loadWishlist());
  }

  Future<void> _removeFavorite(Product product) async {
    try {
      await _repository.setFavorite(product.id, false);
      AppState.instance.setFavorites(
        AppState.instance.favoriteIds.value.difference({product.id}),
      );
      if (mounted) _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update wishlist: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wishlist'),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: _itemCount,
            builder: (context, count, _) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$count ${count == 1 ? 'item' : 'items'}',
                  style: const TextStyle(color: mutedInk),
                ),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load your wishlist.'),
                  const SizedBox(height: 8),
                  Text(snapshot.error.toString()),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final products = snapshot.data ?? const <Product>[];
          if (products.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border, size: 52),
                    SizedBox(height: 12),
                    Text('Your wishlist is empty.'),
                    SizedBox(height: 6),
                    Text(
                      'Tap the heart beside a component to save it here.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final product = products[index];
                return ProductCard(
                  product: product,
                  isFavorite: true,
                  onFavorite: () => _removeFavorite(product),
                  onAddToCart: () => _addToCart(product),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(
                        product: product,
                        demoMode: widget.demoMode,
                        isFavorite: true,
                        onFavorite: () => _removeFavorite(product),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
