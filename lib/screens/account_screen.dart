import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/theme.dart';
import '../services/app_state.dart';
import '../services/store_repository.dart';
import 'addresses_screen.dart';
import 'cart_screen.dart';
import 'order_management_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import 'wishlist_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.demoMode,
    required this.onOrders,
  });

  final bool demoMode;
  final VoidCallback onOrders;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final StoreRepository _repository;
  late Future<int> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _repository = StoreRepository(demoMode: widget.demoMode);
    _summaryFuture = _loadSummary();
    AppState.instance.ordersVersion.addListener(_reloadSummary);
  }

  @override
  void dispose() {
    AppState.instance.ordersVersion.removeListener(_reloadSummary);
    super.dispose();
  }

  void _reloadSummary() {
    if (!mounted) return;
    setState(() => _summaryFuture = _loadSummary());
  }

  // Only the order count is loaded here. The wishlist count comes from
  // AppState so it updates the moment an item is saved or removed.
  Future<int> _loadSummary() async {
    final orders = await _repository.fetchOrders();
    return orders.length;
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      AppState.instance.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not sign out: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.demoMode
        ? null
        : Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Connect your Supabase project';
    final displayName =
        user?.userMetadata?['full_name'] as String? ?? 'DataBee member';
    final role = user?.appMetadata['role']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My account'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: accent,
                    foregroundColor: ink,
                    child: Text(
                      (user?.email?.isNotEmpty == true
                              ? user!.email!.substring(0, 1)
                              : 'D')
                          .toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: mutedInk, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.verified_user_outlined, color: mutedInk),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<int>(
            future: _summaryFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    title: const Text('Account summary unavailable'),
                    subtitle: Text(snapshot.error.toString()),
                    trailing: IconButton(
                      tooltip: 'Retry',
                      onPressed: () =>
                          setState(() => _summaryFuture = _loadSummary()),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                );
              }
              final orders = snapshot.data ?? 0;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Row(
                    children: [
                      _AccountMetric(value: '$orders', label: 'ORDERS'),
                      ValueListenableBuilder<Set<String>>(
                        valueListenable: AppState.instance.favoriteIds,
                        builder: (context, favorites, _) => _AccountMetric(
                          value: '${favorites.length}',
                          label: 'WISHLIST',
                        ),
                      ),
                      ValueListenableBuilder<List<CartItem>>(
                        valueListenable: AppState.instance.cart,
                        builder: (context, cart, _) => _AccountMetric(
                          value:
                              '${cart.fold<int>(0, (sum, item) => sum + item.quantity)}',
                          label: 'CART',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const _SectionLabel('YOUR DATA'),
          const SizedBox(height: 8),
          _AccountAction(
            icon: Icons.receipt_long_outlined,
            title: 'Order history',
            subtitle: 'Review purchases and payment status',
            onTap: widget.onOrders,
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<Set<String>>(
            valueListenable: AppState.instance.favoriteIds,
            builder: (context, favorites, _) => _AccountAction(
              icon: Icons.favorite_border,
              title: 'Wishlist',
              subtitle: 'Your saved hardware components',
              count: favorites.length,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WishlistScreen(demoMode: widget.demoMode),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<List<CartItem>>(
            valueListenable: AppState.instance.cart,
            builder: (context, cart, _) {
              final count = cart.fold<int>(
                0,
                (sum, item) => sum + item.quantity,
              );
              return _AccountAction(
                icon: Icons.shopping_cart_outlined,
                title: 'Shopping cart',
                subtitle: 'Review items saved for checkout',
                count: count,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CartScreen(demoMode: widget.demoMode),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const _SectionLabel('ACCOUNT MANAGEMENT'),
          const SizedBox(height: 8),
          _AccountAction(
            icon: Icons.location_on_outlined,
            title: 'Delivery addresses',
            subtitle: 'Manage where your orders are delivered',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddressesScreen(demoMode: widget.demoMode),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _AccountAction(
            icon: Icons.support_agent,
            title: 'Warranty & support',
            subtitle: 'Get help with products and orders',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupportScreen()),
            ),
          ),
          if (widget.demoMode || role == 'admin') ...[
            const SizedBox(height: 24),
            const _SectionLabel('SELLER TOOLS'),
            const SizedBox(height: 8),
            _AccountAction(
              icon: Icons.inventory_2_outlined,
              title: widget.demoMode
                  ? 'Demo Seller Order Management'
                  : 'Seller Order Management',
              subtitle: 'Confirm orders and prepare them for pickup',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderManagementScreen(
                    demoMode: widget.demoMode,
                    mode: OrderManagementMode.seller,
                  ),
                ),
              ),
            ),
          ],
          if (widget.demoMode || role == 'rider') ...[
            const SizedBox(height: 8),
            _AccountAction(
              icon: Icons.delivery_dining_outlined,
              title: widget.demoMode
                  ? 'Demo Rider Dashboard'
                  : 'Rider Dashboard',
              subtitle: 'Accept and complete assigned deliveries',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderManagementScreen(
                    demoMode: widget.demoMode,
                    mode: OrderManagementMode.rider,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (widget.demoMode)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Demo mode saves your cart, wishlist, addresses, and orders on this device. COD checkout and seller/rider actions are simulated locally.',
                  style: TextStyle(color: mutedInk, height: 1.45),
                ),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
        ],
      ),
    );
  }
}

class _AccountMetric extends StatelessWidget {
  const _AccountMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: mutedInk,
              fontSize: 10,
              fontWeight: FontWeight.w700,
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

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: ink),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: count == null
            ? const Icon(Icons.chevron_right)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge(
                    backgroundColor: accent,
                    textColor: ink,
                    label: Text('$count'),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
      ),
    );
  }
}
