import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _mobile = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _adjust(Map<String, dynamic> c) async {
    final app = AppScope.read(context);
    final points = TextEditingController();
    final reason = TextEditingController();
    final go = await showForm<bool>(
      context,
      title: 'Adjust points for ${c['name']}',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        field(points, 'Points (use - to remove)', type: const TextInputType.numberWithOptions(signed: true)),
        field(reason, 'Reason'),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
      ]),
    );
    final p = int.tryParse(points.text);
    final r = reason.text.trim();
    points.dispose();
    reason.dispose();
    if (go != true || p == null || r.isEmpty || !mounted) {
      return;
    }
    await guarded(context, () async {
      final res = await app.api.post('/loyalty/adjust', body: {'customer_id': c['id'], 'points': p, 'reason': r}) as Map;
      if (mounted) {
        snack(context, 'New balance: ${res['balance']} points.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListModule(
      key: ValueKey(_mobile),
      title: 'Customers',
      path: '/customers',
      query: {if (_mobile.isNotEmpty) 'filter[mobile]': _mobile},
      header: TextField(
        controller: _search,
        keyboardType: TextInputType.phone,
        onSubmitted: (v) => setState(() => _mobile = v.trim()),
        decoration: InputDecoration(
          hintText: 'Find by mobile number',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          suffixIcon: _mobile.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    setState(() => _mobile = '');
                  },
                ),
        ),
      ),
      itemBuilder: (context, c, reload) => Card(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: context.pageBg, child: Icon(Icons.person, color: context.brand)),
          title: Text('${c['name']}'),
          subtitle: Text('${c['mobile']}'),
          trailing: app.can('loyalty.manage') ? const Icon(Icons.stars, color: Brand.warning) : null,
          onTap: app.can('loyalty.manage') ? () => _adjust(c) : null,
        ),
      ),
    );
  }
}

class CouponsScreen extends StatelessWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListModule(
      title: 'Coupons',
      path: '/coupons',
      itemBuilder: (context, c, reload) => Card(
        child: ListTile(
          title: Text('${c['code']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${c['type'] == 'percent' ? '${toNum(c['value']).toStringAsFixed(0)}% off' : '${fmtMoney(c['value'])} off'}'
            '${toNum(c['min_order']) > 0 ? '  -  min ${fmtMoney(c['min_order'])}' : ''}',
          ),
          trailing: Switch(
            value: c['is_active'] == true,
            onChanged: (v) async {
              final ok = await guarded(context, () async {
                await app.api.put('/coupons/${c['id']}', body: {
                  'code': c['code'],
                  'type': c['type'],
                  'value': toNum(c['value']),
                  'is_active': v,
                });
              });
              if (ok) {
                await reload();
              }
            },
          ),
        ),
      ),
      fab: (reload) => FloatingActionButton.extended(
        onPressed: () async {
          final code = TextEditingController();
          final value = TextEditingController();
          var type = 'percent';
          final go = await showForm<bool>(
            context,
            title: 'New coupon',
            builder: (ctx) => StatefulBuilder(
              builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                field(code, 'Code'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'percent', label: Text('Percent')),
                    ButtonSegment(value: 'fixed', label: Text('Fixed')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => set(() => type = s.first),
                ),
                const SizedBox(height: 12),
                field(value, 'Value', type: const TextInputType.numberWithOptions(decimal: true)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
              ]),
            ),
          );
          final v = double.tryParse(value.text);
          final c = code.text.trim().toUpperCase();
          code.dispose();
          value.dispose();
          if (go == true && v != null && c.isNotEmpty && context.mounted) {
            await guarded(context, () async {
              await app.api.post('/coupons', body: {'code': c, 'type': type, 'value': v});
            });
            await reload();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Coupon'),
      ),
    );
  }
}
