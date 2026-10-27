import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
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
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Extra bottom room so the action buttons always clear the
          // system gesture bar.
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
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

/// Kitchen display: live tickets by stage, polled every few seconds with
/// animated tickets, ticking timers and optimistic stage changes.
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  static const _stages = ['pending', 'preparing', 'ready'];
  static const _next = {'pending': 'preparing', 'preparing': 'ready', 'ready': 'served'};
  static const _advanceLabel = {'pending': 'Start preparing', 'preparing': 'Mark ready', 'ready': 'Mark served'};

  final _orders = {for (final s in _stages) s: <Map<String, dynamic>>[]};

  /// Stage a ticket was last rendered in, so the entrance animation only
  /// plays for genuinely new or moved tickets, not on every poll.
  final _seenStage = <Object, String>{};

  Timer? _poll;
  Timer? _ticker;
  bool _loading = true;
  bool _offline = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh(silent: true));
    // One tick per second keeps the elapsed-time badges counting live.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    final app = AppScope.read(context);
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        for (final s in _stages)
          app.cachedGet('/branches/${app.branchId}/orders', query: {'filter[status]': s, 'per_page': 50}),
      ]);
      if (!mounted) return;
      setState(() {
        _offline = results.any((r) => r.fromCache);
        for (var i = 0; i < _stages.length; i++) {
          _orders[_stages[i]] = _orderRows(results[i].data).reversed.toList();
        }
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && !silent) setState(() => _error = e.fullMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Move a ticket to its next stage at once; undo and report if the server refuses.
  Future<void> _advance(Map<String, dynamic> order, String from, String to) async {
    final app = AppScope.read(context);
    HapticFeedback.mediumImpact();
    setState(() {
      _orders[from] = _orders[from]!.where((o) => o['id'] != order['id']).toList();
      order['status'] = to;
      if (_orders.containsKey(to)) {
        _orders[to] = [order, ..._orders[to]!];
      }
    });
    final ok = await guarded(context, () async {
      await app.api.patch('/branches/${app.branchId}/orders/${order['id']}/status', body: {'status': to});
    });
    if (!ok && mounted) {
      setState(() {
        _orders[to] = _orders[to]!.where((o) => o['id'] != order['id']).toList();
        order['status'] = from;
        _orders[from] = [..._orders[from]!, order];
      });
    }
    unawaited(_refresh(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    final empty = _orders.values.every((l) => l.isEmpty);
    return DefaultTabController(
      length: _stages.length,
      child: Scaffold(
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Kitchen'),
            const SizedBox(width: 10),
            _PulseDot(color: _offline ? Brand.warning : Brand.success),
            const SizedBox(width: 6),
            Text(_offline ? 'Saved data' : 'Live',
                style: const TextStyle(fontSize: 12, color: Brand.soft, fontWeight: FontWeight.w600)),
          ]),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < _stages.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _CountBadge(stage: _stages[i], count: _orders[_stages[i]]!.length),
                ],
              ]),
            ),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Brand.soft,
            tabs: [for (final s in _stages) Tab(text: titleCase(s))],
          ),
        ),
        body: Column(children: [
          if (_offline) const OfflineNote(null),
          Expanded(
            child: _error != null && empty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: () => _refresh(), child: const Text('Try again')),
                      ]),
                    ),
                  )
                : _loading && empty
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(children: [for (final s in _stages) _stage(s)]),
          ),
        ]),
      ),
    );
  }

  Widget _stage(String stage) {
    final bottomPad = 24 + MediaQuery.paddingOf(context).bottom;
    final orders = _orders[stage]!;
    final emptyText = switch (stage) {
      'pending' => 'No new tickets. Enjoy the calm!',
      'preparing' => 'Nothing on the stove right now.',
      _ => 'Nothing waiting to be served.',
    };
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _refresh(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [SizedBox(height: 160), EmptyState(emptyText)],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refresh(silent: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPad),
        itemCount: orders.length,
        itemBuilder: (context, i) {
          final o = orders[i];
          final id = o['id'];
          final animate = _seenStage[id] != stage;
          _seenStage[id] = stage;
          return _KdsTicket(
            key: ValueKey('kds-$id'),
            order: o,
            stage: stage,
            index: i,
            animate: animate,
            onAdvance: () => _advance(o, stage, _next[stage]!),
          );
        },
      ),
    );
  }
}

