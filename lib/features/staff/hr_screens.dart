import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/sounds.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// The day's attendance board: punch staff in and out, like the web page.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Future<Cached<dynamic>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<Cached<dynamic>> _load() =>
      AppScope.read(context).cachedGet('/branches/${AppScope.read(context).branchId}/attendance/today');

  Future<void> _reload() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } on ApiException {
      // Shown by the builder.
    }
  }

  Future<void> _punch(Map<String, dynamic> employee, String direction) async {
    final app = AppScope.read(context);
    final ok = await guarded(context, () async {
      await app.api.post('/branches/${app.branchId}/attendance/punch',
          body: {'employee_id': employee['id'], 'direction': direction});
    });
    if (ok) {
      SoundFx.play('notification');
      await _reload();
    }
  }

  String? _time(Object? v) {
    final d = v == null ? null : DateTime.tryParse('$v')?.toLocal();
    return d == null ? null : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance today')),
      body: FutureBuilder<Cached<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: _reload, child: const Text('Try again')),
              ]),
            );
          }
          final data = Map<String, dynamic>.from(snap.data!.data as Map);
          final employees = asRows(data['employees']);
          final byEmployee = {
            for (final a in asRows(data['attendance'])) a['employee_id']: a,
          };
          return RefreshIndicator(
            onRefresh: _reload,
            child: employees.isEmpty
                ? ListView(children: const [SizedBox(height: 160), EmptyState('No staff on this branch.')])
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: employees.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final e = employees[i];
                      final a = byEmployee[e['id']];
                      final clockIn = _time(a?['clock_in']);
                      final clockOut = _time(a?['clock_out']);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: context.brand.withValues(alpha: 0.1),
                            child: Text(
                              '${e['name']}'.isEmpty ? '?' : '${e['name']}'[0].toUpperCase(),
                              style: TextStyle(color: context.brand, fontWeight: FontWeight.w800),
                            ),
                          ),
                          title: Text('${e['name']}'),
                          subtitle: Text(
                            clockIn == null
                                ? '${e['designation'] ?? ''}'
                                : 'In $clockIn${clockOut != null ? '  -  Out $clockOut' : ''}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: clockIn == null ? context.muted : Brand.success,
                              fontWeight: clockIn == null ? null : FontWeight.w600,
                            ),
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (clockIn == null)
                              FilledButton.tonal(
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                                onPressed: () => _punch(e, 'in'),
                                child: const Text('In'),
                              )
                            else if (clockOut == null)
                              FilledButton(
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                                onPressed: () => _punch(e, 'out'),
                                child: const Text('Out'),
                              )
                            else
                              const Icon(Icons.check_circle, color: Brand.success),
                          ]),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

/// Computed pay per employee for this month, read-only, like the web
/// payroll page.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  Future<Cached<dynamic>>? _future;
  DateTime _month = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<Cached<dynamic>> _load() {
    final app = AppScope.read(context);
    final from = DateTime(_month.year, _month.month, 1);
    final to = DateTime.now().isBefore(DateTime(_month.year, _month.month + 1, 1))
        ? DateTime.now()
        : DateTime(_month.year, _month.month + 1, 0);
    return app.cachedGet('/branches/${app.branchId}/payroll', query: {
      'from': from.toIso8601String().substring(0, 10),
      'to': to.toIso8601String().substring(0, 10),
    });
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } on ApiException {
      // Shown by the builder.
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: 'Choose a payroll month (pick any day in it)',
    );
    if (picked != null) {
      setState(() => _month = picked);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll'),
        actions: [
          IconButton(
            tooltip: 'Choose month',
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickMonth,
          ),
        ],
      ),
      body: FutureBuilder<Cached<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: _reload, child: const Text('Try again')),
              ]),
            );
          }
          final data = Map<String, dynamic>.from(snap.data!.data as Map);
          final rows = asRows(data['rows']);
          return RefreshIndicator(
            onRefresh: _reload,
            child: rows.isEmpty
                ? ListView(children: const [SizedBox(height: 160), EmptyState('No staff on this branch.')])
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final numbers = r.entries
                          .where((e) => e.value is num && e.key != 'id')
                          .map((e) => MapEntry(titleCase(e.key), toNum(e.value)));
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text('${r['name']}',
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              if (r['is_active'] == false) const StatusChip('inactive'),
                            ]),
                            if (r['designation'] != null)
                              Text('${r['designation']}', style: TextStyle(color: context.muted, fontSize: 12)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                for (final n in numbers)
                                  Text('${n.key}: ${n.value % 1 == 0 ? n.value.toInt() : n.value.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
