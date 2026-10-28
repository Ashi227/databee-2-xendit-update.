import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/app_config.dart';
import '../models/delivery_address.dart';
import '../models/product.dart';
import 'app_state.dart';

class StoreRepository {
  StoreRepository({SupabaseClient? client, bool demoMode = false})
    : _client =
          client ??
          (!demoMode && AppConfig.isConfigured
              ? Supabase.instance.client
              : null);

  final SupabaseClient? _client;

  static const demoProducts = <Product>[
    Product(
      id: 'demo-gpu',
      name: 'GeForce RTX 4080 SUPER 16GB',
      brand: 'NVIDIA',
      category: 'GPUs',
      price: 59999,
      description: 'High-performance graphics for demanding games, creative work, and AI workloads.',
      stock: 8,
      featured: true,
      specs: {'Memory': '16GB GDDR6X', 'Interface': 'PCIe 4.0', 'TDP': '320W'},
    ),
    Product(
      id: 'demo-cpu',
      name: 'Ryzen 7 7800X3D',
      brand: 'AMD',
      category: 'CPUs',
      price: 21995,
      description: 'An efficient 8-core desktop processor with 3D V-Cache for fast gaming.',
      stock: 12,
      specs: {'Cores': '8', 'Socket': 'AM5', 'TDP': '120W'},
    ),
    Product(
      id: 'demo-motherboard',
      name: 'B650 AORUS Elite AX',
      brand: 'Gigabyte',
      category: 'Motherboards',
      price: 12950,
      description:
          'AM5 ATX motherboard with Wi-Fi, PCIe 4.0 storage, and DDR5 support.',
      stock: 6,
      specs: {'Socket': 'AM5', 'Form factor': 'ATX', 'Memory': 'DDR5'},
    ),
    Product(
      id: 'demo-memory',
      name: 'Vengeance 32GB DDR5 6000',
      brand: 'Corsair',
      category: 'Memory',
      price: 5395,
      description: 'A low-latency 32GB DDR5 memory kit for modern desktop PCs.',
      stock: 20,
      specs: {'Capacity': '32GB', 'Speed': '6000 MT/s', 'Type': 'DDR5'},
    ),
    Product(
      id: 'demo-storage',
      name: '990 PRO 2TB NVMe SSD',
      brand: 'Samsung',
      category: 'Storage',
      price: 8990,
      description: 'Fast PCIe 4.0 NVMe storage with a 2TB capacity for games and projects.',
      stock: 14,
      specs: {'Capacity': '2TB', 'Interface': 'PCIe 4.0 x4', 'Form': 'M.2'},
    ),
    Product(
      id: 'demo-psu',
      name: 'RM850e 850W 80+ Gold',
      brand: 'Corsair',
      category: 'Power Supplies',
      price: 7190,
      description: 'Fully modular 850W power supply, ready for current-generation builds.',
      stock: 9,
      specs: {'Power': '850W', 'Efficiency': '80+ Gold', 'Modular': 'Yes'},
    ),
  ];

  static const _cartKey = 'databee.demo.cart';
  static const _favoritesKey = 'databee.demo.favorites';
  static const _addressesKey = 'databee.demo.addresses';
  static const _ordersKey = 'databee.demo.orders';
  static const demoRiderId = 'databee-demo-rider';

  bool get isDemo => _client == null;

  Future<List<Product>> fetchProducts() async {
    final client = _client;
    if (client == null) {
      final remaining = await _remainingDemoStock();
      return demoProducts
          .map(
            (product) =>
                _withStock(product, remaining[product.id] ?? product.stock),
          )
          .toList();
    }

    final rows = await client
        .from('products')
        .select()
        .eq('is_active', true)
        .order('featured', ascending: false)
        .order('name');
    return rows.map((row) => Product.fromMap(row)).toList();
  }

  Future<List<CartItem>> fetchCart() async {
    final client = _client;
    if (client == null) {
      final values = await _readList(_cartKey);
      final remaining = await _remainingDemoStock();
      return values.map((value) {
        final savedProduct = Product.fromMap(
          Map<String, dynamic>.from(value['product'] as Map),
        );
        return CartItem(
          product: _withStock(
            savedProduct,
            remaining[savedProduct.id] ?? savedProduct.stock,
          ),
          quantity: (value['quantity'] as num).toInt(),
        );
      }).toList();
    }

    _requireUserId(client);
    final rows = await client
        .from('cart_items')
        .select('quantity, product:products(*)');
    return rows
        .where((row) => row['product'] is Map)
        .map(
          (row) => CartItem(
            product: Product.fromMap(
              Map<String, dynamic>.from(row['product'] as Map),
            ),
            quantity: (row['quantity'] as num).toInt(),
          ),
        )
        .toList();
  }

