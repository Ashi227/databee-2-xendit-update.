import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/order_info.dart';
import '../models/product.dart';
import '../services/app_state.dart';
import '../services/store_repository.dart';
import 'cart_screen.dart';
import 'orders_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.order,
    required this.demoMode,
  });

  final OrderInfo order;
  final bool demoMode;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _busy = false;

  bool get _canCancelOrder =>
      widget.order.stage == OrderStage.pendingConfirmation &&
      widget.order.paymentMethod.toUpperCase() == 'COD';

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
          'You can cancel while the order is waiting for seller confirmation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true || _busy) return;

    setState(() => _busy = true);
    try {
      await StoreRepository(demoMode: widget.demoMode)
          .transitionOrder(widget.order.id, 'cancel');
      AppState.instance.refreshOrders();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel your order: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buyAgain() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final order = widget.order;
    final previous = List<CartItem>.of(AppState.instance.cart.value);
    setState(() => _busy = true);
    try {
      final repository = StoreRepository(demoMode: widget.demoMode);
      final products = await repository.fetchProducts();
      final lines = order.items.isEmpty
          ? [
              OrderLineInfo(
                productName: order.productName,
                productId: order.productId,
                quantity: order.quantity,
                unitPrice: order.amount,
              ),
            ]
          : order.items;
      var added = 0;
      for (final line in lines) {
        Product? match;
        for (final product in products) {
          if ((line.productId != null && product.id == line.productId) ||
              product.name == line.productName) {
            match = product;
            break;
          }
        }
        if (match == null) {
          throw StateError('${line.productName} is no longer available.');
        }
        added += AppState.instance.addToCart(match, quantity: line.quantity);
      }
      await repository.saveCart(AppState.instance.cart.value);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            added == 0
                ? 'This item is out of stock or already maxed in your cart.'
                : added < order.quantity
                ? 'Some items could not be added because of current stock.'
                : 'Added to cart.',
          ),
          action: added == 0
              ? null
              : SnackBarAction(
                  label: 'VIEW CART',
                  onPressed: () => navigator.push(
                    MaterialPageRoute(
                      builder: (_) => CartScreen(demoMode: widget.demoMode),
                    ),
                  ),
                ),
        ),
      );
    } catch (error) {
      AppState.instance.restoreCart(previous);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add to cart: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final stage = order.stage;
    return Scaffold(
      appBar: AppBar(title: const Text('Order details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(stageIcon(stage), color: stageColor(stage), size: 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stage.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: stageColor(stage),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.stageDescription,
                          style: const TextStyle(color: mutedInk, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('DELIVERY PROGRESS'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: _timeline(order)),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('ITEM'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (order.items.isEmpty)
                    _OrderItemRow(
                      name: order.productName,
                      quantity: order.quantity,
                      unitPrice: order.quantity == 0
                          ? order.amount
                          : order.amount / order.quantity,
                    )
                  else
                    for (final item in order.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _OrderItemRow(
                          name: item.productName,
                          quantity: item.quantity,
                          unitPrice: item.unitPrice,
                        ),
                      ),
                  if (order.deliveryFee > 0) ...[
                    const Divider(height: 20),
                    _InfoRow('Product subtotal', formatPhp(order.subtotal)),
                    _InfoRow('Delivery fee', formatPhp(order.deliveryFee)),
                  ],
                  const Divider(height: 20),
                  _InfoRow('Total', formatPhp(order.amount)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('ORDER INFO'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _InfoRow('Order ID', order.id),
                  _InfoRow('Placed on', formatOrderDate(order.createdAt)),
                  _InfoRow(
                    'Payment',
                    order.paymentMethod.isEmpty
                        ? order.paymentStatus
                        : '${order.paymentMethod} · ${order.paymentStatus}',
                  ),
                  if (order.riderId != null)
                    _InfoRow(
                      'Assigned rider',
                      order.riderId == StoreRepository.demoRiderId
                          ? 'Demo rider'
                          : order.riderId!,
                    ),
                  if (order.trackingNumber != null)
                    _InfoRow('Tracking no.', order.trackingNumber!),
                ],
              ),
            ),
          ),
          if (order.address != null) ...[
            const SizedBox(height: 16),
            const _SectionLabel('DELIVERY ADDRESS'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.address?['full_name']?.toString() ??
                          order.address?['recipient_name']?.toString() ??
                          '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(order.address?['phone']?.toString() ?? ''),
                    const SizedBox(height: 4),
                    Text(
                      [
                            order.address?['street'],
                            order.address?['barangay'],
                            order.address?['city'],
                            order.address?['province'],
                            order.address?['postal_code'],
                          ]
                          .whereType<String>()
                          .where((part) => part.trim().isNotEmpty)
                          .join(', '),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canCancelOrder) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _cancelOrder,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel order'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _buyAgain,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_shopping_cart),
              label: const Text('Buy again'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _timeline(OrderInfo order) {
    final stage = order.stage;
    final cancelled = stage == OrderStage.cancelled;

    final steps = <_Step>[
      _Step('Order placed', formatOrderDate(order.createdAt), true),
      if (cancelled)
        _Step(
          'Order cancelled',
          [
            order.stageDescription,
            formatOrderDate(order.cancelledAt),
          ].where((value) => value.isNotEmpty).join(' · '),
          true,
          isBad: true,
        )
      else ...[
        _Step(
          'Seller confirmed',
          formatOrderDate(order.confirmedAt),
          order.confirmedAt != null,
        ),
        _Step(
          'Ready for pickup',
          formatOrderDate(order.readyForPickupAt),
          order.readyForPickupAt != null,
        ),
        _Step(
          'Out for delivery',
          formatOrderDate(order.outForDeliveryAt ?? order.shippedAt),
          order.outForDeliveryAt != null || order.shippedAt != null,
        ),
        _Step(
          'Delivered',
          formatOrderDate(order.deliveredAt),
          stage == OrderStage.delivered,
        ),
      ],
    ];

    return [
      for (var i = 0; i < steps.length; i++)
        _TimelineRow(step: steps[i], isLast: i == steps.length - 1),
    ];
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  final String name;
  final int quantity;
  final num unitPrice;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Qty $quantity · ${formatPhp(unitPrice)} each'),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Text(
        formatPhp(unitPrice * quantity),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _Step {
  const _Step(this.title, this.subtitle, this.reached, {this.isBad = false});

  final String title;
  final String subtitle;
  final bool reached;
  final bool isBad;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.isLast});

  final _Step step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = step.isBad
        ? Colors.red.shade700
        : step.reached
        ? Colors.green.shade700
        : mutedInk.withValues(alpha: .5);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(
                  step.isBad
                      ? Icons.cancel
                      : step.reached
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 22,
                  color: color,
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: step.reached || step.isBad ? ink : mutedInk,
                    ),
                  ),
                  if (step.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      step.subtitle,
                      style: const TextStyle(color: mutedInk, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: mutedInk)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: mutedInk,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
      ),
    );
  }
}
