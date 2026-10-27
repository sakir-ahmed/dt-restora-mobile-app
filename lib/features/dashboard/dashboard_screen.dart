import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// Full-page dashboard: today's numbers, the month's sales as an animated
/// chart and low-stock alerts. Kept off the home page so the home list
/// stays short and nothing shifts while data loads.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<(Cached<dynamic>, Cached<dynamic>?)>? _future;
  (Cached<dynamic>, Cached<dynamic>?)? _peek;
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
    if (!_seeded) {
      _seeded = true;
      unawaited(_seedFromCache());
    }
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

  /// Paint the last saved copy at once while the network answers.
  Future<void> _seedFromCache() async {
    final app = AppScope.read(context);
    final today = await app.peekCache('/dashboard');
    if (today == null || !mounted) {
      return;
    }
    Cached<dynamic>? month;
    if (app.can('reports.view')) {
      month = await app.peekCache('/reports/sales');
    }
    if (mounted) {
      setState(() => _peek ??= (today, month));
    }
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } on ApiException {
      // Shown by the builder below.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.done && !snap.hasError) {
            final (today, month) = snap.data!;
            return _body(context, today, month);
          }
          final peek = _peek;
          if (peek != null) {
            return _body(context, peek.$1, peek.$2);
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: _reload, child: const Text('Try again')),
                ]),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _body(BuildContext context, Cached<dynamic> today, Cached<dynamic>? month) {
    final summary = Map<String, dynamic>.from((today.data as Map)['summary'] as Map);
    final lowStock = asRows((today.data as Map)['low_stock']);
    final days = asRows(month?.data);
    final net = toNum(summary['net_profit']);

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SectionTitle('Today', trailing: today.fromCache ? const Icon(Icons.cloud_off, size: 16) : null),
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
          if (days.isNotEmpty) ...[
            const SectionTitle('Sales this month'),
            _MonthBarChart(days: days),
          ],
          if (lowStock.isNotEmpty) ...[
            const SectionTitle('Low stock'),
            Card(
              child: Column(children: [
                for (final s in lowStock)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.warning_amber, color: Brand.warning),
                    title: Text('${s['name']}'),
                    trailing: Text('${s['stock_qty']} / ${s['reorder_level']} ${s['unit_symbol'] ?? ''}'),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Daily net sales for the month as an animated bar chart. The latest day
/// is highlighted; tap any bar for that day's numbers.
class _MonthBarChart extends StatelessWidget {
  const _MonthBarChart({required this.days});

  final List<Map<String, dynamic>> days;

  @override
  Widget build(BuildContext context) {
    final data = days.skip(max(0, days.length - 14)).toList();
    var maxNet = 0.0, sum = 0.0;
    Map<String, dynamic>? best;
    for (final d in data) {
      final net = toNum(d['net']);
      sum += net;
      if (net > maxNet) {
        maxNet = net;
      }
      if (net >= toNum(best?['net'] ?? 0)) {
        best = d;
      }
    }
    if (data.isEmpty || maxNet <= 0) {
      return const Card(child: Padding(padding: EdgeInsets.all(20), child: EmptyState('No sales recorded yet.')));
    }
    final avg = sum / data.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _ChartStat('Best day', fmtMoney(best!['net']), sub: fmtDay(best['date']))),
            const SizedBox(width: 12),
            Expanded(child: _ChartStat('Daily average', fmtMoney(avg), sub: '${data.length} days')),
          ]),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < data.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => snack(context,
                            '${fmtDay(data[i]['date'])}: ${fmtMoney(data[i]['net'])} - ${data[i]['orders']} orders'),
                        child: Column(children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: (toNum(data[i]['net']) / maxNet * t).clamp(0.02, 1),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: i == data.length - 1
                                          ? null
                                          : context.brand.withValues(alpha: 0.30),
                                      gradient: i == data.length - 1
                                          ? LinearGradient(
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                              colors: [
                                                brandColors(AppScope.of(context).brandKey).$1,
                                                brandColors(AppScope.of(context).brandKey).$2,
                                              ],
                                            )
                                          : null,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 16,
                            child: Text(
                              '${DateTime.tryParse('${data[i]['date']}')?.day ?? ''}',
                              style: TextStyle(fontSize: 10, color: context.muted),
                            ),
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Tap a bar for that day\'s numbers.',
              style: TextStyle(fontSize: 11, color: context.muted)),
        ]),
      ),
    );
  }
}

class _ChartStat extends StatelessWidget {
  const _ChartStat(this.label, this.value, {this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, color: context.muted)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
      if (sub != null) Text(sub!, style: TextStyle(fontSize: 10, color: context.muted)),
    ]);
  }
}
