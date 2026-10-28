import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/theme.dart';

class DeliveryAddressScreen extends StatefulWidget {
  const DeliveryAddressScreen({super.key});

  @override
  State<DeliveryAddressScreen> createState() => _DeliveryAddressScreenState();
}

class _DeliveryAddressScreenState extends State<DeliveryAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _street;
  late final TextEditingController _barangay;
  late final TextEditingController _city;
  late final TextEditingController _province;
  late final TextEditingController _postal;
  String? _savedId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _phone = TextEditingController();
    _street = TextEditingController();
    _barangay = TextEditingController();
    _city = TextEditingController();
    _province = TextEditingController();
    _postal = TextEditingController();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Please sign in to manage your address.');
      final row = await client
          .from('delivery_addresses')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) {
        _savedId = row['id']?.toString();
        _name.text = row['recipient_name']?.toString() ?? '';
        _phone.text = row['phone']?.toString() ?? '';
        _street.text = row['street']?.toString() ?? '';
        _barangay.text = row['barangay']?.toString() ?? '';
        _city.text = row['city']?.toString() ?? '';
        _province.text = row['province']?.toString() ?? '';
        _postal.text = row['postal_code']?.toString() ?? '';
      }
    } catch (error) {
      if (mounted) _message('Could not load address: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _phone, _street, _barangay, _city, _province, _postal]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Please sign in before saving an address.');
      final values = <String, dynamic>{
        'user_id': user.id,
        'recipient_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'street': _street.text.trim(),
        'barangay': _barangay.text.trim(),
        'city': _city.text.trim(),
        'province': _province.text.trim(),
        'postal_code': _postal.text.trim(),
        'is_default': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (_savedId == null) {
        final inserted = await client
            .from('delivery_addresses')
            .insert(values)
            .select('id')
            .single();
        _savedId = inserted['id']?.toString();
      } else {
        await client.from('delivery_addresses').update(values).eq('id', _savedId!);
      }
      if (mounted) _message('Delivery address saved to your DataBee account.');
    } catch (error) {
      if (mounted) _message('Could not save address: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _field(String label, TextEditingController controller,
      {TextInputType? keyboardType}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.location_on_outlined),
          ),
          validator: (value) => (value?.trim().isEmpty ?? true)
              ? 'Please enter $label.'
              : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery address')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Where should we deliver your components?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                  'Your saved address is linked to your signed-in DataBee account.',
                  style: TextStyle(color: mutedInk),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _field('Recipient name', _name),
                      _field('Mobile number', _phone, keyboardType: TextInputType.phone),
                      _field('House / street / building', _street),
                      _field('Barangay', _barangay),
                      _field('City / municipality', _city),
                      _field('Province', _province),
                      _field('Postal code', _postal, keyboardType: TextInputType.number),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving...' : 'Save address'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
