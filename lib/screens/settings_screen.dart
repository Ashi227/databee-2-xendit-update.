import 'package:flutter/material.dart';

import '../app/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _compatibilityAlerts = true;
  bool _orderUpdates = true;
  bool _priceAlerts = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _StatusCard(
            title: 'Compatibility engine',
            detail: 'Ready to check component specifications.',
            icon: Icons.settings_suggest_outlined,
            status: 'ACTIVE',
          ),
          const SizedBox(height: 10),
          const _StatusCard(
            title: 'Thermal protection',
            detail: 'Product TDP details are shown when available.',
            icon: Icons.bolt_outlined,
            status: 'ENABLED',
          ),
          const SizedBox(height: 24),
          Text(
            'Notifications',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _compatibilityAlerts,
                  onChanged: (value) =>
                      setState(() => _compatibilityAlerts = value),
                  title: const Text('Compatibility alerts'),
                  subtitle: const Text('Warnings about component fit'),
                  activeThumbColor: accent,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _orderUpdates,
                  onChanged: (value) => setState(() => _orderUpdates = value),
                  title: const Text('Order updates'),
                  subtitle: const Text('Payment and delivery status'),
                  activeThumbColor: accent,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _priceAlerts,
                  onChanged: (value) => setState(() => _priceAlerts = value),
                  title: const Text('Price alerts'),
                  subtitle: const Text('Updates for wishlist components'),
                  activeThumbColor: accent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'About DataBee',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.memory),
              title: Text('DataBee Component Store'),
              subtitle: Text('PHP prices · Secure Xendit checkout'),
              trailing: Text('v1.0'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.detail,
    required this.icon,
    required this.status,
  });

  final String title;
  final String detail;
  final IconData icon;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(color: mutedInk, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              status,
              style: const TextStyle(
                color: mutedInk,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
