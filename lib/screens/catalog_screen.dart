import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/product.dart';
import '../services/app_state.dart';
import '../services/store_repository.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.demoMode});

  final bool demoMode;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final StoreRepository _repository;
  final _searchController = TextEditingController();
  late Future<List<Product>> _productsFuture;
  final Set<String> _favoriteIds = {};
  String _category = 'All components';
  String _sort = 'Featured';
  double _maximumPrice = 150000;

  static const _categories = [
    'All components',
    'GPUs',
    'CPUs',
    'Motherboards',
    'Memory',
    'Storage',
    'Power Supplies',
  ];

  @override
  void initState() {
    super.initState();
    _repository = StoreRepository(demoMode: widget.demoMode);
    _productsFuture = _repository.fetchProducts();
    AppState.instance.favoriteIds.addListener(_onFavoritesChanged);
    AppState.instance.ordersVersion.addListener(_onOrdersUpdated);
    _loadFavorites();
  }

  @override
  void dispose() {
    AppState.instance.favoriteIds.removeListener(_onFavoritesChanged);
    AppState.instance.ordersVersion.removeListener(_onOrdersUpdated);
    _searchController.dispose();
    super.dispose();
  }

  // Keeps the hearts here in step when the wishlist changes elsewhere
  // (for example when an item is removed from the Wishlist screen).
  void _onFavoritesChanged() {
    if (!mounted) return;
    final ids = AppState.instance.favoriteIds.value;
    if (setEquals(ids, _favoriteIds)) return;
    setState(() {
      _favoriteIds
        ..clear()
        ..addAll(ids);
    });
  }

  Future<void> _loadFavorites() async {
    try {
      final ids = await _repository.fetchFavoriteIds();
      if (!mounted) return;
      setState(() => _favoriteIds.addAll(ids));
      AppState.instance.setFavorites(_favoriteIds);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load your wishlist: $error')),
      );
    }
  }

  Future<void> _toggleFavorite(Product product) async {
    final wasFavorite = _favoriteIds.contains(product.id);
    setState(() {
      if (wasFavorite) {
        _favoriteIds.remove(product.id);
      } else {
        _favoriteIds.add(product.id);
      }
    });
    AppState.instance.setFavorites(_favoriteIds);
    try {
      await _repository.setFavorite(product.id, !wasFavorite);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoriteIds.add(product.id);
        } else {
          _favoriteIds.remove(product.id);
        }
      });
      AppState.instance.setFavorites(_favoriteIds);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update wishlist: $error')),
      );
    }
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

  void _refreshProducts() {
    setState(() => _productsFuture = _repository.fetchProducts());
  }

  void _onOrdersUpdated() {
    if (!mounted) return;
    _refreshProducts();
  }

  List<Product> _filterProducts(List<Product> products) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = products.where((product) {
      final matchesCategory =
          _category == 'All components' || product.category == _category;
      final matchesQuery =
          query.isEmpty ||
          '${product.name} ${product.brand} ${product.category}'
              .toLowerCase()
              .contains(query);
      return matchesCategory && matchesQuery && product.price <= _maximumPrice;
    }).toList();

    switch (_sort) {
      case 'Price: low to high':
        filtered.sort((a, b) => a.price.compareTo(b.price));
      case 'Price: high to low':
        filtered.sort((a, b) => b.price.compareTo(a.price));
      case 'Name':
        filtered.sort((a, b) => a.name.compareTo(b.name));
      default:
        filtered.sort(
          (a, b) => (b.featured ? 1 : 0).compareTo(a.featured ? 1 : 0),
        );
    }
    return filtered;
  }

  Future<void> _showFilters() async {
    final result = await showModalBottomSheet<_FilterValues>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FilterSheet(
        selectedCategory: _category,
        selectedSort: _sort,
        maximumPrice: _maximumPrice,
        categories: _categories,
      ),
    );
    if (result != null) {
      setState(() {
        _category = result.category;
        _sort = result.sort;
        _maximumPrice = result.maximumPrice;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.memory, size: 24),
            SizedBox(width: 8),
            Text('DataBee', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          if (widget.demoMode)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  label: Text('DEMO'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ValueListenableBuilder<List<CartItem>>(
            valueListenable: AppState.instance.cart,
            builder: (context, items, _) {
              final count = items.fold<int>(
                0,
                (sum, item) => sum + item.quantity,
              );
              return IconButton(
                tooltip: 'Cart',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CartScreen(demoMode: widget.demoMode),
                  ),
                ),
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh catalog',
            onPressed: _refreshProducts,
            icon: const Icon(Icons.refresh),
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
            return _CatalogError(
              message: snapshot.error.toString(),
              onRetry: _refreshProducts,
            );
          }
          final allProducts = snapshot.data ?? const <Product>[];
          final products = _filterProducts(allProducts);

          return RefreshIndicator(
            onRefresh: () async => _refreshProducts(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Find the right parts for your next build.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: mutedInk),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  hintText: 'Search components',
                                  prefixIcon: Icon(Icons.search),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Filters and sorting',
                              onPressed: _showFilters,
                              icon: const Icon(Icons.tune),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _categories.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final category = _categories[index];
                              return ChoiceChip(
                                label: Text(category),
                                selected: category == _category,
                                onSelected: (_) =>
                                    setState(() => _category = category),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _category == 'All components'
                                    ? 'Components'
                                    : _category,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              '${products.length} items',
                              style: const TextStyle(color: mutedInk),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (products.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('No matching components.')),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return ProductCard(
                          product: product,
                          isFavorite: _favoriteIds.contains(product.id),
                          onFavorite: () => _toggleFavorite(product),
                          onAddToCart: () => _addToCart(product),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductDetailScreen(
                                product: product,
                                demoMode: widget.demoMode,
                                isFavorite: _favoriteIds.contains(product.id),
                                onFavorite: () => _toggleFavorite(product),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onFavorite,
    required this.onAddToCart,
    required this.onTap,
  });

  final Product product;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onAddToCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 80,
                height: 88,
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: product.imageUrl.isEmpty
                    ? Icon(categoryIcon(product.category), size: 38, color: ink)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          product.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.memory, size: 38),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${product.brand.toUpperCase()}  •  ${product.category.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: mutedInk,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatPhp(product.price),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.stock > 0
                          ? '${product.stock} in stock'
                          : 'Out of stock',
                      style: TextStyle(
                        color: product.stock > 0
                            ? Colors.green.shade700
                            : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onFavorite,
                    tooltip: isFavorite
                        ? 'Remove from wishlist'
                        : 'Add to wishlist',
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.red : mutedInk,
                    ),
                  ),
                  IconButton(
                    onPressed: product.stock > 0 ? onAddToCart : null,
                    tooltip: 'Add to cart',
                    icon: const Icon(Icons.add_shopping_cart),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Could not load components.'),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: mutedInk, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _FilterValues {
  const _FilterValues(this.category, this.sort, this.maximumPrice);

  final String category;
  final String sort;
  final double maximumPrice;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.selectedCategory,
    required this.selectedSort,
    required this.maximumPrice,
    required this.categories,
  });

  final String selectedCategory;
  final String selectedSort;
  final double maximumPrice;
  final List<String> categories;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _category = widget.selectedCategory;
  late String _sort = widget.selectedSort;
  late double _maximumPrice = widget.maximumPrice;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text(
              'Category',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: widget.categories
                  .map(
                    (category) => ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _sort,
              decoration: const InputDecoration(labelText: 'Sort by'),
              items:
                  const [
                        'Featured',
                        'Price: low to high',
                        'Price: high to low',
                        'Name',
                      ]
                      .map(
                        (sort) =>
                            DropdownMenuItem(value: sort, child: Text(sort)),
                      )
                      .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _sort = value);
              },
            ),
            const SizedBox(height: 12),
            Text('Maximum price: ${formatPhp(_maximumPrice)}'),
            Slider(
              value: _maximumPrice,
              min: 5000,
              max: 150000,
              divisions: 29,
              label: formatPhp(_maximumPrice),
              onChanged: (value) => setState(() => _maximumPrice = value),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _FilterValues(_category, _sort, _maximumPrice),
                ),
                child: const Text('Show components'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
