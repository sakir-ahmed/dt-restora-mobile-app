import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'payment_sheet.dart';
import 'receipt.dart';

const voidReasons = {
  'wrong_item': 'Wrong item was ordered',
  'customer_changed_mind': 'Customer changed their mind',
  'kitchen_mistake': 'Kitchen mistake',
  'duplicate_order': 'Duplicate order',
  'payment_failed': 'Payment failed',
  'other': 'Other reason',
};

List<Map<String, dynamic>> _orderRows(dynamic raw) => asRows((raw as Map)['orders']);

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListModule(
      key: ValueKey(_status),
      title: 'Orders',
      path: '/branches/${app.branchId}/orders',
      query: {'per_page': 50, if (_status != null) 'filter[status]': _status},
      extract: _orderRows,
      header: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final s in [null, 'pending', 'preparing', 'ready', 'served', 'paid', 'void'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(s == null ? 'All' : titleCase(s)),
                selected: _status == s,
                onSelected: (_) => setState(() => _status = s),
              ),
            ),
        ]),
      ),
      itemBuilder: (context, o, reload) => OrderCard(order: o, onChanged: reload),
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.onChanged});

  final Map<String, dynamic> order;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final items = asRows(order['items']);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)));
          await onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${order['invoice_no']}', style: const TextStyle(fontWeight: FontWeight.w700))),
              StatusChip('${order['status']}'),
            ]),
            const SizedBox(height: 4),
            Text(
              [
                titleCase('${order['order_type']}'),
                if (order['table'] != null) 'Table ${order['table']}',
                '${items.fold<int>(0, (s, i) => s + ((i['quantity'] as num?)?.toInt() ?? 0))} items',
                if (order['created_at'] != null) fmtDate(order['created_at']),
              ].join('  -  '),
              style: TextStyle(color: context.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(fmtMoney(order['total']), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Map<String, dynamic> _order = widget.order;

  @override
  void initState() {
    super.initState();
    // The list payload is lighter than the detail payload; load the full one.
    WidgetsBinding.instance.addPostFrameCallback((_) => guarded(context, _refresh));
  }

  Future<void> _refresh() async {
    final app = AppScope.read(context);
    final fresh = await app.api.get('/branches/${app.branchId}/orders/${_order['id']}');
    if (mounted) {
      setState(() => _order = Map<String, dynamic>.from(fresh as Map));
    }
  }

  Future<void> _setStatus(String status) async {
    final app = AppScope.read(context);
    final ok = await guarded(context, () async {
      await app.api.patch('/branches/${app.branchId}/orders/${_order['id']}/status', body: {'status': status});
      await _refresh();
    });
    if (ok && mounted) {
      snack(context, 'Marked ${titleCase(status)}.');
    }
  }

  Future<void> _pay() async {
    final msg = await showPaymentSheet(context,
        orderId: (_order['id'] as num).toInt(), invoiceNo: '${_order['invoice_no']}', total: _order['total']);
    if (msg != null && mounted) {
      snack(context, msg);
      await guarded(context, _refresh);
    }
  }

  Future<void> _void() async {
    final app = AppScope.read(context);
    var reason = voidReasons.keys.first;
    final note = TextEditingController();
    final send = await showForm<bool>(
      context,
      title: 'Cancel this order (void)',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ctx.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'A void cancels the whole order, for example when it was entered by mistake, the customer changed their mind, '
              'or the payment failed. A manager has to approve it. Once approved, the sale is reversed and the ingredients '
              'go back into stock. Every void is recorded with who asked and why.',
              style: TextStyle(fontSize: 13, color: ctx.muted, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: reason,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: [for (final e in voidReasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => set(() => reason = v!),
          ),
          const SizedBox(height: 12),
          field(note, 'Note for the manager (optional)'),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(app.can('orders.void') ? 'Void order' : 'Send request to manager'),
          ),
        ]),
      ),
    );
    final noteText = note.text;
    note.dispose();
    if (send != true || !mounted) {
      return;
    }
    await guarded(context, () async {
      final res = await app.api.post('/branches/${app.branchId}/orders/${_order['id']}/void-requests',
          body: {'reason_code': reason, if (noteText.isNotEmpty) 'note': noteText}) as Map;
      if (!mounted) {
        return;
      }
      if (app.can('orders.void') && await confirm(context, 'Approve this void now?', body: 'You can approve it yourself because you are a manager.', action: 'Approve')) {
        await app.api.post('/void-requests/${res['id']}/approve');
        await _refresh();
        if (mounted) {
          snack(context, 'Order voided and stock restored.');
        }
      } else {
        await _refresh();
        if (mounted) {
          snack(context, 'Void request sent. A manager will approve it.');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final status = '${_order['status']}';
    final items = asRows(_order['items']);
    const flow = ['pending', 'preparing', 'ready', 'served', 'paid'];
    final step = flow.indexOf(status);
    final next = step >= 0 && step < flow.length - 2 ? flow[step + 1] : null;
    final voidPending = '${_order['void_status']}' == 'pending';
    final canPay = status != 'paid' && status != 'void';
    final totals = <MapEntry<String, String>>[
      MapEntry('Subtotal', fmtMoney(_order['subtotal'] ?? _order['total'])),
      if (toNum(_order['discount_amount']) > 0) MapEntry('Discount', '-${fmtMoney(_order['discount_amount'])}'),
      if (toNum(_order['service_charge']) > 0) MapEntry('Service charge', fmtMoney(_order['service_charge'])),
      if (toNum(_order['vat_amount']) > 0) MapEntry('VAT', fmtMoney(_order['vat_amount'])),
      if (toNum(_order['delivery_fee']) > 0) MapEntry('Delivery fee', fmtMoney(_order['delivery_fee'])),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${_order['invoice_no']}'),
        actions: [
          if (status == 'paid')
            IconButton(
              tooltip: 'Print receipt',
              icon: const Icon(Icons.print),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScreen(orderId: (_order['id'] as num).toInt()))),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => guarded(context, _refresh),
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
          Row(children: [
            StatusChip(status),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  titleCase('${_order['order_type']}'),
                  if (_order['table'] != null) 'Table ${_order['table']}',
                  if (_order['created_at'] != null) fmtDate(_order['created_at']),
                ].join('  -  '),
                style: TextStyle(color: context.muted, fontSize: 12),
              ),
            ),
          ]),
          if (step >= 0 && status != 'void') ...[
            const SizedBox(height: 12),
            Row(children: [
              for (var i = 0; i < flow.length; i++) ...[
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: i <= step ? context.brand : context.lineColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                if (i < flow.length - 1) const SizedBox(width: 4),
              ],
            ]),
            const SizedBox(height: 4),
            Text('Step ${step + 1} of ${flow.length}: ${titleCase(status)}', style: TextStyle(color: context.muted, fontSize: 11)),
          ],
          if (voidPending)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.warnBg, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(Icons.hourglass_top, size: 18, color: context.warnFg),
                  const SizedBox(width: 8),
                  Expanded(child: Text('A void request is waiting for manager approval.', style: TextStyle(color: context.warnFg))),
                ]),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              for (final i in items)
                ListTile(
                  dense: true,
                  title: Text(localized(app, i)),
                  subtitle: Text(
                    'Qty ${i['quantity']}${i['unit_price'] == null ? '' : '  x  ${fmtMoney(i['unit_price'])}'}'
                    '${asRows(i['add_ons']).isEmpty ? '' : '\n+ ${asRows(i['add_ons']).map((a) => a['name']).join(', ')}'}',
                  ),
                  trailing: Text(fmtMoney(i['line_total']), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              const Divider(height: 1),
              for (final t in totals)
                ListTile(dense: true, visualDensity: VisualDensity.compact, title: Text(t.key), trailing: Text(t.value)),
              ListTile(
                title: const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
                trailing: Text(fmtMoney(_order['total']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ]),
          ),
          if (asRows(_order['payments']).isNotEmpty) ...[
            const SectionTitle('Payments'),
            Card(
              child: Column(children: [
                for (final p in asRows(_order['payments']))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(titleCase('${p['method']}')),
                    trailing: Text(fmtMoney(p['amount']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          if (next != null && app.can('orders.create'))
            FilledButton.icon(
              onPressed: () => _setStatus(next),
              icon: const Icon(Icons.arrow_forward),
              label: Text('Mark ${titleCase(next)}'),
            ),
          if (canPay && (app.can('payments.manage') || app.can('pos.access'))) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: _pay, icon: const Icon(Icons.payments), label: const Text('Take payment')),
          ],
          if (status == 'paid') ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScreen(orderId: (_order['id'] as num).toInt()))),
              icon: const Icon(Icons.receipt),
              label: const Text('Receipt and print'),
            ),
          ],
          if (status != 'void' && app.can('orders.create') && !voidPending) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Brand.danger),
              onPressed: _void,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel order (void)'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Kitchen display: active tickets grouped by stage, refreshed regularly.
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  Timer? _timer;
  final _keys = {
    for (final s in ['pending', 'preparing', 'ready']) s: GlobalKey<DataViewState<List<Map<String, dynamic>>>>(),
  };

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      for (final k in _keys.values) {
        k.currentState?.reload();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    const stages = {'pending': 'preparing', 'preparing': 'ready', 'ready': 'served'};
    return DefaultTabController(
      length: stages.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kitchen'),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Brand.soft,
            tabs: [for (final s in stages.keys) Tab(text: titleCase(s))],
          ),
        ),
        body: TabBarView(children: [
          for (final entry in stages.entries)
            DataView<List<Map<String, dynamic>>>(
              key: _keys[entry.key],
              path: '/branches/${app.branchId}/orders',
              query: {'filter[status]': entry.key, 'per_page': 50},
              transform: _orderRows,
              builder: (context, rows, raw, reload) => rows.isEmpty
                  ? ListView(children: const [SizedBox(height: 120), EmptyState('No tickets.')])
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      for (final o in rows.reversed)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text('${o['invoice_no']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                                Text(titleCase('${o['order_type']}'), style: TextStyle(color: context.muted, fontSize: 12)),
                              ]),
                              const SizedBox(height: 6),
                              for (final i in asRows(o['items']))
                                Text('${i['quantity']} x ${i['name']}', style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 10),
                              FilledButton(
                                onPressed: () async {
                                  final ok = await guarded(context, () async {
                                    await app.api.patch('/branches/${app.branchId}/orders/${o['id']}/status',
                                        body: {'status': entry.value});
                                  });
                                  if (ok) {
                                    for (final k in _keys.values) {
                                      unawaited(k.currentState?.reload());
                                    }
                                  }
                                },
                                child: Text('Mark ${titleCase(entry.value)}'),
                              ),
                            ]),
                          ),
                        ),
                    ]),
            ),
        ]),
      ),
    );
  }
}