class _KdsTicket extends StatefulWidget {
  const _KdsTicket({
    super.key,
    required this.order,
    required this.stage,
    required this.index,
    required this.animate,
    required this.onAdvance,
  });

  final Map<String, dynamic> order;
  final String stage;
  final int index;
  final bool animate;
  final VoidCallback onAdvance;

  @override
  State<_KdsTicket> createState() => _KdsTicketState();
}

class _KdsTicketState extends State<_KdsTicket> with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.animate ? 0 : 1,
  );
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      // A short stagger per row so a fresh batch cascades in.
      _delay = Timer(Duration(milliseconds: widget.index.clamp(0, 6) * 45), () {
        if (mounted) _enter.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final o = widget.order;
    final created = DateTime.tryParse('${o['created_at']}')?.toLocal();
    final elapsed = created == null ? Duration.zero : DateTime.now().difference(created);
    final mins = elapsed.inMinutes;
    final warnAfter = widget.stage == 'preparing' ? 12 : 5;
    final dangerAfter = widget.stage == 'preparing' ? 22 : 10;
    final urgency = mins >= dangerAfter ? Brand.danger : mins >= warnAfter ? Brand.warning : Brand.success;
    final items = asRows(o['items']);
    final fresh = elapsed.inMinutes < 1;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _enter, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero)
            .animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic)),
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0)
              .animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic)),
          child: Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (fresh) ...[
                    _PulseDot(color: Brand.primary, size: 7),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text('${o['invoice_no']}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  _TypeChip('${o['order_type']}', table: o['table']),
                  const SizedBox(width: 6),
                  _ElapsedBadge(elapsed: elapsed, color: urgency),
                ]),
                const SizedBox(height: 10),
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 36,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.brand.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${i['quantity']}',
                            style: TextStyle(fontWeight: FontWeight.w800, color: context.brand)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(localized(app, i), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          if (asRows(i['add_ons']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+ ${asRows(i['add_ons']).map((a) => localized(app, a)).join(', ')}',
                                style: TextStyle(fontSize: 12, color: context.muted),
                              ),
                            ),
                        ]),
                      ),
                    ]),
                  ),
                const SizedBox(height: 6),
                Row(children: [
                  if (o['created_at'] != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(fmtDate(o['created_at']), style: TextStyle(fontSize: 11, color: context.muted)),
                    ),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onAdvance,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: Text(_KitchenScreenState._advanceLabel[widget.stage]!),
                      style: FilledButton.styleFrom(
                        backgroundColor: urgency == Brand.danger ? Brand.danger : null,
                        minimumSize: const Size.fromHeight(40),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Softly pulsing dot used for the Live badge and fresh tickets.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.6, end: 1.4).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Opacity(
        opacity: 0.4 + 0.6 * _pulse.value,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Ticket count per stage, shown in the app bar.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.stage, required this.count});

  final String stage;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = switch (stage) {
      'pending' => Brand.warning,
      'preparing' => Brand.accent,
      _ => Brand.success,
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: count == 0 ? Colors.white.withValues(alpha: 0.10) : color,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text('$count',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}

/// Order type with icon; shows the table number for dine-in.
class _TypeChip extends StatelessWidget {
  const _TypeChip(this.type, {this.table});

  final String type;
  final Object? table;

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      'dine_in' => Icons.restaurant,
      'takeaway' => Icons.shopping_bag,
      'delivery' => Icons.delivery_dining,
      _ => Icons.receipt_outlined,
    };
    final label = table != null ? 'Table $table' : titleCase(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.brand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: context.brand),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.brand)),
      ]),
    );
  }
}

/// Time since the order was placed; ticks every second, colored by urgency.
class _ElapsedBadge extends StatelessWidget {
  const _ElapsedBadge({required this.elapsed, required this.color});

  final Duration elapsed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = elapsed.inHours > 0
        ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m'
        : elapsed.inMinutes > 0
            ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s'
            : '${elapsed.inSeconds}s';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined, size: 13, color: color),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ]),
    );
  }
}
