import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/theme.dart';
import '../models/order_info.dart';
import '../models/product.dart';
import '../services/app_state.dart';
import '../services/store_repository.dart';
import 'orders_screen.dart';

enum OrderManagementMode { seller, rider }

class OrderManagementScreen extends StatefulWidget {
  const OrderManagementScreen({
    super.key,
    required this.demoMode,
    required this.mode,
  });

  final bool demoMode;
  final OrderManagementMode mode;

  @override
  State<OrderManagementScreen> createState() => _OrderManagementScreenState();
}

class _OrderManagementScreenState extends State<OrderManagementScreen> {
  late final StoreRepository _repository;
  late Future<List<Map<String, dynamic>>> _ordersFuture;
  StreamSubscription<void>? _orderSubscription;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = StoreRepository(demoMode: widget.demoMode);
    _ordersFuture = _repository.fetchOrders();
    AppState.instance.ordersVersion.addListener(_reload);
    if (!widget.demoMode) {
      _orderSubscription = _repository.watchOrderChanges().listen(
        (_) => _reload(),
        onError: (Object error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Live order updates stopped: $error')),
          );
        },
      );
    }
  }

  @override
  void dispose() {
    AppState.instance.ordersVersion.removeListener(_reload);
    _orderSubscription?.cancel();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _ordersFuture = _repository.fetchOrders());
  }

  Future<void> _act(OrderInfo order, String action) async {
    if (_busy) return;
    if (action == 'mark_delivered') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            widget.demoMode ? 'Confirm demo delivery?' : 'Confirm delivery?',
          ),
          content: Text(
            widget.demoMode
                ? 'This demo action marks the order as delivered and saves the delivery time.'
                : 'Confirm that this order was successfully delivered.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mark as Delivered'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      await _repository.transitionOrder(order.id, action);
      AppState.instance.refreshOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_successMessage(action))));
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update order: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _successMessage(String action) => switch (action) {
    'confirm' => 'Order confirmed.',
    'reject' => 'Order rejected.',
    'ready_for_pickup' => 'Order marked ready for pickup.',
    'accept_delivery' => 'Delivery accepted and assigned to this demo rider.',
    'mark_delivered' => 'Order marked as delivered.',
    _ => 'Order updated.',
  };

  Future<void> _confirmReject(OrderInfo order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject this order?'),
        content: const Text('This action cancels the pending order.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject order'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _act(order, 'reject');
  }

  @override
  Widget build(BuildContext context) {
    final seller = widget.mode == OrderManagementMode.seller;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          seller
              ? 'Seller order management'
              : widget.demoMode
              ? 'Demo Rider Dashboard'
              : 'Rider Dashboard',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh orders',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.demoMode)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                child: ListTile(
                  leading: Icon(Icons.science_outlined),
                  title: Text('Demonstration mode'),
                  subtitle: Text(
                    'Actions update locally saved demo orders; no real rider is contacted.',
                  ),
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Could not load orders for management.'),
                          const SizedBox(height: 8),
                          Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _reload,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final allOrders = (snapshot.data ?? const [])
                    .map(OrderInfo.fromMap)
                    .toList();
                final orders = seller
                    ? allOrders
                    : allOrders.where(_isRiderOrder).toList();
                if (orders.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        seller
                            ? 'No orders to manage yet.'
                            : 'No deliveries are available right now.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: mutedInk),
                      ),
                    ),
                  );
                }
                if (!seller) {
                  final active = orders
                      .where((order) => order.stage != OrderStage.delivered)
                      .toList();
                  final history = orders
                      .where((order) => order.stage == OrderStage.delivered)
                      .toList();
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (active.isNotEmpty) ...[
                          const _ListHeading('ACTIVE DELIVERIES'),
                          const SizedBox(height: 8),
                          for (final order in active) ...[
                            _managementCard(order),
                            const SizedBox(height: 10),
                          ],
                        ],
                        if (active.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'No active deliveries.',
                                style: TextStyle(color: mutedInk),
                              ),
                            ),
                          ),
                        if (history.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const _ListHeading('DELIVERY HISTORY'),
                          const SizedBox(height: 8),
                          for (final order in history) ...[
                            _managementCard(order),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return _managementCard(order);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _managementCard(OrderInfo order) => _ManagementOrderCard(
    order: order,
    mode: widget.mode,
    busy: _busy,
    onAction: (action) => _act(order, action),
    onReject: () => _confirmReject(order),
  );

  bool _isRiderOrder(OrderInfo order) =>
      order.stage == OrderStage.readyForPickup ||
      (order.riderId ==
              (widget.demoMode
                  ? StoreRepository.demoRiderId
                  : Supabase.instance.client.auth.currentUser?.id) &&
          (order.stage == OrderStage.outForDelivery ||
              order.stage == OrderStage.delivered));
}

class _ListHeading extends StatelessWidget {
  const _ListHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: mutedInk,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: .8,
    ),
  );
}

class _ManagementOrderCard extends StatelessWidget {
  const _ManagementOrderCard({
    required this.order,
    required this.mode,
    required this.busy,
    required this.onAction,
    required this.onReject,
  });

  final OrderInfo order;
  final OrderManagementMode mode;
  final bool busy;
  final ValueChanged<String> onAction;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final address = order.address ?? const <String, dynamic>{};
    final isSeller = mode == OrderManagementMode.seller;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(stageIcon(order.stage), color: stageColor(order.stage)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.stage.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: stageColor(order.stage),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Order ${order.id}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(order.productName),
            for (final item in order.items)
              Text(
                '${item.productName} · Qty ${item.quantity} · ${formatPhp(item.lineTotal)}',
                style: const TextStyle(color: mutedInk),
              ),
            Text(
              '${order.quantity} item(s) · ${order.paymentMethod.isEmpty ? order.paymentStatus : order.paymentMethod}',
              style: const TextStyle(color: mutedInk),
            ),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '${address['full_name'] ?? address['recipient_name'] ?? ''} · ${address['phone'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                [
                      address['street'],
                      address['barangay'],
                      address['city'],
                      address['province'],
                      address['postal_code'],
                    ]
                    .whereType<String>()
                    .where((part) => part.isNotEmpty)
                    .join(', '),
                style: const TextStyle(color: mutedInk),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '${formatPhp(order.amount)} due',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (order.riderId != null)
              Text(
                'Rider: ${order.riderId == StoreRepository.demoRiderId ? 'Demo rider' : order.riderId}',
                style: const TextStyle(color: mutedInk),
              ),
            if (order.deliveredAt != null)
              Text(
                'Delivered ${formatOrderDate(order.deliveredAt)}',
                style: const TextStyle(color: mutedInk),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (isSeller &&
                    order.stage == OrderStage.pendingConfirmation) ...[
                  FilledButton(
                    onPressed: busy ? null : () => onAction('confirm'),
                    child: const Text('Confirm'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : onReject,
                    child: const Text('Reject'),
                  ),
                ],
                if (isSeller && order.stage == OrderStage.toShip)
                  FilledButton(
                    onPressed: busy ? null : () => onAction('ready_for_pickup'),
                    child: const Text('Mark Ready for Pickup'),
                  ),
                if (!isSeller && order.stage == OrderStage.readyForPickup)
                  FilledButton(
                    onPressed: busy ? null : () => onAction('accept_delivery'),
                    child: const Text('Accept Delivery'),
                  ),
                if (!isSeller && order.stage == OrderStage.outForDelivery)
                  FilledButton.icon(
                    onPressed: busy ? null : () => onAction('mark_delivered'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Mark as Delivered'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
