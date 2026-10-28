import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// Expenses: the web admin's expense book, with the same categories. Each
/// new expense is posted to the accounts by the server.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListModule(
      title: 'Expenses',
      path: '/expenses',
      query: {'branch_id': app.branchId},
      extract: (raw) => asRows((raw as Map?)?['expenses']),
      itemBuilder: (context, e, reload) => Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: context.pageBg,
            child: Icon(Icons.receipt, color: context.brand, size: 20),
          ),
          title: Text(titleCase('${e['category']}')),
          subtitle: Text(
            '${fmtDay(e['expense_date'])}'
            '${(e['description'] ?? '').toString().isEmpty ? '' : '  -  ${e['description']}'}',
          ),
          trailing: Text(
            fmtMoney(e['amount']),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onLongPress: () async {
            if (await confirm(
              context,
              'Delete this expense?',
              body: '${titleCase('${e['category']}')}  -  ${fmtMoney(e['amount'])}',
              action: 'Delete',
            )) {
              if (!context.mounted) {
                return;
              }
              final ok = await guarded(
                context,
                () async => app.api.delete('/expenses/${e['id']}'),
              );
              if (ok) {
                await reload();
              }
            }
          },
        ),
      ),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          'Press and hold an expense to delete it.',
          style: TextStyle(fontSize: 12, color: context.muted),
        ),
      ),
      fab: (reload) => FloatingActionButton.extended(
        onPressed: () async {
          await showForm<void>(
            context,
            title: 'Add expense',
            builder: (_) => const _ExpenseForm(),
          );
          await reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Expense'),
      ),
    );
  }
}

const _expenseCategories = [
  'rent',
  'utilities',
  'marketing',
  'repairs',
  'supplies',
  'salary_extra',
  'other',
];

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm();

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _category = _expenseCategories.first;
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  String get _dateText =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final amount = double.tryParse(_amount.text);
    if (amount == null || amount <= 0) {
      snack(context, 'Enter an amount above zero.', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await app.api.post('/expenses', body: {
        'branch_id': app.branchId,
        'expense_date': _dateText,
        'category': _category,
        'amount': amount,
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
      });
    });
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context);
      snack(context, 'Expense recorded.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        initialValue: _category,
        decoration: const InputDecoration(labelText: 'Category'),
        items: [
          for (final c in _expenseCategories) DropdownMenuItem(value: c, child: Text(titleCase(c))),
        ],
        onChanged: (v) => setState(() => _category = v!),
      ),
      const SizedBox(height: 12),
      field(_amount, 'Amount', type: const TextInputType.numberWithOptions(decimal: true)),
      OutlinedButton.icon(
        onPressed: _pickDate,
        icon: const Icon(Icons.event, size: 18),
        label: Text('Date: $_dateText'),
      ),
      const SizedBox(height: 12),
      field(_description, 'Description (optional)'),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Save expense')),
    ]);
  }
}

/// Suppliers: add, edit and remove the vendors purchases are booked against.
class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final canManage = app.can('inventory.manage');

    Future<void> openForm(Map<String, dynamic>? supplier, Future<void> Function() reload) async {
      await showForm<void>(
        context,
        title: supplier == null ? 'Add supplier' : 'Edit supplier',
        builder: (_) => _SupplierForm(supplier: supplier),
      );
      await reload();
    }

    return ListModule(
      title: 'Suppliers',
      path: '/suppliers',
      itemBuilder: (context, s, reload) => Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: context.pageBg,
            child: Icon(Icons.local_shipping_outlined, color: context.brand, size: 20),
          ),
          title: Text(localized(app, s)),
          subtitle: Text([
            if ((s['mobile'] ?? '').toString().isNotEmpty) s['mobile'],
            if ((s['address'] ?? '').toString().isNotEmpty) s['address'],
          ].join('  -  ')),
          trailing: s['is_active'] == false ? const StatusChip('inactive') : null,
          onTap: canManage ? () => openForm(s, reload) : null,
          onLongPress: canManage
              ? () async {
                  if (await confirm(
                    context,
                    'Delete ${s['name']}?',
                    body: 'Suppliers with purchases cannot be deleted.',
                    action: 'Delete',
                  )) {
                    if (!context.mounted) {
                      return;
                    }
                    final ok = await guarded(
                      context,
                      () async => app.api.delete('/suppliers/${s['id']}'),
                    );
                    if (ok) {
                      await reload();
                    }
                  }
                }
              : null,
        ),
      ),
      fab: canManage
          ? (reload) => FloatingActionButton.extended(
                onPressed: () => openForm(null, reload),
                icon: const Icon(Icons.add_business),
                label: const Text('Supplier'),
              )
          : null,
    );
  }
}

