import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListModule(
      title: 'Staff',
      path: '/branches/${app.branchId}/employees',
      itemBuilder: (context, e, reload) => Card(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: context.pageBg, child: Icon(Icons.person, color: context.brand)),
          title: Text(localized(app, e)),
          subtitle: Text('${e['designation']}${e['mobile'] == null ? '' : '  -  ${e['mobile']}'}'),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              e['pay_basis'] == null || e['pay_basis'] == 'monthly'
                  ? fmtMoney(e['monthly_salary'])
                  : '${fmtMoney(e['pay_rate'])} / ${e['pay_basis'] == 'daily' ? 'day' : 'hr'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (e['is_active'] == false) const StatusChip('inactive'),
          ]),
        ),
      ),
      fab: app.can('employees.manage')
          ? (reload) => FloatingActionButton.extended(
                onPressed: () async {
                  await showForm<void>(context, title: 'Add employee', builder: (_) => const _EmployeeForm());
                  await reload();
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Employee'),
              )
          : null,
    );
  }
}

class _EmployeeForm extends StatefulWidget {
  const _EmployeeForm();

  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final _name = TextEditingController();
  final _designation = TextEditingController();
  final _mobile = TextEditingController();
  final _pay = TextEditingController();
  String _basis = 'monthly';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _designation.dispose();
    _mobile.dispose();
    _pay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final pay = double.tryParse(_pay.text);
    if (_name.text.trim().isEmpty || _designation.text.trim().isEmpty || pay == null) {
      snack(context, 'Name, designation and pay are required.', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await app.api.post('/branches/${app.branchId}/employees', body: {
        'name': _name.text.trim(),
        'designation': _designation.text.trim(),
        'pay_basis': _basis,
        if (_basis == 'monthly') 'monthly_salary': pay else 'pay_rate': pay,
        if (_mobile.text.trim().isNotEmpty) 'mobile': _mobile.text.trim(),
      });
    });
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context);
      snack(context, 'Employee added.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      field(_name, 'Full name'),
      field(_designation, 'Designation'),
      field(_mobile, 'Mobile', type: TextInputType.phone),
      DropdownButtonFormField<String>(
        initialValue: _basis,
        decoration: const InputDecoration(labelText: 'Pay basis'),
        items: const [
          DropdownMenuItem(value: 'monthly', child: Text('Monthly salary')),
          DropdownMenuItem(value: 'daily', child: Text('Daily rate')),
          DropdownMenuItem(value: 'hourly', child: Text('Hourly rate')),
        ],
        onChanged: (v) => setState(() => _basis = v!),
      ),
      const SizedBox(height: 12),
      field(_pay, _basis == 'monthly' ? 'Monthly salary' : 'Rate', type: const TextInputType.numberWithOptions(decimal: true)),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
    ]);
  }
}
