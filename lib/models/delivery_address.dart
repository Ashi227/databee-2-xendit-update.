class DeliveryAddress {
  const DeliveryAddress({
    required this.id,
    required this.label,
    required this.fullName,
    required this.phone,
    required this.street,
    required this.barangay,
    required this.city,
    required this.province,
    required this.postalCode,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String fullName;
  final String phone;
  final String street;
  final String barangay;
  final String city;
  final String province;
  final String postalCode;
  final bool isDefault;

  bool get isValid {
    final requiredValues = [
      fullName,
      phone,
      street,
      barangay,
      city,
      province,
      postalCode,
    ];
    if (requiredValues.any((value) {
      final normalized = value.trim().toLowerCase();
      return normalized.isEmpty ||
          normalized == 'test' ||
          normalized == 'placeholder' ||
          normalized == 'n/a' ||
          normalized == 'na' ||
          normalized == 'none' ||
          normalized == '-';
    })) {
      return false;
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 7 &&
        RegExp(r'^\d{4,6}$').hasMatch(postalCode.trim());
  }

  String get fullAddress =>
      '$street, $barangay, $city, $province ${postalCode.trim()}';

  DeliveryAddress copyWith({
    String? label,
    String? fullName,
    String? phone,
    String? street,
    String? barangay,
    String? city,
    String? province,
    String? postalCode,
    bool? isDefault,
  }) {
    return DeliveryAddress(
      id: id,
      label: label ?? this.label,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      street: street ?? this.street,
      barangay: barangay ?? this.barangay,
      city: city ?? this.city,
      province: province ?? this.province,
      postalCode: postalCode ?? this.postalCode,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  factory DeliveryAddress.fromMap(Map<String, dynamic> map) {
    return DeliveryAddress(
      id: map['id'].toString(),
      label: map['label'] as String? ?? 'Home',
      fullName:
          map['full_name'] as String? ?? map['recipient_name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      street: map['street'] as String? ?? '',
      barangay: map['barangay'] as String? ?? '',
      city: map['city'] as String? ?? '',
      province: map['province'] as String? ?? '',
      postalCode: map['postal_code'] as String? ?? '',
      isDefault: map['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'full_name': fullName,
      'phone': phone,
      'street': street,
      'barangay': barangay,
      'city': city,
      'province': province,
      'postal_code': postalCode,
      'is_default': isDefault,
    };
  }

  /// One-line version used in the address list.
  String get singleLine {
    final parts = [
      street,
      barangay,
      city,
      province,
      postalCode,
    ].where((part) => part.trim().isNotEmpty);
    return parts.join(', ');
  }
}
