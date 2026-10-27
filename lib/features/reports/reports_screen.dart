import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/generic_view.dart';
import '../../ui/widgets.dart';

const reportTypes = {
  'sales': 'Sales by day',
  'channel': 'Sales by channel',
  'payment-method': 'Payment methods',
  'cashier': 'Cashiers',
  'item-sales': 'Top items',
  'discount-void': 'Discounts and voids',
  'delivery': 'Delivery performance',
  'loyalty': 'Loyalty',
  'food-cost': 'Food cost',
  'wastage': 'Wastage',
  'stock-valuation': 'Stock valuation',
  'branch-pl': 'Branch profit and loss',
};

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final e in reportTypes.entries)
          Card(
            child: ListTile(
              leading: Icon(Icons.bar_chart, color: context.brand),
              title: Text(e.value),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen(type: e.key, title: e.value))),
            ),
          ),
      ]),
    );
  }
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.type, required this.title, this.basePath = '/reports'});

  final String type;
  final String title;
  final String basePath;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _to = DateTime.now();

  String _d(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _pick() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [IconButton(icon: const Icon(Icons.date_range), tooltip: 'Date range', onPressed: _pick)],
      ),
      body: DataView<Object?>(
        key: ValueKey('${_d(_from)}${_d(_to)}'),
        path: '${widget.basePath}/${widget.type}',
        query: {'from': _d(_from), 'to': _d(_to)},
        transform: (raw) => raw,
        builder: (context, data, raw, reload) => ListView(
          padding: const EdgeInsets.all(12),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${fmtDay(_from.toIso8601String())} to ${fmtDay(_to.toIso8601String())}',
                  style: TextStyle(color: context.muted)),
            ),
            GenericView(data),
          ],
        ),
      ),
    );
  }
}
