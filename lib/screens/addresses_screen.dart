import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/delivery_address.dart';
import '../services/store_repository.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key, required this.demoMode});

  final bool demoMode;

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  late final StoreRepository _repository;
  late Future<List<DeliveryAddress>> _addressesFuture;
  List<DeliveryAddress> _addresses = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _repository = StoreRepository(demoMode: widget.demoMode);
    _addressesFuture = _load();
  }

  Future<List<DeliveryAddress>> _load() async {
    final addresses = await _repository.fetchAddresses();
    _addresses = addresses;
    return addresses;
  }

  void _reload() {
    setState(() => _addressesFuture = _load());
  }

  Future<void> _persist(List<DeliveryAddress> updated) async {
    setState(() => _isSaving = true);
    try {
      final savedAddresses = await _repository.saveAddresses(updated);
      if (!mounted) return;
      setState(() {
        _addresses = savedAddresses;
        _addressesFuture = Future.value(savedAddresses);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save address: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openForm({DeliveryAddress? existing}) async {
    final result = await Navigator.push<DeliveryAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressFormScreen(
          existing: existing,
          isFirstAddress: _addresses.isEmpty,
        ),
      ),
    );
    if (result == null) return;

    var updated = List<DeliveryAddress>.of(_addresses);
    final index = updated.indexWhere((address) => address.id == result.id);
    if (index == -1) {
      updated.add(result);
    } else {
      updated[index] = result;
    }
    if (result.isDefault) {
      updated = updated
          .map(
            (address) => address.copyWith(isDefault: address.id == result.id),
          )
          .toList();
    } else if (!updated.any((address) => address.isDefault)) {
      updated[0] = updated[0].copyWith(isDefault: true);
    }
    await _persist(updated);
  }

  Future<void> _makeDefault(DeliveryAddress target) async {
    final updated = _addresses
        .map((address) => address.copyWith(isDefault: address.id == target.id))
        .toList();
    await _persist(updated);
  }

  Future<void> _delete(DeliveryAddress target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text('Remove "${target.label}" from your saved addresses?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final updated = _addresses
        .where((address) => address.id != target.id)
        .toList();
    if (updated.isNotEmpty && !updated.any((address) => address.isDefault)) {
      updated[0] = updated[0].copyWith(isDefault: true);
    }
    await _persist(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery addresses')),
      body: FutureBuilder<List<DeliveryAddress>>(
        future: _addressesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load your addresses.'),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: mutedInk),
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
          final addresses = snapshot.data ?? const <DeliveryAddress>[];
          if (addresses.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on_outlined, size: 54, color: mutedInk),
                    SizedBox(height: 12),
                    Text(
                      'No delivery addresses yet',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Add an address so your orders know where to go.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedInk),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: addresses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final address = addresses[index];
              return _AddressCard(
                address: address,
                enabled: !_isSaving,
                onEdit: () => _openForm(existing: address),
                onDelete: () => _delete(address),
                onMakeDefault: () => _makeDefault(address),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _isSaving ? null : () => _openForm(),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add new address'),
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
    required this.onMakeDefault,
  });

  final DeliveryAddress address;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMakeDefault;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  address.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (address.isDefault) ...[
                  const SizedBox(width: 8),
                  const Chip(
                    label: Text('DEFAULT'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Edit address',
                  onPressed: enabled ? onEdit : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete address',
                  onPressed: enabled ? onDelete : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              address.fullName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (address.phone.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(address.phone, style: const TextStyle(color: mutedInk)),
            ],
            const SizedBox(height: 6),
            Text(
              address.singleLine,
              style: const TextStyle(color: mutedInk, height: 1.4),
            ),
            if (!address.isDefault) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: enabled ? onMakeDefault : null,
                child: const Text('Set as default'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({
    super.key,
    this.existing,
    required this.isFirstAddress,
  });

  final DeliveryAddress? existing;
  final bool isFirstAddress;

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  static const _labels = ['Home', 'Work', 'Other'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _streetController;
  late final TextEditingController _barangayController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _postalController;
  late String _label;
  late bool _isDefault;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.fullName ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _streetController = TextEditingController(text: existing?.street ?? '');
    _barangayController = TextEditingController(text: existing?.barangay ?? '');
    _cityController = TextEditingController(text: existing?.city ?? '');
    _provinceController = TextEditingController(text: existing?.province ?? '');
    _postalController = TextEditingController(text: existing?.postalCode ?? '');
    _label = _labels.contains(existing?.label) ? existing!.label : 'Home';
    _isDefault = existing?.isDefault ?? widget.isFirstAddress;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _barangayController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _postalController.dispose();
    super.dispose();
  }

  String? _required(String? value, String field) {
    if (value == null || value.trim().isEmpty) return 'Enter $field';
    final normalized = value.trim().toLowerCase();
    if (normalized == 'test' ||
        normalized == 'placeholder' ||
        normalized == 'n/a' ||
        normalized == 'na' ||
        normalized == 'none' ||
        normalized == '-') {
      return 'Enter a real $field';
    }
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    final address = DeliveryAddress(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      label: _label,
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      street: _streetController.text.trim(),
      barangay: _barangayController.text.trim(),
      city: _cityController.text.trim(),
      province: _provinceController.text.trim(),
      postalCode: _postalController.text.trim(),
      isDefault: _isDefault,
    );
    Navigator.pop(context, address);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit address' : 'New address')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _label,
              decoration: const InputDecoration(labelText: 'Address label'),
              items: _labels
                  .map(
                    (label) =>
                        DropdownMenuItem(value: label, child: Text(label)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _label = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (value) => _required(value, 'the recipient name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                hintText: '09XX XXX XXXX',
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
                if (digits.length < 7) return 'Enter a valid mobile number';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _streetController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'House no., building, street',
              ),
              validator: (value) => _required(value, 'the street address'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barangayController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Barangay'),
              validator: (value) => _required(value, 'the barangay'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cityController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'City / municipality',
              ),
              validator: (value) =>
                  _required(value, 'the city or municipality'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _provinceController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Province'),
              validator: (value) => _required(value, 'the province'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _postalController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Postal code'),
              validator: (value) {
                final requiredError = _required(value, 'the postal code');
                if (requiredError != null) return requiredError;
                if (!RegExp(r'^\d{4,6}$').hasMatch(value!.trim())) {
                  return 'Enter a valid postal code';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              onChanged: (value) => setState(() => _isDefault = value),
              title: const Text('Use as default address'),
              activeThumbColor: accent,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _save,
              child: Text(editing ? 'Save changes' : 'Save address'),
            ),
          ],
        ),
      ),
    );
  }
}
