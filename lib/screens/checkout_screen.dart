import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/delivery_address.dart';
import '../models/product.dart';
import '../services/app_state.dart';
import '../services/checkout_window.dart';
import '../services/store_repository.dart';
import 'addresses_screen.dart';
import 'xendit_checkout_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.demoMode,
    required this.items,
  });

  final bool demoMode;
  final List<CartItem> items;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const _deliveryFee = 150;

  late final StoreRepository _repository;
  late Future<List<DeliveryAddress>> _addressesFuture;
  DeliveryAddress? _selectedAddress;
  bool _placingOrder = false;
  late String _checkoutKey;
  String _paymentMethod = 'COD';

  String _newCheckoutKey() => DateTime.now().microsecondsSinceEpoch.toString();

  num get _subtotal =>
      widget.items.fold<num>(0, (total, item) => total + item.lineTotal);

  @override
  void initState() {
    super.initState();
    _checkoutKey = _newCheckoutKey();
    _repository = StoreRepository(demoMode: widget.demoMode);
    _addressesFuture = _loadAddresses();
  }

  Future<List<DeliveryAddress>> _loadAddresses() async {
    final addresses = await _repository.fetchAddresses();
    final validAddresses = addresses
        .where((address) => address.isValid)
        .toList();
    if (_selectedAddress == null && validAddresses.isNotEmpty) {
      _selectedAddress = validAddresses.firstWhere(
        (address) => address.isDefault,
        orElse: () => validAddresses.first,
      );
    } else if (_selectedAddress != null) {
      final selectedId = _selectedAddress!.id;
      final matching = validAddresses.where(
        (address) => address.id == selectedId,
      );
      _selectedAddress = matching.isEmpty ? null : matching.first;
    }
    return addresses;
  }

  Future<void> _openAddresses() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddressesScreen(demoMode: widget.demoMode),
      ),
    );
    if (mounted) {
      setState(() => _addressesFuture = _loadAddresses());
    }
  }

  Future<void> _placeOrder() async {
    final address = _selectedAddress;
    if (address == null || !address.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add and select a valid delivery address to continue.'),
        ),
      );
      return;
    }
    if (_placingOrder) return;

    setState(() => _placingOrder = true);
    try {
      if (_paymentMethod == 'XENDIT') {
        await _payWithXendit(address);
        return;
      }

      final orderId = await _repository.createCodOrder(
        items: widget.items,
        address: address,
        checkoutKey: _checkoutKey,
        deliveryFee: _deliveryFee,
      );
      final purchasedIds = widget.items.map((item) => item.product.id).toSet();
      final remaining = AppState.instance.cart.value
          .where((item) => !purchasedIds.contains(item.product.id))
          .toList();
      AppState.instance.restoreCart(remaining);
      AppState.instance.refreshOrders();

      String? cartSaveError;
      try {
        await _repository.saveCart(remaining);
      } catch (error) {
        cartSaveError = error.toString();
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
          title: const Text('Order placed'),
          content: Text(
            cartSaveError == null
                ? widget.demoMode
                      ? 'Demo COD order $orderId was saved locally. No payment was collected. Simulated amount due: ${formatPhp(_subtotal + _deliveryFee)}.'
                      : 'Your COD order $orderId has been recorded. Amount due on delivery: ${formatPhp(_subtotal + _deliveryFee)}.'
                : 'Order $orderId was recorded, but the cart could not be synchronized: $cartSaveError',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not place your order: $error')),
      );
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  Future<void> _payWithXendit(DeliveryAddress address) async {
    final checkoutWindow = kIsWeb ? CheckoutWindow.open() : null;
    if (kIsWeb && checkoutWindow == null) {
      throw StateError('Allow pop-ups to open the secure Xendit payment page.');
    }

    try {
      final invoice = await _repository.createInvoiceForItems(
        items: widget.items,
        address: address,
        checkoutKey: _checkoutKey,
        deliveryFee: _deliveryFee,
      );
      final invoiceUrl = invoice['invoice_url'] as String?;
      final externalId = invoice['external_id'] as String?;
      final uri = Uri.tryParse(invoiceUrl ?? '');
      if (invoiceUrl == null ||
          externalId == null ||
          uri == null ||
          uri.scheme != 'https') {
        throw const FormatException(
          'Xendit returned an invalid invoice URL or reference.',
        );
      }

      if (!mounted) {
        checkoutWindow?.close();
        return;
      }
      checkoutWindow?.navigate(invoiceUrl);
      final status = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => XenditCheckoutScreen(
            invoiceUrl: invoiceUrl,
            externalId: externalId,
          ),
        ),
      );
      checkoutWindow?.close();
      if (!mounted) return;

      if (status != 'PAID' && status != 'SETTLED') {
        if (status == 'EXPIRED' || status == 'FAILED') {
          _checkoutKey = _newCheckoutKey();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == null
                  ? 'Payment was not confirmed. Your cart is unchanged.'
                  : 'Xendit payment status: $status. Your cart is unchanged.',
            ),
          ),
        );
        return;
      }

      final purchasedIds = widget.items.map((item) => item.product.id).toSet();
      final remaining = AppState.instance.cart.value
          .where((item) => !purchasedIds.contains(item.product.id))
          .toList();
      AppState.instance
        ..restoreCart(remaining)
        ..refreshOrders();

      String? cartError;
      try {
        await _repository.saveCart(remaining);
      } catch (error) {
        cartError = error.toString();
      }
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
          title: const Text('Payment confirmed'),
          content: Text(
            cartError == null
                ? 'Xendit confirmed payment for order $externalId.'
                : 'Xendit confirmed order $externalId, but the cart could not be synchronized: $cartError',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      checkoutWindow?.close();
      rethrow;
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _subtotal + _deliveryFee;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (widget.demoMode) ...[
            const Card(
              child: ListTile(
                leading: Icon(Icons.science_outlined),
                title: Text('Demo checkout'),
                subtitle: Text(
                  'Orders and delivery actions are simulated locally. No payment is collected.',
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const _SectionLabel('ITEMS'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var index = 0; index < widget.items.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      widget.items[index].product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('Qty ${widget.items[index].quantity}'),
                    trailing: Text(
                      formatPhp(widget.items[index].lineTotal),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('DELIVERY ADDRESS'),
          const SizedBox(height: 8),
          FutureBuilder<List<DeliveryAddress>>(
            future: _addressesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    title: const Text('Could not load delivery addresses.'),
                    subtitle: Text(snapshot.error.toString()),
                    trailing: IconButton(
                      tooltip: 'Retry',
                      onPressed: () =>
                          setState(() => _addressesFuture = _loadAddresses()),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                );
              }
              final addresses = (snapshot.data ?? const <DeliveryAddress>[])
                  .where((address) => address.isValid)
                  .toList();
              if (addresses.isEmpty) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.location_off_outlined),
                    title: const Text('A valid address is required'),
                    subtitle: const Text(
                      'Add a recipient, phone number, and complete address before ordering.',
                    ),
                    trailing: TextButton(
                      onPressed: _openAddresses,
                      child: const Text('Add'),
                    ),
                  ),
                );
              }
              return Card(
                child: RadioGroup<String>(
                  groupValue: _selectedAddress?.id,
                  onChanged: (id) {
                    if (_placingOrder || id == null) return;
                    setState(
                      () => _selectedAddress = addresses.firstWhere(
                        (a) => a.id == id,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < addresses.length;
                        index++
                      ) ...[
                        if (index > 0) const Divider(height: 1),
                        RadioListTile<String>(
                          value: addresses[index].id,
                          title: Text(
                            '${addresses[index].label} · ${addresses[index].fullName}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${addresses[index].phone}\n${addresses[index].fullAddress}',
                          ),
                        ),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _placingOrder ? null : _openAddresses,
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          label: const Text('Manage addresses'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const _SectionLabel('PAYMENT METHOD'),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<String>(
              groupValue: _paymentMethod,
              onChanged: (value) {
                if (_placingOrder || value == null) return;
                setState(() => _paymentMethod = value);
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'COD',
                    title: const Text('Cash on Delivery'),
                    subtitle: Text(
                      widget.demoMode
                          ? 'Demo COD simulation; no payment is collected.'
                          : 'Pay when your order arrives.',
                    ),
                    secondary: const Icon(Icons.payments_outlined),
                  ),
                  if (widget.demoMode)
                    const ListTile(
                      leading: Icon(Icons.open_in_new),
                      title: Text('Xendit'),
                      subtitle: Text(
                        'Run with your Supabase project and configure an Xendit test key to use online checkout.',
                      ),
                    )
                  else
                    const RadioListTile<String>(
                      value: 'XENDIT',
                      title: Text('Xendit'),
                      subtitle: Text(
                        'Secure online payment. Test or live mode is controlled by your server key.',
                      ),
                      secondary: Icon(Icons.lock_outline),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('PAYMENT SUMMARY'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _TotalRow('Product subtotal', _subtotal),
                  const SizedBox(height: 8),
                  _TotalRow('Delivery fee', _deliveryFee),
                  const Divider(height: 24),
                  _TotalRow('Amount due', total, isTotal: true),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _placingOrder ? null : _placeOrder,
          icon: _placingOrder
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(
            _placingOrder
                ? _paymentMethod == 'XENDIT'
                      ? 'Opening Xendit...'
                      : 'Placing order...'
                : _paymentMethod == 'XENDIT'
                ? 'Pay with Xendit'
                : 'Place COD order',
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: mutedInk,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: .8,
    ),
  );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.amount, {this.isTotal = false});

  final String label;
  final num amount;
  final bool isTotal;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: isTotal ? null : mutedInk,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.normal,
          ),
        ),
      ),
      Text(
        formatPhp(amount),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: isTotal ? 18 : null,
        ),
      ),
    ],
  );
}
