import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../inventory/inventory_screens.dart';

/// Manager's dispatch board: delivery orders and rider assignment.
class DispatchScreen extends StatelessWidget {
  const DispatchScreen({super.key});

  Future<void> _assign(BuildContext context, Map<String, dynamic> order, Future<void> Function() reload) async {
    final app = AppScope.read(context);
    final ref = await loadReference(app);
    final riders = asRows(ref['riders']);
    final delivery = order['delivery'] as Map?;
    if (ref['riders'] == null) {
      if (context.mounted) {
        snack(context, 'Assigning riders needs the latest server update.', error: true);
      }
      return;
    }
    if (delivery == null) {
      if (context.mounted) {
        snack(context, 'This order has no delivery record yet.', error: true);
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    final rider = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Assign rider', style: Theme.of(ctx).textTheme.titleMedium),
          for (final r in riders)
            ListTile(
              leading: Icon(Icons.two_wheeler, color: r['is_on_duty'] == true ? Brand.success : context.muted),
              title: Text('${r['name']}'),
              subtitle: Text('${r['vehicle'] ?? ''}  ${r['is_on_duty'] == true ? 'On duty' : 'Off duty'}'),
              onTap: () => Navigator.pop(ctx, r),
            ),
          if (riders.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No active riders.')),
        ]),
      ),
    );
    if (rider == null || !context.mounted) {
      return;
    }
    final ok = await guarded(context, () async {
      await app.api.post('/deliveries/${delivery['id']}/assign', body: {'rider_id': rider['id']});
    });
    if (ok && context.mounted) {
      snack(context, 'Assigned to ${rider['name']}.');
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListModule(
      title: 'Delivery dispatch',
      path: '/branches/${app.branchId}/deliveries',
      itemBuilder: (context, o, reload) {
        final delivery = o['delivery'] as Map?;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${o['invoice_no']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                StatusChip('${delivery?['status'] ?? o['status']}'),
              ]),
              const SizedBox(height: 4),
              Text(fmtMoney(o['total'])),
              Text(
                delivery?['rider_id'] == null ? 'No rider assigned' : 'Rider #${delivery!['rider_id']}',
                style: TextStyle(color: context.muted, fontSize: 12),
              ),
              if (app.can('delivery.dispatch') && delivery != null && '${delivery['status']}' != 'delivered')
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _assign(context, o, reload),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(delivery['rider_id'] == null ? 'Assign rider' : 'Reassign'),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}

/// The rider's own deliveries and the cash they owe.
class RiderScreen extends StatelessWidget {
  const RiderScreen({super.key});

  static const _next = {'assigned': 'picked_up', 'picked_up': 'on_the_way', 'on_the_way': 'delivered'};

  Future<void> _update(BuildContext context, Map<String, dynamic> d, String status, Future<void> Function() reload) async {
    final app = AppScope.read(context);
    String? otp;
    String? reason;
    if (status == 'delivered' && d['otp_required'] == true) {
      final c = TextEditingController();
      final ok = await showForm<bool>(
        context,
        title: 'Customer code',
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          field(c, '4 digit delivery code', type: TextInputType.number),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm delivery')),
        ]),
      );
      otp = c.text.trim();
      c.dispose();
      if (ok != true) {
        return;
      }
    }
    if (status == 'failed') {
      if (!context.mounted) {
        return;
      }
      final c = TextEditingController();
      final ok = await showForm<bool>(
        context,
        title: 'Why could it not be delivered?',
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          field(c, 'Reason'),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark failed')),
        ]),
      );
      reason = c.text.trim();
      c.dispose();
      if (ok != true) {
        return;
      }
    }
    if (!context.mounted) {
      return;
    }
    final ok = await guarded(context, () async {
      await app.api.post('/rider/deliveries/${d['id']}/status',
          body: {'status': status, 'otp': ?otp, if (reason != null && reason.isNotEmpty) 'reason': reason});
    });
    if (ok && context.mounted) {
      snack(context, 'Updated to ${titleCase(status)}.');
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My deliveries'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Brand.soft,
            tabs: [Tab(text: 'Deliveries'), Tab(text: 'Cash to hand over')],
          ),
        ),
        body: TabBarView(children: [
          DataView<List<Map<String, dynamic>>>(
            path: '/rider/deliveries',
            transform: asRows,
            builder: (context, rows, raw, reload) => rows.isEmpty
                ? ListView(children: const [SizedBox(height: 120), EmptyState('No deliveries assigned.')])
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final d in rows)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('${(d['order'] as Map)['invoice_no']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                              StatusChip('${d['status']}'),
                            ]),
                            const SizedBox(height: 6),
                            Text('${(d['order'] as Map)['address'] ?? 'No address'}'),
                            if ((d['order'] as Map)['zone'] != null)
                              Text('${(d['order'] as Map)['zone']}', style: TextStyle(color: context.muted, fontSize: 12)),
                            const SizedBox(height: 6),
                            Text('Collect ${fmtMoney(d['cod_amount'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 10),
                            if (_next['${d['status']}'] != null)
                              Row(children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => _update(context, d, _next['${d['status']}']!, reload),
                                    child: Text('Mark ${titleCase(_next['${d['status']}']!)}'),
                                  ),
                                ),
                                if (d['status'] != 'assigned') ...[
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: () => _update(context, d, 'failed', reload),
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(80, 48)),
                                    child: const Text('Failed'),
                                  ),
                                ],
                              ]),
                          ]),
                        ),
                      ),
                  ]),
          ),
          DataView<Map<String, dynamic>>(
            path: '/rider/cod-summary',
            transform: (raw) => Map<String, dynamic>.from(raw as Map),
            builder: (context, cod, raw, reload) => ListView(padding: const EdgeInsets.all(16), children: [
              Metric('Cash to hand over', fmtMoney(cod['total']), icon: Icons.payments),
              const SizedBox(height: 8),
              Text('${cod['count']} delivered orders not yet settled', style: TextStyle(color: context.muted)),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  for (final d in asRows(cod['deliveries']))
                    ListTile(dense: true, title: Text('Delivery #${d['id']}'), trailing: Text(fmtMoney(d['cod_amount']))),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