  Future<void> saveCart(List<CartItem> items) async {
    final client = _client;
    if (client == null) {
      await _writeList(
        _cartKey,
        items
            .map(
              (item) => {
                'product': _productToMap(item.product),
                'quantity': item.quantity,
              },
            )
            .toList(),
      );
      return;
    }

    _requireUserId(client);
    await client.rpc(
      'save_cart_items',
      params: {
        'p_items': items
            .map(
              (item) => {
                'product_id': item.product.id,
                'quantity': item.quantity,
              },
            )
            .toList(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchOrders() async {
    final client = _client;
    if (client == null) return _readList(_ordersKey);

    final rows = await client
        .from('orders')
        .select('*, order_items(*)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Stream<void> watchOrderChanges() {
    final client = _client;
    if (client == null) return const Stream<void>.empty();
    return client.from('orders').stream(primaryKey: ['id']).map<void>((_) {});
  }

  Future<Set<String>> fetchFavoriteIds() async {
    final client = _client;
    if (client == null) {
      final values = await _readList(_favoritesKey);
      return values.map((value) => value['product_id'].toString()).toSet();
    }

    final rows = await client.from('favorites').select('product_id');
    return rows.map((row) => row['product_id'].toString()).toSet();
  }

  Future<void> setFavorite(String productId, bool favorite) async {
    final client = _client;
    if (client == null) {
      final ids = await fetchFavoriteIds();
      if (favorite) {
        ids.add(productId);
      } else {
        ids.remove(productId);
      }
      await _writeList(
        _favoritesKey,
        ids.map((id) => {'product_id': id}).toList(),
      );
      return;
    }

    final userId = _requireUserId(client);
    if (favorite) {
      await client.from('favorites').upsert({
        'user_id': userId,
        'product_id': productId,
      });
    } else {
      await client
          .from('favorites')
          .delete()
          .eq('user_id', userId)
          .eq('product_id', productId);
    }
  }

  Future<Map<String, dynamic>> createInvoice(
    Product product, {
    int quantity = 1,
    DeliveryAddress? address,
    num deliveryFee = 0,
    String? checkoutKey,
  }) async {
    return _requestInvoice({
      'product_id': product.id,
      'quantity': quantity,
      'items': [
        {'product_id': product.id, 'quantity': quantity},
      ],
      'delivery_address': address?.toMap(),
      'delivery_fee': deliveryFee,
      'checkout_key': checkoutKey,
    });
  }

  Future<Map<String, dynamic>> createInvoiceForItems({
    required List<CartItem> items,
    required DeliveryAddress address,
    required String checkoutKey,
    num deliveryFee = 0,
  }) async {
    if (items.isEmpty) throw StateError('Your cart is empty.');
    if (!address.isValid) {
      throw StateError('A valid delivery address is required.');
    }
    return _requestInvoice({
      'items': items
          .map(
            (item) => {
              'product_id': item.product.id,
              'quantity': item.quantity,
            },
          )
          .toList(),
      'delivery_address': address.toMap(),
      'delivery_fee': deliveryFee,
      'checkout_key': checkoutKey,
    });
  }

  Future<Map<String, dynamic>> _requestInvoice(
    Map<String, dynamic> body,
  ) async {
    final client = _client;
    if (client == null) {
      throw StateError('Connect Supabase before placing a real order.');
    }
    final response = await client.functions.invoke(
      'create-invoice',
      body: body,
    );
    if (response.status < 200 || response.status >= 300) {
      throw Exception('Invoice creation failed: ${response.data}');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> attachInvoiceDelivery({
    required String externalId,
    required Product product,
    required int quantity,
    required DeliveryAddress address,
  }) async {
    if (quantity < 1 || !address.isValid) {
      throw StateError('A valid quantity and delivery address are required.');
    }
    await _requireClient().rpc(
      'attach_invoice_delivery',
      params: {
        'p_external_id': externalId,
        'p_product_id': product.id,
        'p_quantity': quantity,
        'p_delivery_address': address.toMap(),
      },
    );
  }

  Future<String> orderStatus(String externalId) async {
    final row = await _requireClient()
        .from('orders')
        .select('status')
        .eq('external_id', externalId)
        .maybeSingle();
    return row?['status'] as String? ?? 'PENDING';
  }

  Future<List<DeliveryAddress>> fetchAddresses() async {
    final client = _client;
    if (client == null) {
      final values = await _readList(_addressesKey);
      return values.map(DeliveryAddress.fromMap).toList();
    }

    final userId = _requireUserId(client);
    final rows = await client
        .from('delivery_addresses')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => DeliveryAddress.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<DeliveryAddress>> saveAddresses(
    List<DeliveryAddress> addresses,
  ) async {
    final client = _client;
    if (client == null) {
      await _writeList(
        _addressesKey,
        addresses.map((address) => address.toMap()).toList(),
      );
      return addresses;
    }
    final userId = _requireUserId(client);
    final existing = await client
        .from('delivery_addresses')
        .select('id')
        .eq('user_id', userId);
    final existingIds = existing.map((row) => row['id'].toString()).toSet();
    final savedAddresses = <DeliveryAddress>[];

    for (final address in addresses) {
      final values = <String, dynamic>{
        'user_id': userId,
        'label': address.label,
        'recipient_name': address.fullName,
        'phone': address.phone,
        'street': address.street,
        'barangay': address.barangay,
        'city': address.city,
        'province': address.province,
        'postal_code': address.postalCode,
        'is_default': address.isDefault,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (existingIds.contains(address.id)) values['id'] = address.id;
      final row = await client
          .from('delivery_addresses')
          .upsert(values)
          .select()
          .single();
      savedAddresses.add(
        DeliveryAddress.fromMap(Map<String, dynamic>.from(row)),
      );
    }

    final savedIds = savedAddresses.map((address) => address.id).toSet();
    final removedIds = existingIds.difference(savedIds);
    if (removedIds.isNotEmpty) {
      await client
          .from('delivery_addresses')
          .delete()
          .eq('user_id', userId)
          .inFilter('id', removedIds.toList());
    }
    return savedAddresses;
  }

  Future<String> createCodOrder({
    required List<CartItem> items,
    required DeliveryAddress address,
    required String checkoutKey,
    num deliveryFee = 150,
  }) async {
    if (items.isEmpty) throw StateError('Your cart is empty.');
    if (!address.isValid) {
      throw StateError(
        'Choose or add a valid delivery address before checkout.',
      );
    }
    if (checkoutKey.trim().isEmpty) {
      throw StateError('A valid checkout key is required.');
    }
    final client = _client;
    final localOrders = client == null ? await fetchOrders() : null;
    if (localOrders != null) {
      for (final order in localOrders) {
        if (order['checkout_key'] == checkoutKey) {
          return order['id'].toString();
        }
      }
    }
    final demoStock = _client == null ? await _remainingDemoStock() : null;
    for (final item in items) {
      final available = demoStock?[item.product.id] ?? item.product.stock;
      if (item.quantity < 1 || item.quantity > available) {
        throw StateError('${item.product.name} has an invalid quantity.');
      }
    }

    if (client != null) {
      final result = await client.rpc(
        'create_cod_order',
        params: {
          'p_items': items
              .map(
                (item) => {
                  'product_id': item.product.id,
                  'quantity': item.quantity,
                },
              )
              .toList(),
          'p_delivery_address': address.toMap(),
          'p_delivery_fee': deliveryFee,
          'p_checkout_key': checkoutKey,
        },
      );
      return result.toString();
    }

    final subtotal = items.fold<num>(
      0,
      (total, item) => total + item.lineTotal,
    );
    final now = DateTime.now().toUtc();
    final id = 'DB-${now.millisecondsSinceEpoch}-${Random().nextInt(9999)}';
    final order = <String, dynamic>{
      'id': id,
      'user_id': 'demo-customer',
      'product_id': items.first.product.id,
      'product_name': items.length == 1
          ? items.first.product.name
          : '${items.first.product.name} + ${items.length - 1} more',
      'amount': subtotal + deliveryFee,
      'subtotal': subtotal,
      'delivery_fee': deliveryFee,
      'quantity': items.fold<int>(0, (total, item) => total + item.quantity),
      'status': 'UNPAID',
      'payment_status': 'DUE_ON_DELIVERY',
      'payment_method': 'COD',
      'delivery_status': 'PENDING_CONFIRMATION',
      'delivery_address': address.toMap(),
      'created_at': now.toIso8601String(),
      'order_items': items
          .map(
            (item) => {
              'product_id': item.product.id,
              'product_name': item.product.name,
              'image_url': item.product.imageUrl,
              'unit_price': item.product.price,
              'quantity': item.quantity,
            },
          )
          .toList(),
    };
    final orders = localOrders!;
    orders.insert(0, order);
    order['checkout_key'] = checkoutKey;
    await _writeList(_ordersKey, orders);
    return id;
  }

  Future<void> transitionOrder(String orderId, String action) async {
    final client = _client;
    if (client != null) {
      await client.rpc(
        'transition_order',
        params: {'p_order_id': orderId, 'p_action': action},
      );
      return;
    }

    final orders = await fetchOrders();
    final index = orders.indexWhere(
      (order) => order['id'].toString() == orderId,
    );
    if (index == -1) throw StateError('Order was not found.');
    final order = Map<String, dynamic>.from(orders[index]);
    final status = (order['delivery_status'] ?? '').toString();
    final now = DateTime.now().toUtc().toIso8601String();

    switch (action) {
      case 'confirm':
        _requireStatus(status, 'PENDING_CONFIRMATION');
        order
          ..['delivery_status'] = 'TO_SHIP'
          ..['status'] = 'CONFIRMED'
          ..['confirmed_at'] = now;
      case 'reject':
        _requireStatus(status, 'PENDING_CONFIRMATION');
        order
          ..['delivery_status'] = 'CANCELLED'
          ..['status'] = 'CANCELLED'
          ..['cancelled_at'] = now;
      case 'ready_for_pickup':
        _requireStatus(status, 'TO_SHIP');
        order
          ..['delivery_status'] = 'READY_FOR_PICKUP'
          ..['ready_for_pickup_at'] = now;
      case 'accept_delivery':
        _requireStatus(status, 'READY_FOR_PICKUP');
        if (order['rider_id'] != null) {
          throw StateError('This delivery is already assigned to a rider.');
        }
        order
          ..['rider_id'] = demoRiderId
          ..['delivery_status'] = 'OUT_FOR_DELIVERY'
          ..['out_for_delivery_at'] = now
          ..['shipped_at'] = now;
      case 'mark_delivered':
        _requireStatus(status, 'OUT_FOR_DELIVERY');
        if (order['rider_id'] != demoRiderId) {
          throw StateError(
            'Only the assigned rider can complete this delivery.',
          );
        }
        order
          ..['delivery_status'] = 'DELIVERED'
          ..['delivered_at'] = now;
      case 'cancel':
        _requireStatus(status, 'PENDING_CONFIRMATION');
        order
          ..['delivery_status'] = 'CANCELLED'
          ..['status'] = 'CANCELLED'
          ..['cancelled_at'] = now;
      default:
        throw StateError('Unsupported order action: $action');
    }

    orders[index] = order;
    await _writeList(_ordersKey, orders);
  }

  Future<void> clearPersistedDemoCart() async {
    if (_client == null) await _writeList(_cartKey, []);
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('Saved DataBee data for "$key" is invalid.');
    }
    return decoded
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
  }

  Future<Map<String, int>> _remainingDemoStock() async {
    final remaining = {
      for (final product in demoProducts) product.id: product.stock,
    };
    final orders = await _readList(_ordersKey);
    for (final order in orders) {
      if ((order['delivery_status'] ?? '').toString() == 'CANCELLED') continue;
      final items = order['order_items'];
      if (items is! List) continue;
      for (final value in items.whereType<Map>()) {
        final item = Map<String, dynamic>.from(value);
        final id = item['product_id']?.toString();
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        if (id != null && remaining.containsKey(id)) {
          remaining[id] = (remaining[id]! - quantity).clamp(0, remaining[id]!);
        }
      }
    }
    return remaining;
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> values) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(key, jsonEncode(values));
    if (!saved) throw StateError('Could not save DataBee data on this device.');
  }

  Map<String, dynamic> _productToMap(Product product) => {
    'id': product.id,
    'name': product.name,
    'brand': product.brand,
    'category': product.category,
    'price': product.price,
    'description': product.description,
    'stock': product.stock,
    'image_url': product.imageUrl,
    'specs': product.specs,
    'featured': product.featured,
  };

  Product _withStock(Product product, int stock) => Product(
    id: product.id,
    name: product.name,
    brand: product.brand,
    category: product.category,
    price: product.price,
    description: product.description,
    stock: stock,
    imageUrl: product.imageUrl,
    specs: product.specs,
    featured: product.featured,
  );

  SupabaseClient _requireClient() =>
      _client ?? (throw StateError('Supabase is not configured.'));

  String _requireUserId(SupabaseClient client) =>
      client.auth.currentUser?.id ??
      (throw StateError('Sign in to access your saved shopping data.'));

  void _requireStatus(String actual, String expected) {
    if (actual != expected) {
      throw StateError('This order cannot be changed from its current status.');
    }
  }
}
