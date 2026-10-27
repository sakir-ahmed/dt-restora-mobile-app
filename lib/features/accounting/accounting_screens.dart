import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/generic_view.dart';
import '../../ui/widgets.dart';
import '../reports/reports_screen.dart';

const statements = {
  'trial-balance': 'Trial balance',
  'profit-loss': 'Profit and loss',
  'balance-sheet': 'Balance sheet',
  'cash-flow': 'Cash flow',
  'vat-summary': 'VAT summary',
};

class AccountingScreen extends StatelessWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accounting'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Brand.soft,
            tabs: [Tab(text: 'Statements'), Tab(text: 'Journals'), Tab(text: 'Vouchers'), Tab(text: 'Payables'), Tab(text: 'Accounts')],
          ),
        ),
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(12), children: [
            for (final e in statements.entries)
              Card(
                child: ListTile(
                  leading: Icon(Icons.account_balance, color: context.brand),
                  title: Text(e.value),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReportScreen(type: e.key, title: e.value, basePath: '/accounting/reports')),
                  ),
                ),
              ),
          ]),
          _Journals(canPost: app.can('journals.post')),
          _Vouchers(canManage: app.can('vouchers.manage')),
          DataView<Object?>(
            path: '/accounting/payables',
            transform: (raw) => raw,
            builder: (context, data, raw, reload) => ListView(
              padding: const EdgeInsets.all(12),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [GenericView(data)],
            ),
          ),
          _Accounts(),
        ]),
      ),
    );
  }
}

class _Journals extends StatelessWidget {
  const _Journals({required this.canPost});

  final bool canPost;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return DataView<List<Map<String, dynamic>>>(
      path: '/accounting/journals',
      transform: asRows,
      builder: (context, rows, raw, reload) => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final j = rows[i];
          final lines = asRows(j['lines']);
          final total = lines.fold<double>(0, (s, l) => s + toNum(l['debit']));
          final status = '${j['status']}';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${j['reference'] ?? 'Journal #${j['id']}'}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  StatusChip(status),
                ]),
                Text('${fmtDay(j['entry_date'])}  -  ${j['note'] ?? ''}', style: TextStyle(color: context.muted, fontSize: 12)),
                Text(fmtMoney(total), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (canPost && (status == 'draft' || status == 'posted'))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        final action = status == 'draft' ? 'approve' : 'reverse';
                        if (!await confirm(context, '${titleCase(action)} this journal?', action: titleCase(action))) {
                          return;
                        }
                        if (!context.mounted) {
                          return;
                        }
                        final ok = await guarded(context, () async {
                          await app.api.post('/accounting/journals/${j['id']}/$action');
                        });
                        if (ok) {
                          await reload();
                        }
                      },
                      child: Text(status == 'draft' ? 'Approve' : 'Reverse'),
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _Vouchers extends StatefulWidget {
  const _Vouchers({required this.canManage});

  final bool canManage;

  @override
  State<_Vouchers> createState() => _VouchersState();
}

class _VouchersState extends State<_Vouchers> {
  final _key = GlobalKey<DataViewState<List<Map<String, dynamic>>>>();

  Future<void> _create() async {
    final app = AppScope.read(context);
    final amount = TextEditingController();
    final note = TextEditingController();
    var type = 'expense';
    var payFrom = '1100';
    final go = await showForm<bool>(
      context,
      title: 'New voucher',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Expense')),
              ButtonSegment(value: 'payment', label: Text('Supplier payment')),
            ],
            selected: {type},
            onSelectionChanged: (s) => set(() => type = s.first),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: payFrom,
            decoration: const InputDecoration(labelText: 'Pay from'),
            items: const [
              DropdownMenuItem(value: '1100', child: Text('Cash in hand')),
              DropdownMenuItem(value: '1110', child: Text('Bank')),
              DropdownMenuItem(value: '1120', child: Text('bKash')),
              DropdownMenuItem(value: '1130', child: Text('Nagad')),
            ],
            onChanged: (v) => set(() => payFrom = v!),
          ),
          const SizedBox(height: 12),
          field(amount, 'Amount', type: const TextInputType.numberWithOptions(decimal: true)),
          field(note, 'Note'),
          if (type == 'payment') Text('Supplier payments need a supplier; use the web app for those.', style: TextStyle(fontSize: 12, color: context.muted)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save voucher')),
        ]),
      ),
    );
    final a = double.tryParse(amount.text);
    final n = note.text.trim();
    amount.dispose();
    note.dispose();
    if (go != true || a == null || !mounted) {
      return;
    }
    final ok = await guarded(context, () async {
      await app.api.post('/accounting/vouchers', body: {
        'type': type,
        'amount': a,
        'entry_date': DateTime.now().toIso8601String().substring(0, 10),
        'pay_from_code': payFrom,
        if (n.isNotEmpty) 'note': n,
      });
    });
    if (ok) {
      await _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Voucher'))
          : null,
      body: DataView<List<Map<String, dynamic>>>(
        key: _key,
        path: '/accounting/vouchers',
        transform: asRows,
        builder: (context, rows, raw, reload) => ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final v = rows[i];
            return Card(
              child: ListTile(
                title: Text('${titleCase('${v['type']}')}  -  ${fmtMoney(v['amount'])}'),
                subtitle: Text('${fmtDay(v['entry_date'])}  ${v['note'] ?? ''}'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Accounts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DataView<List<Map<String, dynamic>>>(
      path: '/accounting/accounts',
      transform: asRows,
      builder: (context, rows, raw, reload) => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final a = rows[i];
          return Card(
            child: ListTile(
              dense: true,
              leading: Text('${a['code']}', style: TextStyle(fontWeight: FontWeight.w700, color: context.brand)),
              title: Text('${a['name']}'),
              subtitle: Text(titleCase('${a['type']}')),
              trailing: a['is_active'] == true ? null : const StatusChip('inactive'),
            ),
          );
        },
      ),
    );
  }
}