class _SupplierForm extends StatefulWidget {
  const _SupplierForm({this.supplier});

  final Map<String, dynamic>? supplier;

  @override
  State<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<_SupplierForm> {
  late final _name = TextEditingController(text: '${widget.supplier?['name'] ?? ''}');
  late final _nameBn = TextEditingController(text: '${widget.supplier?['name_bn'] ?? ''}');
  late final _mobile = TextEditingController(text: '${widget.supplier?['mobile'] ?? ''}');
  late final _email = TextEditingController(text: '${widget.supplier?['email'] ?? ''}');
  late final _address = TextEditingController(text: '${widget.supplier?['address'] ?? ''}');
  late bool _active = widget.supplier?['is_active'] != false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _nameBn.dispose();
    _mobile.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    if (_name.text.trim().isEmpty) {
      snack(context, 'The supplier needs a name.', error: true);
      return;
    }
    final body = {
      'name': _name.text.trim(),
      'name_bn': _nameBn.text.trim().isEmpty ? null : _nameBn.text.trim(),
      'mobile': _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'is_active': _active,
    };
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      if (widget.supplier == null) {
        await app.api.post('/suppliers', body: body);
      } else {
        await app.api.put('/suppliers/${widget.supplier!['id']}', body: body);
      }
    });
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context);
      snack(context, 'Supplier saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      field(_name, 'Name'),
      field(_nameBn, 'Name in Bangla (optional)'),
      field(_mobile, 'Mobile', type: TextInputType.phone),
      field(_email, 'Email', type: TextInputType.emailAddress),
      field(_address, 'Address'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Active'),
        value: _active,
        onChanged: (v) => setState(() => _active = v),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Save supplier')),
    ]);
  }
}

