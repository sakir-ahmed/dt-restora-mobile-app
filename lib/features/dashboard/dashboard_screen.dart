import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// Today's numbers and low-stock alerts, plus this month's sales by day.
class DashboardSummary extends StatefulWidget {
  const DashboardSummary({super.key});

  @override
  State<DashboardSummary> createState() => _DashboardSummaryState();
}

class _DashboardSummaryState extends State<DashboardSummary> {
  Future<(Cached<dynamic>, Cached<dynamic>?)>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<(Cached<dynamic>, Cached<dynamic>?)> _load() async {
    final app = AppScope.read(context);
    final today = await app.cachedGet('/dashboard');
    Cached<dynamic>? month;
    if (app.can('reports.view')) {
      try {
        month = await app.cachedGet('/reports/sales');
      } on ApiException {
        month = null;
      }
    }
    return (today, month);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Padding(padding: const EdgeInsets.only(top: 12), child: Text('${snap.error}'));
        }
        final (today, month) = snap.data!;
        final summary = Map<String, dynamic>.from((today.data as Map)['summary'] as Map);
        final lowStock = asRows((today.data as Map)['low_stock']);
        final days = asRows(month?.data);
        final net = toNum(summary['net_profit']);

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle("Today", trailing: today.fromCache ? const Icon(Icons.cloud_off, size: 16) : null),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.9,
            children: [
              Metric('Net sales', fmtMoney(summary['net_sales']), icon: Icons.payments),
              Metric('Orders', '${summary['orders']}', icon: Icons.receipt_long),
              Metric('Food cost', fmtMoney(summary['food_cost']), icon: Icons.kitchen),
              Metric('Net profit', fmtMoney(net), icon: net < 0 ? Icons.trending_down : Icons.trending_up, negative: net < 0),
            ],
          ),
          if (lowStock.isNotEmpty) ...[
            const SectionTitle('Low stock'),
            Card(
              child: Column(children: [
                for (final s in lowStock.take(5))
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.warning_amber, color: Brand.warning),
                    title: Text('${s['name']}'),
                    trailing: Text('${s['stock_qty']} / ${s['reorder_level']} ${s['unit_symbol'] ?? ''}'),
                  ),
              ]),
            ),
          ],
          if (days.isNotEmpty) ...[
            const SectionTitle('Sales this month'),
            Card(
              child: Column(children: [
                for (final d in days.reversed.take(7))
                  ListTile(
                    dense: true,
                    title: Text(fmtDay(d['date'])),
                    subtitle: Text('${d['orders']} orders'),
                    trailing: Text(fmtMoney(d['net']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}
