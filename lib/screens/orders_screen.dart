import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/order_info.dart';
import '../models/product.dart';
import '../services/app_state.dart';
import '../services/store_repository.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.demoMode});

  final bool demoMode;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final StoreRepository _repository;
  late Future<List<Map<String, dynamic>>> _ordersFuture;
  StreamSubscription<void>? _orderSubscription;
  OrderStage? _filter;

  @override
  void initState() {
    super.initState();
    _repository = StoreRepository(demoMode: widget.demoMode);
    _ordersFuture = _repository.fetchOrders();
    AppState.instance.ordersVersion.addListener(_refresh);
    if (!widget.demoMode) {
      _orderSubscription = _repository.watchOrderChanges().listen(
        (_) => _refresh(),
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
    AppState.instance.ordersVersion.removeListener(_refresh);
    _orderSubscription?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _ordersFuture = _repository.fetchOrders());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your orders'),
        actions: [
          IconButton(
            tooltip: 'Refresh orders',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load your orders.'),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: mutedInk),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final orders = (snapshot.data ?? const <Map<String, dynamic>>[])
              .map(OrderInfo.fromMap)
              .toList();
          if (orders.isEmpty) return const _EmptyOrders();

          final visible = _filter == null
              ? orders
              : orders.where((order) => order.stage == _filter).toList();

          return Column(
            children: [
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _stageChip('All', null, orders.length),
                    for (final stage in OrderStage.values)
                      _stageChip(
                        stage.label,
                        stage,
                        orders.where((o) => o.stage == stage).length,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                'No orders in this list.',
                                style: TextStyle(color: mutedInk),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => _OrderCard(
                            order: visible[index],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderDetailScreen(
                                  order: visible[index],
                                  demoMode: widget.demoMode,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stageChip(String label, OrderStage? stage, int count) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(count > 0 && stage != null ? '$label ($count)' : label),
        selected: _filter == stage,
        onSelected: (_) => setState(() => _filter = stage),
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 54, color: mutedInk),
            const SizedBox(height: 12),
            Text(
              'No orders yet',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your DataBee purchases and payment status will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedInk),
            ),
          ],
        ),
      ),
    );
  }
}

Color stageColor(OrderStage stage) => switch (stage) {
  OrderStage.pendingConfirmation => Colors.orange.shade800,
  OrderStage.toShip => Colors.blue.shade700,
  OrderStage.readyForPickup => Colors.teal.shade700,
  OrderStage.outForDelivery => Colors.blue.shade700,
  OrderStage.delivered => Colors.green.shade700,
  OrderStage.cancelled => Colors.red.shade700,
};

IconData stageIcon(OrderStage stage) => switch (stage) {
  OrderStage.pendingConfirmation => Icons.schedule,
  OrderStage.toShip => Icons.inventory_2_outlined,
  OrderStage.readyForPickup => Icons.inventory_2,
  OrderStage.outForDelivery => Icons.local_shipping_outlined,
  OrderStage.delivered => Icons.check_circle,
  OrderStage.cancelled => Icons.cancel_outlined,
};

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final OrderInfo order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stage = order.stage;
    final created = order.createdAt;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(stageIcon(stage), color: stageColor(stage)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stage.label.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: stageColor(stage),
                      ),
                    ),
                  ),
                  if (created != null)
                    Text(
                      '${created.day}/${created.month}/${created.year}',
                      style: const TextStyle(color: mutedInk, fontSize: 12),
                    ),
                ],
              ),
              const Divider(height: 24),
              Text(
                order.productName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'Qty ${order.quantity}',
                    style: const TextStyle(color: mutedInk),
                  ),
                  const Spacer(),
                  Text(
                    formatPhp(order.amount),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                order.stageDescription,
                style: const TextStyle(color: mutedInk, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
