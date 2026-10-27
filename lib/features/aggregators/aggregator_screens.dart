import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// Delivery-app channels (Foodpanda, Foodi, ...): commission, status,
/// menu sync, and accept or reject for incoming platform orders.
class AggregatorsScreen extends StatelessWidget {
  const AggregatorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListModule(
      title: 'Delivery apps',
      path: '/aggregators/channels',
      itemBuilder: (context, ch, reload) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.hub, color: context.brand),
              const SizedBox(width: 10),
              Expanded(child: Text('${ch['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              Switch(
                value: ch['is_active'] == true,
                onChanged: (v) async {
                  final ok = await guarded(context, () async {
                    await app.api.put('/aggregators/channels/${ch['id']}',
                        body: {'commission_percent': toNum(ch['commission_percent']), 'is_active': v});
                  });
                  if (ok) {
                    await reload();
                  }
                },
              ),
            ]),
            Text('Commission ${toNum(ch['commission_percent']).toStringAsFixed(1)}%  -  ${titleCase('${ch['environment'] ?? ''}')}',
                style: TextStyle(color: context.muted)),
            if (ch['last_error'] != null)
              Text('${ch['last_error']}', style: const TextStyle(color: Brand.danger, fontSize: 12)),
            Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () async {
                  final c = TextEditingController(text: toNum(ch['commission_percent']).toString());
                  final go = await showForm<bool>(
                    context,
                    title: '${ch['name']} commission',
                    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      field(c, 'Commission percent', type: const TextInputType.numberWithOptions(decimal: true)),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
                    ]),
                  );
                  final v = double.tryParse(c.text);
                  c.dispose();
                  if (go == true && v != null && context.mounted) {
                    await guarded(context, () async {
                      await app.api.put('/aggregators/channels/${ch['id']}',
                          body: {'commission_percent': v, 'is_active': ch['is_active'] == true});
                    });
                    await reload();
                  }
                },
                child: const Text('Edit commission'),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await guarded(context, () async {
                    final res = await app.api.post('/aggregators/menu-sync',
                        body: {'aggregator_channel_id': ch['id'], 'branch_id': app.branchId}) as Map;
                    if (context.mounted) {
                      snack(context, 'Menu synced: ${res['items']} items.');
                    }
                  });
                  if (ok) {
                    await reload();
                  }
                },
                child: const Text('Sync menu'),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ManualAggregatorOrderScreen(channel: ch)),
                ),
                child: const Text('Manual order'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class ManualAggregatorOrderScreen extends StatefulWidget {
  const ManualAggregatorOrderScreen({super.key, required this.channel});

  final Map<String, dynamic> channel;

  @override
  State<ManualAggregatorOrderScreen> createState() => _ManualAggregatorOrderScreenState();
}

class _ManualAggregatorOrderScreenState extends State<ManualAggregatorOrderScreen> {
  final _platformId = TextEditingController();
  final Map<int, int> _qty = {};
  bool _busy = false;
  Map<String, dynamic>? _created;

  @override
  void dispose() {
    _platformId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final items = [
      for (final e in _qty.entries)
        if (e.value > 0) {'menu_item_id': e.key, 'quantity': e.value}
    ];
    if (_platformId.text.trim().isEmpty || items.isEmpty) {
      snack(context, 'Enter the platform order number and at least one item.', error: true);
      return;
    }
    setState(() => _busy = true);
    await guarded(context, () async {
      final res = await app.api.post('/branches/${app.branchId}/orders/manual-aggregator', body: {
        'aggregator_channel_id': widget.channel['id'],
        'platform_order_id': _platformId.text.trim(),
        'items': items,
      }) as Map;
      setState(() {
        _created = Map<String, dynamic>.from(res);
        _qty.clear();
        _platformId.clear();
      });
    });
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _decide(String decision) async {
    final app = AppScope.read(context);
    await guarded(context, () async {
      await app.api.post('/aggregators/orders/${_created!['id']}/$decision');
      if (mounted) {
        snack(context, 'Order ${decision}ed.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final items = [for (final c in asRows(app.bootstrap?['categories'])) ...asRows(c['items'])];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.channel['name']} order')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_created != null)
          Card(
            color: Brand.success.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Created ${_created!['invoice_no']}  -  ${fmtMoney(_created!['total'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Row(children: [
                  TextButton(onPressed: () => _decide('accept'), child: const Text('Accept')),
                  TextButton(onPressed: () => _decide('reject'), child: const Text('Reject')),
                ]),
              ]),
            ),
          ),
        field(_platformId, 'Platform order number'),
        for (final i in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(localized(app, i)),
            subtitle: Text(fmtMoney(i['base_price'])),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() => _qty[(i['id'] as num).toInt()] = ((_qty[(i['id'] as num).toInt()] ?? 0) - 1).clamp(0, 99)),
              ),
              Text('${_qty[(i['id'] as num).toInt()] ?? 0}'),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _qty[(i['id'] as num).toInt()] = (_qty[(i['id'] as num).toInt()] ?? 0) + 1),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Create order')),
      ]),
    );
  }
}
