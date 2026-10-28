import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';

const _layouts = ['classic', 'compact', 'bold'];

const _actionLabels = {
  'send_to_kitchen': 'Send to kitchen',
  'confirm_payment': 'Confirm payment',
  'quick_save': 'Quick save',
};

const _flagLabels = {
  'enabled': 'Show this button',
  'exact_amount': 'Take the exact amount in cash',
  'print_invoice': 'Print the invoice',
  'print_kitchen': 'Print the kitchen token',
};

/// A branch's POS settings: invoice layout and numbering, payment methods,
/// sounds, cash shortcuts and the action buttons. It sends the whole `pos`
/// block back with the branch's other fields, as the web admin does.
class PosSettingsScreen extends StatefulWidget {
  const PosSettingsScreen({super.key, required this.branch});

  final Map<String, dynamic> branch;

  @override
  State<PosSettingsScreen> createState() => _PosSettingsScreenState();
}

class _PosSettingsScreenState extends State<PosSettingsScreen> {
  late final Map<String, dynamic> _pos = _deepCopy(widget.branch['pos'] as Map? ?? const {});
  late final _pattern = TextEditingController(text: '${_pos['invoice_pattern'] ?? ''}');
  late final _digits = TextEditingController(text: '${_pos['invoice_seq_digits'] ?? 4}');
  late final _cash = TextEditingController(
    text: ((_pos['cash_suggestions'] as List?) ?? const []).join(', '),
  );
  bool _busy = false;

  static Map<String, dynamic> _deepCopy(Map source) => {
        for (final e in source.entries)
          '${e.key}': e.value is Map
              ? _deepCopy(e.value as Map)
              : e.value is List
                  ? [for (final v in e.value as List) v is Map ? _deepCopy(v) : v]
                  : e.value,
      };

  @override
  void dispose() {
    _pattern.dispose();
    _digits.dispose();
    _cash.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _sounds => _pos['sounds'] as Map<String, dynamic>;
  Map<String, dynamic> get _actions => _pos['actions'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get _methods => asRows(_pos['payment_methods']);

  Future<void> _save() async {
    final app = AppScope.read(context);
    final digits = int.tryParse(_digits.text.trim());
    if (digits == null || digits < 1 || digits > 8) {
      snack(context, 'Counter digits must be between 1 and 8.', error: true);
      return;
    }
    if (!_methods.any((m) => m['enabled'] == true)) {
      snack(context, 'Keep at least one payment method on.', error: true);
      return;
    }
    final cash = <int>[];
    for (final part in _cash.text.split(',')) {
      final text = part.trim();
      if (text.isEmpty) {
        continue;
      }
      final n = int.tryParse(text);
      if (n == null || n < 1) {
        snack(context, 'Cash shortcuts are whole amounts separated by commas.', error: true);
        return;
      }
      cash.add(n);
    }

    final b = widget.branch;
    final body = {
      for (final k in const [
        'name', 'name_bn', 'code', 'phone', 'address', 'address_bn', 'city', 'city_bn',
        'latitude', 'longitude', 'vat_percent', 'vat_inclusive', 'service_charge_percent',
        'allow_negative_stock', 'online_ordering_enabled', 'receipt_footer', 'is_active',
      ])
        k: b[k],
      'pos': {
        ..._pos,
        'invoice_pattern': _pattern.text.trim(),
        'invoice_seq_digits': digits,
        'cash_suggestions': cash,
      },
    };
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await app.api.put('/branches/${b['id']}', body: body);
      // The POS reads these from the saved bootstrap, so refresh it now.
      await app.loadBootstrap();
    });
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context, true);
      snack(context, 'POS settings saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('POS settings - ${widget.branch['code']}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const SectionTitle('Invoice'),
          DropdownButtonFormField<String>(
            initialValue: '${_pos['invoice_layout'] ?? 'classic'}',
            decoration: const InputDecoration(labelText: 'Receipt layout'),
            items: [for (final l in _layouts) DropdownMenuItem(value: l, child: Text(titleCase(l)))],
            onChanged: (v) => setState(() => _pos['invoice_layout'] = v),
          ),
          const SizedBox(height: 12),
          field(_pattern, 'Invoice number pattern'),
          Text(
            'Tokens: {BRANCH} {TERMINAL} {YYYY} {YY} {MM} {DD} {TIME} {RAND} {SEQ}. '
            'Use {TIME} and {RAND} so terminals that are offline never repeat a number. '
            '{SEQ} counts on the server and cannot be used offline.',
            style: TextStyle(fontSize: 12, color: context.muted),
          ),
          const SizedBox(height: 12),
          field(_digits, 'Counter digits (for {SEQ})', type: TextInputType.number),
          const SectionTitle('Payment methods'),
          for (final m in _methods)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${m['name'] ?? titleCase('${m['method']}')}'),
              subtitle: Text(titleCase('${m['type'] ?? ''}')),
              value: m['enabled'] == true,
              onChanged: (v) => setState(() => m['enabled'] = v),
            ),
          const SectionTitle('Cash shortcuts'),
          field(_cash, 'Amounts, separated by commas', type: TextInputType.text, hint: '1000, 500, 200, 100'),
          const SectionTitle('Sounds'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Play sounds'),
            value: _sounds['enabled'] == true,
            onChanged: (v) => setState(() => _sounds['enabled'] = v),
          ),
          Row(children: [
            const Text('Volume'),
            Expanded(
              child: Slider(
                value: toNum(_sounds['volume']).clamp(0, 100).toDouble(),
                max: 100,
                divisions: 20,
                label: '${toNum(_sounds['volume']).round()}',
                onChanged: _sounds['enabled'] == true ? (v) => setState(() => _sounds['volume'] = v.round()) : null,
              ),
            ),
          ]),
          const SectionTitle('Action buttons'),
          for (final entry in _actionLabels.entries)
            Card(
              child: ExpansionTile(
                title: Text(entry.value),
                children: [
                  for (final flag in _flagLabels.entries)
                    SwitchListTile(
                      dense: true,
                      title: Text(flag.value),
                      value: (_actions[entry.key] as Map)[flag.key] == true,
                      onChanged: (v) => setState(() => (_actions[entry.key] as Map)[flag.key] = v),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save POS settings'),
          ),
        ],
      ),
    );
  }
}
