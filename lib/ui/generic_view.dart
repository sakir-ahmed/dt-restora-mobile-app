import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'widgets.dart';

/// Renders any JSON report (maps, lists of rows, nested sections) as
/// readable cards, so every report type works without its own layout.
class GenericView extends StatelessWidget {
  const GenericView(this.data, {super.key});

  final Object? data;

  static bool _isMoneyKey(String key) => RegExp(
          r'(total|amount|sales|net|gross|cost|profit|revenue|debit|credit|balance|value|vat|discount|fee|expenses|salary|commission|current|days_|older|price|cash)')
      .hasMatch(key);

  static String _cell(String key, Object? v) {
    if (v == null) {
      return '-';
    }
    if (v is bool) {
      return v ? 'Yes' : 'No';
    }
    if (v is String && RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(v)) {
      return fmtDay(v);
    }
    if ((v is num || (v is String && num.tryParse(v) != null)) && _isMoneyKey(key) && !key.endsWith('_id') && key != 'id') {
      return fmtMoney(v);
    }
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d is List) {
      final rows = d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (rows.isEmpty) {
        return const EmptyState('No data for this period.');
      }
      return Column(children: [for (final r in rows) _RowCard(r)]);
    }
    if (d is Map) {
      final map = Map<String, dynamic>.from(d);
      final scalars = map.entries.where((e) => e.value is! List && e.value is! Map).toList();
      final nested = map.entries.where((e) => e.value is List || e.value is Map).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (scalars.isNotEmpty)
          Card(
            child: Column(children: [
              for (final e in scalars)
                ListTile(dense: true, title: Text(titleCase(e.key)), trailing: Text(_cell(e.key, e.value), style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        for (final e in nested) ...[
          SectionTitle(titleCase(e.key)),
          GenericView(e.value),
        ],
      ]);
    }
    return Text('${d ?? ''}');
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard(this.row);

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final entries = row.entries.where((e) => e.value is! List && e.value is! Map && e.key != 'created_at' && e.key != 'updated_at').toList();
    final first = entries.isEmpty ? null : entries.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (first != null)
            Text(GenericView._cell(first.key, first.value), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          for (final e in entries.skip(1))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(children: [
                Expanded(child: Text(titleCase(e.key), style: TextStyle(color: context.muted, fontSize: 12))),
                Text(GenericView._cell(e.key, e.value), style: const TextStyle(fontSize: 13)),
              ]),
            ),
        ]),
      ),
    );
  }
}
