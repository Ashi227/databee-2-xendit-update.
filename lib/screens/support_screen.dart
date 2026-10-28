import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Warranty & support page. The text below is sample content that shows what
/// the page can look like; replace it with DataBee's real policy and contacts.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _coverage = [
    ('GPUs', '3 years', Icons.videogame_asset_outlined),
    ('CPUs', '3 years', Icons.memory),
    ('Motherboards', '3 years', Icons.developer_board_outlined),
    ('Memory', 'Limited lifetime', Icons.storage),
    ('Storage', '5 years', Icons.sd_storage_outlined),
    ('Power Supplies', '5 years', Icons.bolt),
  ];

  static const _claimSteps = [
    'Keep your order receipt. Your order history shows the purchase date.',
    'Contact support with your order number and a short description of the issue.',
    'Our team confirms the warranty and sends return instructions within 2 business days.',
    'Ship or drop off the item in its original packaging with all accessories.',
    'We test the part, then repair, replace, or refund it within 7 to 14 business days.',
  ];

  static const _faqs = [
    (
      'What does the warranty cover?',
      'Manufacturing defects and hardware failures that happen during normal '
          'use within the warranty period shown above.',
    ),
    (
      'What is not covered?',
      'Physical damage, liquid damage, burnt parts caused by incorrect '
          'installation or power surges, overclocking damage, and removed or '
          'tampered serial stickers.',
    ),
    (
      'Can I return an item I just received?',
      'Yes. Unused items in sealed packaging can be returned within 7 days '
          'of delivery. Items that arrive damaged or defective can be '
          'replaced at no cost.',
    ),
    (
      'How do I know if my part is compatible?',
      'Check the specifications on the product page, such as socket, memory '
          'type, and power draw. Support can also double-check your parts '
          'list before you order.',
    ),
    (
      'How long does a replacement take?',
      'Most replacements ship within 3 business days after the returned '
          'item passes inspection, depending on stock.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Warranty & support')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: mutedInk),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sample content. Replace these terms and contact '
                      'details with DataBee\'s actual warranty policy.',
                      style: TextStyle(color: mutedInk, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('CONTACT SUPPORT'),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.email_outlined, color: ink),
                  title: Text(
                    'Email',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('support@databee.example'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.phone_outlined, color: ink),
                  title: Text(
                    'Phone / Viber',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('+63 900 000 0000'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.schedule, color: ink),
                  title: Text(
                    'Support hours',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Monday to Saturday, 9:00 AM to 6:00 PM'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('WARRANTY COVERAGE'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < _coverage.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(_coverage[i].$3, color: ink),
                    title: Text(
                      _coverage[i].$1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Text(
                      _coverage[i].$2,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('HOW TO CLAIM A WARRANTY'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (var i = 0; i < _claimSteps.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == _claimSteps.length - 1 ? 0 : 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: accent,
                            foregroundColor: ink,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _claimSteps[i],
                              style: const TextStyle(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('FREQUENTLY ASKED QUESTIONS'),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _faqs.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(
                      _faqs[i].$1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedAlignment: Alignment.centerLeft,
                    children: [
                      Text(
                        _faqs[i].$2,
                        style: const TextStyle(color: mutedInk, height: 1.5),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: mutedInk,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
      ),
    );
  }
}
