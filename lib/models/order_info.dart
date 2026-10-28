enum OrderStage {
  pendingConfirmation,
  toShip,
  readyForPickup,
  outForDelivery,
  delivered,
  cancelled,
}

extension OrderStageLabel on OrderStage {
  String get label => switch (this) {
    OrderStage.pendingConfirmation => 'Pending Confirmation',
    OrderStage.toShip => 'To Ship',
    OrderStage.readyForPickup => 'Ready for Pickup',
    OrderStage.outForDelivery => 'Out for Delivery',
    OrderStage.delivered => 'Delivered',
    OrderStage.cancelled => 'Cancelled',
  };
}

/// One row of the `orders` table, with a Shopee-style stage worked out from
/// the payment status and (when present) the `delivery_status` column.
class OrderInfo {
  const OrderInfo({
    required this.id,
    required this.productId,
    required this.productName,
    required this.amount,
    required this.quantity,
    required this.paymentStatus,
    required this.deliveryStatus,
    required this.createdAt,
    required this.shippedAt,
    required this.deliveredAt,
    required this.trackingNumber,
    this.items = const [],
    this.paymentMethod = '',
    this.deliveryFee = 0,
    this.subtotal = 0,
    this.address,
    this.riderId,
    this.confirmedAt,
    this.readyForPickupAt,
    this.outForDeliveryAt,
    this.cancelledAt,
  });

  final String id;
  final String? productId;
  final String productName;
  final num amount;
  final int quantity;
  final String paymentStatus;
  final String deliveryStatus;
  final DateTime? createdAt;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;
  final String? trackingNumber;
  final List<OrderLineInfo> items;
  final String paymentMethod;
  final num deliveryFee;
  final num subtotal;
  final Map<String, dynamic>? address;
  final String? riderId;
  final DateTime? confirmedAt;
  final DateTime? readyForPickupAt;
  final DateTime? outForDeliveryAt;
  final DateTime? cancelledAt;

  factory OrderInfo.fromMap(Map<String, dynamic> map) {
    String? text(String key) {
      final value = map[key];
      if (value == null) return null;
      final result = value.toString().trim();
      return result.isEmpty ? null : result;
    }

    DateTime? date(String key) => DateTime.tryParse(text(key) ?? '')?.toLocal();

    final itemRows = map['order_items'];
    final items = itemRows is List
        ? itemRows
              .whereType<Map>()
              .map(
                (row) => OrderLineInfo.fromMap(Map<String, dynamic>.from(row)),
              )
              .toList()
        : <OrderLineInfo>[];
    final addressValue = map['delivery_address'];
    final address = addressValue is Map
        ? Map<String, dynamic>.from(addressValue)
        : null;
    final paymentMethod = text('payment_method') ?? '';
    final paymentStatus = paymentMethod.toUpperCase() == 'COD'
        ? text('payment_status') ?? text('status') ?? 'PENDING'
        : text('status') ?? text('payment_status') ?? 'PENDING';

    return OrderInfo(
      id: map['id'].toString(),
      productId: text('product_id'),
      productName: items.isNotEmpty
          ? items.length == 1
                ? items.single.productName
                : '${items.first.productName} + ${items.length - 1} more'
          : text('product_name') ?? 'Component order',
      amount: map['amount'] as num? ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      paymentStatus: paymentStatus.toUpperCase(),
      deliveryStatus: (text('delivery_status') ?? '').toUpperCase(),
      createdAt: date('created_at'),
      shippedAt: date('shipped_at'),
      deliveredAt: date('delivered_at'),
      trackingNumber: text('tracking_number'),
      items: items,
      paymentMethod: paymentMethod,
      deliveryFee: map['delivery_fee'] as num? ?? 0,
      subtotal: map['subtotal'] as num? ?? 0,
      address: address,
      riderId: text('rider_id'),
      confirmedAt: date('confirmed_at'),
      readyForPickupAt: date('ready_for_pickup_at'),
      outForDeliveryAt: date('out_for_delivery_at'),
      cancelledAt: date('cancelled_at'),
    );
  }

  bool get isPaid => paymentStatus == 'PAID' || paymentStatus == 'SETTLED';

  OrderStage get stage {
    if (deliveryStatus == 'CANCELLED' ||
        paymentStatus == 'EXPIRED' ||
        paymentStatus == 'FAILED' ||
        paymentStatus == 'CANCELLED') {
      return OrderStage.cancelled;
    }
    return switch (deliveryStatus) {
      'PENDING_CONFIRMATION' => OrderStage.pendingConfirmation,
      'TO_SHIP' || 'PROCESSING' => OrderStage.toShip,
      'READY_FOR_PICKUP' => OrderStage.readyForPickup,
      'OUT_FOR_DELIVERY' ||
      'SHIPPED' ||
      'IN_TRANSIT' => OrderStage.outForDelivery,
      'DELIVERED' || 'COMPLETED' => OrderStage.delivered,
      _ => isPaid ? OrderStage.toShip : OrderStage.pendingConfirmation,
    };
  }

  /// Short sentence shown under the stage.
  String get stageDescription => switch (stage) {
    OrderStage.pendingConfirmation =>
      paymentMethod == 'COD'
          ? 'Your order is waiting for seller confirmation.'
          : 'Waiting for your payment.',
    OrderStage.toShip => 'The seller is preparing your order.',
    OrderStage.readyForPickup => 'Your order is ready for rider pickup.',
    OrderStage.outForDelivery => 'Your parcel is out for delivery.',
    OrderStage.delivered => 'Your order has been delivered.',
    OrderStage.cancelled =>
      paymentStatus == 'EXPIRED'
          ? 'The payment window expired, so this order was cancelled.'
          : 'This order was cancelled.',
  };
}

class OrderLineInfo {
  const OrderLineInfo({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.imageUrl = '',
    this.productId,
  });

  final String? productId;
  final String productName;
  final int quantity;
  final num unitPrice;
  final String imageUrl;

  num get lineTotal => unitPrice * quantity;

  factory OrderLineInfo.fromMap(Map<String, dynamic> map) => OrderLineInfo(
    productName: map['product_name']?.toString() ?? 'Component',
    quantity: (map['quantity'] as num?)?.toInt() ?? 1,
    unitPrice: map['unit_price'] as num? ?? 0,
    imageUrl: map['image_url']?.toString() ?? '',
    productId: map['product_id']?.toString(),
  );
}

String formatOrderDate(DateTime? date) {
  if (date == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour >= 12 ? 'PM' : 'AM';
  return '${months[date.month - 1]} ${date.day}, ${date.year} · $hour12:$minute $suffix';
}
