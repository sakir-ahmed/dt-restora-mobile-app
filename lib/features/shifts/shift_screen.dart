import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../inventory/inventory_screens.dart';

/// Cashier cash shift. Opening and closing both work offline.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  Future<Map<String, dynamic>>? _ref;
  Map<String, dynamic>? _closeResult;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ref ??= loadReference(AppScope.read(context));
  }

  Future<void> _reload() async {
    final next = loadReference(AppScope.read(context));
    setState(() {
      _ref = next;
    });
    await next;
  }

  Future<void> _open(Map<String, dynamic>? current) async {
    final app = AppScope.read(context);
    final cash = TextEditingController(text: '0');
    final go = await showForm<bool>(
      context,
      title: 'Open shift',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        field(cash, 'Opening cash', type: const TextInputType.numberWithOptions(decimal: true)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open shift')),
      ]),
    );
    final amount = double.tryParse(cash.text) ?? 0;
    cash.dispose();
    if (go != true || !mounted) {
      return;
    }
    try {
      await app.api.post('/branches/${app.branchId}/shifts/open', body: {'opening_cash': amount, 'terminal': 'T01'});
      if (mounted) {
        snack(context, 'Shift opened.');
      }
    } on ApiException catch (e) {
      if (!e.isNetwork) {
        if (mounted) {
          snack(context, e.fullMessage, error: true);
        }
        return;
      }
      await app.queue('shift', {'action': 'open', 'branch_id': app.branchId, 'opening_cash': amount, 'terminal': 'T01'},
          label: 'Open shift');
      if (mounted) {
        snack(context, 'Offline: shift opening saved. Will sync.');
      }
    }
    await _reload();
  }

  Future<void> _close(Map<String, dynamic>? shift) async {
    final app = AppScope.read(context);
    final counted = TextEditingController();
    final go = await showForm<bool>(
      context,
      title: 'Close shift',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (shift != null) ...[
          Text('Opened with ${fmtMoney(shift['opening_cash'])}', style: TextStyle(color: context.muted)),
          const SizedBox(height: 12),
        ],
        field(counted, 'Cash counted in drawer', type: const TextInputType.numberWithOptions(decimal: true)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close shift')),
      ]),
    );
    final amount = double.tryParse(counted.text);
    counted.dispose();
    if (go != true || amount == null || !mounted) {
      return;
    }
    if (shift == null) {
      // The server did not tell us the shift id: let the sync service find
      // this cashier's open shift.
      final sent = await app.queue('shift', {'action': 'close', 'branch_id': app.branchId, 'counted_cash': amount},
          label: 'Close shift');
      if (mounted) {
        snack(context, sent ? 'Shift closed.' : 'Saved on this device. Will sync when online.');
      }
      await _reload();
      return;
    }
    try {
      final res = await app.api.post('/shifts/${shift['id']}/close', body: {'counted_cash': amount});
      setState(() => _closeResult = Map<String, dynamic>.from(res as Map));
    } on ApiException catch (e) {
      if (!e.isNetwork) {
        if (mounted) {
          snack(context, e.fullMessage, error: true);
        }
        return;
      }
      await app.queue('shift', {'action': 'close', 'branch_id': app.branchId, 'counted_cash': amount}, label: 'Close shift');
      if (mounted) {
        snack(context, 'Offline: shift close saved. Will sync.');
      }
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cash shift')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _ref,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final ref = snap.data!;
          final known = ref.containsKey('current_shift');
          final shift = ref['current_shift'] == null ? null : Map<String, dynamic>.from(ref['current_shift'] as Map);
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
              if (!known) ...[
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Shift status unavailable'),
                    subtitle: Text('Open a shift at the start of the day and close it when you count the drawer.'),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => _open(null), child: const Text('Open shift')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _close(null), child: const Text('Close shift')),
              ] else if (shift == null) ...[
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('No open shift'),
                    subtitle: Text('Open a shift before taking cash payments.'),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => _open(null), child: const Text('Open shift')),
              ] else ...[
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.lock_open, color: Brand.success),
                      title: const Text('Shift open'),
                      subtitle: Text('Since ${fmtDate(shift['opened_at'])}  -  Terminal ${shift['terminal_code']}'),
                    ),
                    ListTile(title: const Text('Opening cash'), trailing: Text(fmtMoney(shift['opening_cash']))),
                  ]),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => _close(shift), child: const Text('Close shift')),
              ],
              if (_closeResult != null) ...[
                const SectionTitle('Last closed shift'),
                Card(
                  child: Column(children: [
                    ListTile(title: const Text('Expected cash'), trailing: Text(fmtMoney(_closeResult!['expected_cash']))),
                    ListTile(title: const Text('Counted cash'), trailing: Text(fmtMoney(_closeResult!['counted_cash']))),
                    ListTile(
                      title: const Text('Difference'),
                      trailing: Text(fmtMoney(_closeResult!['difference']),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: toNum(_closeResult!['difference']) == 0 ? null : Brand.danger)),
                    ),
                  ]),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }
}