/// Loyalty programme: totals, settings and a customer lookup with history.
class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final _mobile = TextEditingController();
  final _key = GlobalKey<DataViewState<Map<String, dynamic>>>();
  String _lookup = '';

  @override
  void dispose() {
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _editSettings(Map<String, dynamic> settings) async {
    await showForm<void>(
      context,
      title: 'Loyalty settings',
      builder: (_) => _LoyaltySettingsForm(settings: settings),
    );
    await _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty')),
      body: DataView<Map<String, dynamic>>(
        key: ValueKey(_lookup),
        path: '/loyalty',
        query: _lookup.isEmpty ? null : {'mobile': _lookup},
        transform: (raw) => Map<String, dynamic>.from((raw as Map?) ?? const {}),
        builder: (context, data, raw, reload) {
          final totals = Map<String, dynamic>.from((data['totals'] as Map?) ?? const {});
          final settings = Map<String, dynamic>.from((data['settings'] as Map?) ?? const {});
          final lookup = data['lookup'] == null ? null : Map<String, dynamic>.from(data['lookup'] as Map);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              Row(children: [
                Expanded(child: Metric('Customers with points', '${totals['customers_with_points'] ?? 0}', icon: Icons.people)),
                const SizedBox(width: 8),
                Expanded(child: Metric('Points earned', '${totals['points_earned'] ?? 0}', icon: Icons.trending_up)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Metric('Points redeemed', '${totals['points_redeemed'] ?? 0}', icon: Icons.redeem)),
                const SizedBox(width: 8),
                Expanded(child: Metric('Points expired', '${totals['points_expired'] ?? 0}', icon: Icons.hourglass_bottom)),
              ]),
              const SectionTitle('Programme'),
              Card(
                child: ListTile(
                  leading: Icon(Icons.stars, color: settings['is_enabled'] == true ? Brand.success : context.muted),
                  title: Text(settings['is_enabled'] == true ? 'Programme is on' : 'Programme is off'),
                  subtitle: Text(
                    'Earn ${settings['earn_rate'] ?? 0} per 100 spent  -  '
                    '1 point = ${fmtMoney(settings['point_value'])}  -  expires after ${settings['expiry_days'] ?? 0} days',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editSettings(settings),
                ),
              ),
              const SectionTitle('Find a customer'),
              Row(children: [
                Expanded(child: field(_mobile, 'Customer mobile', type: TextInputType.phone)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(56, 56)),
                    onPressed: () => setState(() => _lookup = _mobile.text.trim()),
                    child: const Icon(Icons.search),
                  ),
                ),
              ]),
              if (_lookup.isNotEmpty && lookup == null)
                const EmptyState('No customer with that mobile number.'),
              if (lookup != null) ..._lookupCards(context, lookup),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _lookupCards(BuildContext context, Map<String, dynamic> lookup) {
    final customer = Map<String, dynamic>.from((lookup['customer'] as Map?) ?? const {});
    final entries = asRows(lookup['entries']);
    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.person),
          title: Text('${customer['name']}'),
          subtitle: Text('${customer['mobile']}'),
          trailing: Text(
            '${lookup['balance']} pts',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
      ),
      for (final e in entries)
        Card(
          child: ListTile(
            dense: true,
            title: Text('${titleCase('${e['type']}')}${e['invoice_no'] == null ? '' : '  -  ${e['invoice_no']}'}'),
            subtitle: Text('${fmtDate(e['created_at'])}${(e['note'] ?? '').toString().isEmpty ? '' : '  -  ${e['note']}'}'),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                '${(e['points'] as num) > 0 ? '+' : ''}${e['points']}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: (e['points'] as num) > 0 ? Brand.success : Brand.danger,
                ),
              ),
              Text('bal ${e['balance_after']}', style: TextStyle(fontSize: 11, color: context.muted)),
            ]),
          ),
        ),
    ];
  }
}

class _LoyaltySettingsForm extends StatefulWidget {
  const _LoyaltySettingsForm({required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<_LoyaltySettingsForm> createState() => _LoyaltySettingsFormState();
}

class _LoyaltySettingsFormState extends State<_LoyaltySettingsForm> {
  late final _earn = TextEditingController(text: '${widget.settings['earn_rate'] ?? 0}');
  late final _value = TextEditingController(text: '${widget.settings['point_value'] ?? 0}');
  late final _expiry = TextEditingController(text: '${widget.settings['expiry_days'] ?? 365}');
  late bool _enabled = widget.settings['is_enabled'] == true;
  bool _busy = false;

  @override
  void dispose() {
    _earn.dispose();
    _value.dispose();
    _expiry.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final earn = int.tryParse(_earn.text);
    final value = double.tryParse(_value.text);
    final expiry = int.tryParse(_expiry.text);
    if (earn == null || value == null || expiry == null) {
      snack(context, 'Fill in all three numbers.', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await app.api.put('/loyalty/settings', body: {
        'earn_rate': earn,
        'point_value': value,
        'expiry_days': expiry,
        'is_enabled': _enabled,
      });
    });
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context);
      snack(context, 'Loyalty settings saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Programme enabled'),
        value: _enabled,
        onChanged: (v) => setState(() => _enabled = v),
      ),
      field(_earn, 'Points earned per 100 spent', type: TextInputType.number),
      field(_value, 'Value of one point', type: const TextInputType.numberWithOptions(decimal: true)),
      field(_expiry, 'Days until points expire', type: TextInputType.number),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Save settings')),
    ]);
  }
}

/// Activity log: who did what, newest first.
class ActivityLogScreen extends StatelessWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListModule(
      title: 'Activity log',
      path: '/activity-log',
      itemBuilder: (context, a, reload) => Card(
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: context.pageBg,
            child: Icon(Icons.history, color: context.brand, size: 18),
          ),
          title: Text('${a['description']}'),
          subtitle: Text([
            if (a['causer'] != null) a['causer'],
            if (a['subject_type'] != null) titleCase('${a['subject_type']}'),
            fmtDate(a['created_at']),
          ].join('  -  ')),
        ),
      ),
    );
  }
}
