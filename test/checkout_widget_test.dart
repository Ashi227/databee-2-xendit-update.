import 'package:databee/models/delivery_address.dart';
import 'package:databee/models/order_info.dart';
import 'package:databee/screens/checkout_screen.dart';
import 'package:databee/screens/order_detail_screen.dart';
import 'package:databee/services/app_state.dart';
import 'package:databee/services/store_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance
      ..restoreCart([])
      ..setFavorites({});
  });

  testWidgets(
    'checkout places COD order and clears only purchased cart lines',
    (tester) async {
      final repository = StoreRepository(demoMode: true);
      final product = StoreRepository.demoProducts.first;
      final address = DeliveryAddress(
        id: 'checkout-address',
        label: 'Home',
        fullName: 'Demo Buyer',
        phone: '09123456789',
        street: '12 Sample Street',
        barangay: 'Barangay One',
        city: 'Quezon City',
        province: 'Metro Manila',
        postalCode: '1100',
        isDefault: true,
      );
      final cartItem = CartItem(product: product, quantity: 1);
      final remainingItem = CartItem(
        product: StoreRepository.demoProducts[1],
        quantity: 2,
      );
      await repository.saveAddresses([address]);
      await repository.saveCart([cartItem, remainingItem]);
      AppState.instance.restoreCart([cartItem, remainingItem]);

      await tester.pumpWidget(
        MaterialApp(home: CheckoutScreen(demoMode: true, items: [cartItem])),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('12 Sample Street'), findsOneWidget);

      await tester.tap(find.text('Place COD order'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Order placed'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final orders = await repository.fetchOrders();
      expect(orders, hasLength(1));
      expect(
        OrderInfo.fromMap(orders.single).stage,
        OrderStage.pendingConfirmation,
      );
      expect(
        (await repository.fetchCart()).single.product.id,
        remainingItem.product.id,
      );
      expect(
        AppState.instance.cart.value.single.product.id,
        remainingItem.product.id,
      );
    },
  );

  testWidgets('Supabase checkout allows selecting Xendit payment', (
    tester,
  ) async {
    final product = StoreRepository.demoProducts.first;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          demoMode: false,
          items: [CartItem(product: product, quantity: 1)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Xendit'), findsOneWidget);
    await tester.tap(find.text('Xendit'));
    await tester.pumpAndSettle();
    expect(find.text('Pay with Xendit'), findsOneWidget);
  });

  testWidgets('customer can cancel a pending COD order', (tester) async {
    final repository = StoreRepository(demoMode: true);
    final product = StoreRepository.demoProducts.first;
    final address = DeliveryAddress(
      id: 'cancel-address',
      label: 'Home',
      fullName: 'Demo Buyer',
      phone: '09123456789',
      street: '12 Sample Street',
      barangay: 'Barangay One',
      city: 'Quezon City',
      province: 'Metro Manila',
      postalCode: '1100',
    );
    final originalStock = (await repository.fetchProducts())
        .firstWhere((item) => item.id == product.id)
        .stock;
    final orderId = await repository.createCodOrder(
      items: [CartItem(product: product, quantity: 1)],
      address: address,
      checkoutKey: 'cancel-order-test',
    );
    final order = OrderInfo.fromMap((await repository.fetchOrders()).single);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      OrderDetailScreen(order: order, demoMode: true),
                ),
              ),
              child: const Text('Open order'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open order'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel order'), findsOneWidget);
    await tester.tap(find.text('Cancel order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel order').last);
    await tester.pumpAndSettle();

    expect(find.text('Open order'), findsOneWidget);
    final savedOrder = (await repository.fetchOrders()).single;
    expect(savedOrder['id'], orderId);
    expect(OrderInfo.fromMap(savedOrder).stage, OrderStage.cancelled);
    expect(
      (await repository.fetchProducts())
          .firstWhere((item) => item.id == product.id)
          .stock,
      originalStock,
    );
  });

  testWidgets('checkout refuses to place an order without a valid address', (
    tester,
  ) async {
    final product = StoreRepository.demoProducts.first;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          demoMode: true,
          items: [CartItem(product: product, quantity: 1)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Place COD order'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add and select a valid delivery address to continue.'),
      findsOneWidget,
    );
    expect(await StoreRepository(demoMode: true).fetchOrders(), isEmpty);
  });
}
