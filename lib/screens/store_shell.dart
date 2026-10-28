import 'package:flutter/material.dart';

import '../services/app_state.dart';
import 'account_screen.dart';
import 'catalog_screen.dart';
import 'orders_screen.dart';
import '../services/store_repository.dart';

class StoreShell extends StatefulWidget {
  const StoreShell({super.key, this.demoMode = false});

  final bool demoMode;

  @override
  State<StoreShell> createState() => _StoreShellState();
}

class _StoreShellState extends State<StoreShell> {
  int _selectedIndex = 0;
  late final StoreRepository _repository;
  late Future<void> _restoreFuture;

  @override
  void initState() {
    super.initState();
    _repository = StoreRepository(demoMode: widget.demoMode);
    _restoreFuture = _restoreSavedShoppingData();
  }

  Future<void> _restoreSavedShoppingData() async {
    final cart = await _repository.fetchCart();
    final favorites = await _repository.fetchFavoriteIds();
    AppState.instance
      ..restoreCart(cart)
      ..setFavorites(favorites);
  }

  void _retryRestore() {
    setState(() => _restoreFuture = _restoreSavedShoppingData());
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      CatalogScreen(demoMode: widget.demoMode),
      OrdersScreen(demoMode: widget.demoMode),
      AccountScreen(
        demoMode: widget.demoMode,
        onOrders: () {
          AppState.instance.refreshOrders();
          setState(() => _selectedIndex = 1);
        },
      ),
    ];

    return Scaffold(
      body: FutureBuilder<void>(
        future: _restoreFuture,
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
                    const Text(
                      'DataBee database setup is incomplete. In Supabase, open SQL Editor and run supabase/shopping_delivery.sql.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This creates the cart and order tables required by the app.\n\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _retryRestore,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          return IndexedStack(index: _selectedIndex, children: pages);
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index != 0) AppState.instance.refreshOrders();
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Catalog',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
