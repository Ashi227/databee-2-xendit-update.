import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/delivery_address.dart';
import '../models/product.dart';
import '../services/app_state.dart';
import '../services/checkout_window.dart';
import '../services/store_repository.dart';
import 'addresses_screen.dart';
import 'cart_screen.dart';
import 'xendit_checkout_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.demoMode,
    required this.isFavorite,
    required this.onFavorite,
  });

  final Product product;
  final bool demoMode;
  final bool isFavorite;
  final VoidCallback onFavorite;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late final StoreRepository _repository;
  int _quantity = 1;
  bool _isCheckingOut = false;

  @override
  void initState() {
    super.initState();
    _repository = StoreRepository(demoMode: widget.demoMode);
  }

  Future<void> _addToCart() async {
    final product = widget.product;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final previous = List<CartItem>.of(AppState.instance.cart.value);
    final added = AppState.instance.addToCart(product, quantity: _quantity);
    messenger.hideCurrentSnackBar();
    if (added == 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'All ${product.stock} available units are already in your cart.',
          ),
        ),
      );
      return;
    }
    try {
      await _repository.saveCart(AppState.instance.cart.value);
    } catch (error) {
      AppState.instance.restoreCart(previous);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save your cart: $error')),
      );
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added < _quantity
              ? 'Added $added to cart (limited by available stock).'
              : 'Added to cart.',
        ),
        action: SnackBarAction(
          label: 'VIEW CART',
          onPressed: () => navigator.push(
            MaterialPageRoute(
              builder: (_) => CartScreen(demoMode: widget.demoMode),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _buyNow() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (widget.demoMode) {
      final previous = List<CartItem>.of(AppState.instance.cart.value);
      final added = AppState.instance.addToCart(
        widget.product,
        quantity: _quantity,
      );
      if (added == 0) {
        messenger.showSnackBar(
          const SnackBar(content: Text('This product is out of stock.')),
        );
        return;
      }
      try {
        await _repository.saveCart(AppState.instance.cart.value);
        if (!mounted) return;
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => CartScreen(demoMode: widget.demoMode),
          ),
        );
      } catch (error) {
        AppState.instance.restoreCart(previous);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save your cart: $error')),
        );
      }
      return;
    }

    late final DeliveryAddress deliveryAddress;
    try {
      final addresses = await _repository.fetchAddresses();
      final validAddresses = addresses
          .where((address) => address.isValid)
          .toList();
      if (validAddresses.isEmpty) {
        if (!mounted) return;
        final openAddresses = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delivery address required'),
            content: const Text(
              'Add a valid delivery address before placing your order.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add address'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (openAddresses == true) {
          await navigator.push(
            MaterialPageRoute(
              builder: (_) => AddressesScreen(demoMode: widget.demoMode),
            ),
          );
        }
        return;
      }
      deliveryAddress = validAddresses.firstWhere(
        (address) => address.isDefault,
        orElse: () => validAddresses.first,
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not validate your delivery address: $error'),
        ),
      );
      return;
    }

    final checkoutWindow = kIsWeb ? CheckoutWindow.open() : null;
    if (kIsWeb && checkoutWindow == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Allow pop-ups to open the secure Xendit checkout.'),
        ),
      );
      return;
    }

    setState(() => _isCheckingOut = true);
    try {
      final invoice = await _repository.createInvoice(
        widget.product,
        quantity: _quantity,
      );
      final invoiceUrl = invoice['invoice_url'] as String?;
      final externalId = invoice['external_id'] as String?;
      if (invoiceUrl == null || externalId == null) {
        throw const FormatException(
          'Invoice response is missing payment details.',
        );
      }
      final uri = Uri.tryParse(invoiceUrl);
      if (uri == null || uri.scheme != 'https') {
        throw const FormatException('Payment link is not a valid secure URL.');
      }
      await _repository.attachInvoiceDelivery(
        externalId: externalId,
        product: widget.product,
        quantity: _quantity,
        address: deliveryAddress,
      );

      if (!mounted) {
        checkoutWindow?.close();
        return;
      }
      checkoutWindow?.navigate(invoiceUrl);
      final checkoutStatus = await navigator.push<String>(
        MaterialPageRoute(
          builder: (_) => XenditCheckoutScreen(
            invoiceUrl: invoiceUrl,
            externalId: externalId,
          ),
        ),
      );
      if (!mounted) return;

      final status = checkoutStatus ?? await _waitForPayment(externalId);
      AppState.instance.refreshOrders();
      if (!mounted) return;
      final paid = status == 'PAID' || status == 'SETTLED';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            paid
                ? 'Payment confirmed. Your order is paid.'
                : 'Order status: $status. You can refresh Orders to check again.',
          ),
          backgroundColor: paid ? Colors.green.shade700 : null,
          duration: const Duration(seconds: 5),
        ),
      );
      if (paid) {
        checkoutWindow?.close();
        navigator.pop();
      }
    } catch (error) {
      checkoutWindow?.close();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not start checkout: $error')),
      );
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  Future<String> _waitForPayment(String externalId) async {
    var status = 'PENDING';
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      status = await _repository.orderStatus(externalId);
      if (status == 'PAID' ||
          status == 'SETTLED' ||
          status == 'EXPIRED' ||
          status == 'FAILED') {
        return status;
      }
    }
    return status;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Component details'),
        actions: [
          IconButton(
            tooltip: widget.isFavorite
                ? 'Remove from wishlist'
                : 'Add to wishlist',
            onPressed: widget.onFavorite,
            icon: Icon(
              widget.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: widget.isFavorite ? Colors.red : null,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: product.imageUrl.isEmpty
                ? Icon(categoryIcon(product.category), size: 88, color: ink)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.network(
                      product.imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.memory, size: 88),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          Text(
            '${product.brand.toUpperCase()}  /  ${product.category.toUpperCase()}',
            style: const TextStyle(
              color: mutedInk,
              letterSpacing: 1,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            product.name,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                formatPhp(product.price),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                product.stock > 0
                    ? '${product.stock} in stock'
                    : 'Out of stock',
                style: TextStyle(
                  color: product.stock > 0 ? Colors.green.shade700 : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                product.description.isEmpty
                    ? 'Product specifications and details will be updated soon.'
                    : product.description,
                style: const TextStyle(color: mutedInk, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Specifications',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Card(
            child: product.specs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No specifications available yet.',
                      style: TextStyle(color: mutedInk),
                    ),
                  )
                : Column(
                    children: product.specs.entries
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(color: mutedInk),
                                  ),
                                ),
                                Text(
                                  entry.value.toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              IconButton.outlined(
                onPressed: _quantity > 1
                    ? () => setState(() => _quantity--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '$_quantity',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton.outlined(
                onPressed: _quantity < product.stock
                    ? () => setState(() => _quantity++)
                    : null,
                icon: const Icon(Icons.add),
              ),
              const Spacer(),
              Text(
                formatPhp(product.price * _quantity),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCheckingOut || product.stock < 1
                    ? null
                    : _addToCart,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text(
                  'Add to cart',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isCheckingOut || product.stock < 1 ? null : _buyNow,
                icon: _isCheckingOut
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline),
                label: Text(
                  _isCheckingOut ? 'Preparing checkout...' : 'Buy now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
