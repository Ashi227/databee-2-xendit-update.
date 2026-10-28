import 'package:flutter/material.dart';

import '../app/theme.dart';

class WarrantySupportScreen extends StatefulWidget {
  const WarrantySupportScreen({super.key});

  @override
  State<WarrantySupportScreen> createState() => _WarrantySupportScreenState();
}

class _WarrantySupportScreenState extends State<WarrantySupportScreen> {
  final _orderController = TextEditingController();
  final _detailsController = TextEditingController();
  String _topic = 'Warranty claim';

  @override
  void dispose() {
    _orderController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_detailsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please describe how we can help.')));
      return;
    }
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Sample support request received'),
      content: Text('Topic: $_topic\nReference: ${_orderController.text.trim().isEmpty ? 'Not provided' : _orderController.text.trim()}\n\nThis is a UI prototype. No real ticket was sent.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    ));
    _detailsController.clear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Warranty & support')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.verified_outlined, size: 28), SizedBox(width: 10), Expanded(child: Text('Sample limited warranty', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)))]),
        const SizedBox(height: 12),
        _bullet('Warranty period: 12 months from the purchase date (sample policy; actual brand warranty may differ).'),
        _bullet('Keep your order receipt and original serial number for verification.'),
        _bullet('Warranty covers verified manufacturing defects under normal use.'),
        _bullet('Physical damage, liquid damage, tampering, and improper installation may be excluded.'),
        _bullet('Contact support before shipping a component for inspection or replacement.'),
      ]))),
      const SizedBox(height: 16),
      Text('Contact support', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Card(child: Column(children: [
        ListTile(leading: Icon(Icons.email_outlined), title: Text('Email'), subtitle: Text('support@databee.com  (sample contact)')),
        Divider(height: 1),
        ListTile(leading: Icon(Icons.schedule_outlined), title: Text('Support hours'), subtitle: Text('Monday–Saturday · 9:00 AM–6:00 PM (sample hours)')),
        Divider(height: 1),
        ListTile(leading: Icon(Icons.timer_outlined), title: Text('Response time'), subtitle: Text('Usually within 1–2 business days (sample target)')),
      ])),
      const SizedBox(height: 20),
      Text('Create a support request', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(initialValue: _topic, decoration: const InputDecoration(labelText: 'What do you need help with?'), items: const [DropdownMenuItem(value: 'Warranty claim', child: Text('Warranty claim')), DropdownMenuItem(value: 'Delivery issue', child: Text('Delivery issue')), DropdownMenuItem(value: 'Product question', child: Text('Product question')), DropdownMenuItem(value: 'Order issue', child: Text('Order issue'))], onChanged: (value) => setState(() => _topic = value ?? _topic)),
      const SizedBox(height: 12),
      TextField(controller: _orderController, decoration: const InputDecoration(labelText: 'Order number (optional)', prefixIcon: Icon(Icons.receipt_long_outlined))),
      const SizedBox(height: 12),
      TextField(controller: _detailsController, maxLines: 4, decoration: const InputDecoration(labelText: 'Describe the issue', alignLabelWithHint: true, prefixIcon: Icon(Icons.message_outlined))),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.send_outlined), label: const Text('Submit sample request')),
      const SizedBox(height: 10),
      const Text('The warranty terms and contact details above are demonstration content. Replace them with your group’s approved policy before release.', style: TextStyle(color: mutedInk, fontSize: 12)),
    ]),
  );

  Widget _bullet(String text) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(text, style: const TextStyle(height: 1.4)))]));
}
