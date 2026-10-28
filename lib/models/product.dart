class Product {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.price,
    required this.description,
    required this.stock,
    this.imageUrl = '',
    this.specs = const {},
    this.featured = false,
  });

  final String id;
  final String name;
  final String brand;
  final String category;
  final num price;
  final String description;
  final int stock;
  final String imageUrl;
  final Map<String, dynamic> specs;
  final bool featured;

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'].toString(),
      name: map['name'] as String? ?? 'Unnamed component',
      brand: map['brand'] as String? ?? 'Generic',
      category: map['category'] as String? ?? 'Other',
      price: map['price'] as num? ?? 0,
      description: map['description'] as String? ?? '',
      stock: map['stock'] as int? ?? 0,
      imageUrl: map['image_url'] as String? ?? '',
      specs: Map<String, dynamic>.from(map['specs'] as Map? ?? const {}),
      featured: map['featured'] as bool? ?? false,
    );
  }
}

String formatPhp(num amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final digits = parts.first;
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    final start = (end - 3).clamp(0, digits.length);
    groups.insert(0, digits.substring(start, end));
  }
  return '₱${groups.join(',')}.${parts.last}';
}
