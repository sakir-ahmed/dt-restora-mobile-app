import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

const wastageReasons = ['spoiled', 'dropped', 'complimentary', 'over_production', 'kitchen_mistake', 'other'];

/// Lookup lists (ingredients, units, suppliers, riders, tables) from
/// `/branches/{id}/reference`, cached for offline use.
///
/// Older servers do not have this endpoint; then an empty map comes back so
/// screens can fall back or explain what is missing.
Future<Map<String, dynamic>> loadReference(AppState app) async {
  try {
    final res = await app.cachedGet('/branches/${app.branchId}/reference');
    return Map<String, dynamic>.from(res.data as Map);
  } on ApiException catch (e) {
    if (e.status == 404) {
      return {};
    }
    rethrow;
  }
}

const _needsUpdate = 'This screen needs the latest server update (the lookup lists are not available on this server yet).';

class _RefLoader extends StatelessWidget {
  const _RefLoader({required this.builder, this.require = const []});

  final Widget Function(BuildContext context, Map<String, dynamic> ref) builder;
  final List<String> require;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: loadReference(app),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState('${snap.error}');
        }
        if (require.any((k) => snap.data![k] == null)) {
          return const EmptyState(_needsUpdate);
        }
        return builder(context, snap.data!);
      },
    );
  }
}

// ---------------------------------------------------------------- stock

class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stock')),
      body: _RefLoader(
        builder: (context, ref) {
          final ingredients = {for (final i in asRows(ref['ingredients'])) (i['id'] as num).toInt(): i};
          return DataView<List<Map<String, dynamic>>>(
            path: '/branches/${app.branchId}/inventory/stock',
            transform: asRows,
            builder: (context, rows, raw, reload) => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = rows[i];
                final meta = ingredients[(r['ingredient_id'] as num).toInt()];
                final low = meta != null && toNum(r['stock_qty']) <= toNum(meta['reorder_level']);
                return Card(
                  child: ListTile(
                    leading: Icon(low ? Icons.warning_amber : Icons.inventory_2,
                        color: low ? Brand.warning : context.brand),
                    title: Text('${r['name']}'),
                    subtitle: Text('Avg cost ${fmtMoney(r['avg_cost'])}${low ? '  -  Low stock' : ''}'),
                    trailing: Text('${toNum(r['stock_qty']).toStringAsFixed(2)} ${meta?['unit_symbol'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
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

// ---------------------------------------------------------------- wastage

class WastageScreen extends StatefulWidget {
  const WastageScreen({super.key});

  @override
  State<WastageScreen> createState() => _WastageScreenState();
}

class _WastageScreenState extends State<WastageScreen> {
  int? _ingredient;
  String _reason = wastageReasons.first;
  final _qty = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(Map<String, dynamic> ref) async {
    final app = AppScope.read(context);
    final ing = asRows(ref['ingredients']).where((i) => i['id'] == _ingredient).firstOrNull;
    final qty = double.tryParse(_qty.text);
    if (ing == null || qty == null || qty <= 0) {
      snack(context, 'Choose an ingredient and enter a quantity.', error: true);
      return;
    }
    setState(() => _busy = true);
    final sent = await app.queue(
      'wastage',
      {
        'branch_id': app.branchId,
        'ingredient_id': ing['id'],
        'unit_id': ing['unit_id'],
        'qty': qty,
        'reason_code': _reason,
        if (_note.text.isNotEmpty) 'note': _note.text,
      },
      label: 'Wastage: ${ing['name']} $qty',
    );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    _qty.clear();
    _note.clear();
    snack(context, sent ? 'Wastage logged.' : 'Saved on this device. Will sync when online.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log wastage')),
      body: _RefLoader(
        require: const ['ingredients'],
        builder: (context, ref) {
          final ingredients = asRows(ref['ingredients']);
          return ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButtonFormField<int>(
              initialValue: _ingredient,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ingredient'),
              items: [
                for (final i in ingredients)
                  DropdownMenuItem(value: (i['id'] as num).toInt(), child: Text('${i['name']} (${i['unit_symbol'] ?? ''})')),
              ],
              onChanged: (v) => setState(() => _ingredient = v),
            ),
            const SizedBox(height: 12),
            field(_qty, 'Quantity', type: const TextInputType.numberWithOptions(decimal: true)),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: [for (final r in wastageReasons) DropdownMenuItem(value: r, child: Text(titleCase(r)))],
              onChanged: (v) => setState(() => _reason = v!),
            ),
            const SizedBox(height: 12),
            field(_note, 'Note (optional)'),
            FilledButton(onPressed: _busy ? null : () => _submit(ref), child: const Text('Log wastage')),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- purchases

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListModule(
      title: 'Purchases',
      path: '/branches/${app.branchId}/purchases',
      itemBuilder: (context, p, reload) => Card(
        child: ListTile(
          title: Text('${p['invoice_no'] ?? 'Purchase #${p['id']}'}'),
          subtitle: Text('${fmtDay(p['purchased_at'])}  -  ${asRows(p['items']).length} lines'),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtMoney(p['total']), style: const TextStyle(fontWeight: FontWeight.w700)),
            StatusChip('${p['status']}'),
          ]),
        ),
      ),
      fab: (reload) => FloatingActionButton.extended(
        onPressed: () async {
          await showForm<void>(context, title: 'New purchase', builder: (_) => const _PurchaseForm());
          await reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Purchase'),
      ),
    );
  }
}

class _PurchaseForm extends StatefulWidget {
  const _PurchaseForm();

  @override
  State<_PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<_PurchaseForm> {
  Map<String, dynamic>? _ref;
  int? _supplier;
  final _invoice = TextEditingController();
  bool _receive = true;
  final List<({int ingredient, TextEditingController qty, TextEditingController cost})> _lines = [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    loadReference(AppScope.read(context)).then((r) {
      if (mounted) {
        setState(() => _ref = r);
      }
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    });
  }

  @override
  void dispose() {
    _invoice.dispose();
    for (final l in _lines) {
      l.qty.dispose();
      l.cost.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final items = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final ing = asRows(_ref!['ingredients']).firstWhere((i) => i['id'] == l.ingredient);
      final qty = double.tryParse(l.qty.text);
      final cost = double.tryParse(l.cost.text);
      if (qty != null && qty > 0 && cost != null) {
        items.add({'ingredient_id': l.ingredient, 'unit_id': ing['unit_id'], 'qty': qty, 'unit_cost': cost});
      }
    }
    if (_supplier == null || items.isEmpty) {
      snack(context, 'Choose a supplier and add at least one line.', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      await app.api.post('/branches/${app.branchId}/purchases', body: {
        'supplier_id': _supplier,
        if (_invoice.text.isNotEmpty) 'invoice_no': _invoice.text,
        'purchased_at': DateTime.now().toIso8601String().substring(0, 10),
        'receive': _receive,
        'items': items,
      });
    });
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context);
      snack(context, 'Purchase saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text(_error!);
    }
    final ref = _ref;
    if (ref == null) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (ref['ingredients'] == null) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: EmptyState(_needsUpdate));
    }
    final ingredients = asRows(ref['ingredients']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<int>(
        initialValue: _supplier,
        decoration: const InputDecoration(labelText: 'Supplier'),
        items: [for (final s in asRows(ref['suppliers'])) DropdownMenuItem(value: (s['id'] as num).toInt(), child: Text('${s['name']}'))],
        onChanged: (v) => setState(() => _supplier = v),
      ),
      const SizedBox(height: 12),
      field(_invoice, 'Supplier invoice no. (optional)'),
      for (var i = 0; i < _lines.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Text(ingredients.firstWhere((x) => x['id'] == _lines[i].ingredient)['name'].toString()),
            ),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _lines[i].qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Qty', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _lines[i].cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Unit cost', isDense: true),
              ),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.removeAt(i))),
          ]),
        ),
      DropdownButtonFormField<int>(
        initialValue: null,
        decoration: const InputDecoration(labelText: 'Add ingredient'),
        items: [for (final i in ingredients) DropdownMenuItem(value: (i['id'] as num).toInt(), child: Text('${i['name']}'))],
        onChanged: (v) {
          if (v != null) {
            setState(() => _lines.add((ingredient: v, qty: TextEditingController(), cost: TextEditingController())));
          }
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Receive into stock now'),
        value: _receive,
        onChanged: (v) => setState(() => _receive = v),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Save purchase')),
    ]);
  }
}

// ---------------------------------------------------------------- stock count

class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key});

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  final Map<int, TextEditingController> _counts = {};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _close() async {
    final app = AppScope.read(context);
    final items = [
      for (final e in _counts.entries)
        if (e.value.text.trim().isNotEmpty) {'ingredient_id': e.key, 'counted_qty': double.tryParse(e.value.text) ?? 0}
    ];
    if (items.isEmpty) {
      snack(context, 'Enter at least one counted quantity.', error: true);
      return;
    }
    if (!await confirm(context, 'Close stock count?', body: 'Stock will be adjusted to the counted quantities.', action: 'Close count')) {
      return;
    }
    setState(() => _busy = true);
    final sent = await app.queue('stock_count', {'action': 'close', 'branch_id': app.branchId, 'items': items},
        label: 'Stock count (${items.length} items)');
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    for (final c in _counts.values) {
      c.clear();
    }
    snack(context, sent ? 'Stock count closed.' : 'Saved on this device. Will sync when online.');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stock count')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(onPressed: _busy ? null : _close, child: const Text('Close count')),
        ),
      ),
      body: DataView<List<Map<String, dynamic>>>(
        path: '/branches/${app.branchId}/inventory/stock',
        transform: asRows,
        builder: (context, rows, raw, reload) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            final id = (r['ingredient_id'] as num).toInt();
            final c = _counts.putIfAbsent(id, TextEditingController.new);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('System: ${toNum(r['stock_qty']).toStringAsFixed(2)}', style: TextStyle(color: context.muted, fontSize: 12)),
                    ]),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: c,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Counted', isDense: true),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- transfers

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  int? _toBranch;
  int? _ingredient;
  final _qty = TextEditingController();
  final _id = TextEditingController();
  bool _busy = false;
  String? _lastTransfer;

  @override
  void dispose() {
    _qty.dispose();
    _id.dispose();
    super.dispose();
  }

  Future<void> _create(Map<String, dynamic> ref) async {
    final app = AppScope.read(context);
    final ing = asRows(ref['ingredients']).where((i) => i['id'] == _ingredient).firstOrNull;
    final qty = double.tryParse(_qty.text);
    if (_toBranch == null || ing == null || qty == null || qty <= 0) {
      snack(context, 'Choose a destination branch, ingredient and quantity.', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await guarded(context, () async {
      final res = await app.api.post('/stock-transfers', body: {
        'from_branch_id': app.branchId,
        'to_branch_id': _toBranch,
        'items': [
          {'ingredient_id': ing['id'], 'unit_id': ing['unit_id'], 'qty': qty}
        ],
      }) as Map;
      _lastTransfer = 'Transfer #${res['id']} is ${res['status']}.';
    });
    if (mounted) {
      setState(() => _busy = false);
      if (ok) {
        _qty.clear();
      }
    }
  }

  Future<void> _act(String action) async {
    final app = AppScope.read(context);
    final id = int.tryParse(_id.text.trim());
    if (id == null) {
      snack(context, 'Enter a transfer number.', error: true);
      return;
    }
    final ok = await guarded(context, () async {
      await app.api.post('/stock-transfers/$id/$action');
    });
    if (ok && mounted) {
      snack(context, 'Transfer #$id ${action == 'approve' ? 'approved' : 'received'}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stock transfers')),
      body: _RefLoader(
        require: const ['ingredients'],
        builder: (context, ref) => FutureBuilder<Cached<dynamic>>(
          future: app.cachedGet('/customer/branches'),
          builder: (context, snap) {
            final branches = asRows(snap.data?.data).where((b) => b['id'] != app.branchId).toList();
            return ListView(padding: const EdgeInsets.all(16), children: [
              const SectionTitle('Send stock to another branch'),
              DropdownButtonFormField<int>(
                initialValue: _toBranch,
                decoration: const InputDecoration(labelText: 'To branch'),
                items: [for (final b in branches) DropdownMenuItem(value: (b['id'] as num).toInt(), child: Text('${b['name']}'))],
                onChanged: (v) => setState(() => _toBranch = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _ingredient,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ingredient'),
                items: [
                  for (final i in asRows(ref['ingredients']))
                    DropdownMenuItem(value: (i['id'] as num).toInt(), child: Text('${i['name']} (${i['unit_symbol'] ?? ''})')),
                ],
                onChanged: (v) => setState(() => _ingredient = v),
              ),
              const SizedBox(height: 12),
              field(_qty, 'Quantity', type: const TextInputType.numberWithOptions(decimal: true)),
              FilledButton(onPressed: _busy ? null : () => _create(ref), child: const Text('Create transfer')),
              if (_lastTransfer != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_lastTransfer!)),
              const SectionTitle('Approve or receive'),
              field(_id, 'Transfer number', type: TextInputType.number),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _act('approve'), child: const Text('Approve'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: () => _act('receive'), child: const Text('Receive'))),
              ]),
              const SizedBox(height: 8),
              Text('Transfers need a connection and are not queued offline.',
                  style: TextStyle(color: context.muted, fontSize: 12)),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- recipes

class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final menuNames = {
      for (final c in asRows(app.bootstrap?['categories']))
        for (final i in asRows(c['items'])) (i['id'] as num).toInt(): localized(app, i),
    };
    return ListModule(
      title: 'Recipes',
      path: '/recipes',
      itemBuilder: (context, r, reload) => Card(
        child: ListTile(
          title: Text(menuNames[(r['menu_item_id'] as num).toInt()] ?? 'Menu item #${r['menu_item_id']}'),
          subtitle: Text('${asRows(r['items']).length} ingredients'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeCostScreen(recipe: r, title: menuNames[(r['menu_item_id'] as num).toInt()] ?? 'Recipe'))),
        ),
      ),
    );
  }
}

class RecipeCostScreen extends StatelessWidget {
  const RecipeCostScreen({super.key, required this.recipe, required this.title});

  final Map<String, dynamic> recipe;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _RefLoader(
        builder: (context, _) => DataView<Map<String, dynamic>>(
          path: '/recipes/${recipe['id']}/cost',
          transform: (raw) => Map<String, dynamic>.from(raw as Map),
          builder: (context, cost, raw, reload) {
            final ref = {for (final e in cost.entries) e.key: e.value};
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Column(children: [
                  for (final e in ref.entries.where((e) => e.value is! List && e.value is! Map))
                    ListTile(dense: true, title: Text(titleCase(e.key)), trailing: Text('${e.value}')),
                ]),
              ),
              const SectionTitle('Ingredients'),
              Card(
                child: Column(children: [
                  for (final i in asRows(recipe['items']))
                    ListTile(dense: true, title: Text('Ingredient #${i['ingredient_id']}'), trailing: Text(toNum(i['qty']).toStringAsFixed(2))),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- menu & tables

class MenuViewScreen extends StatelessWidget {
  const MenuViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cats = asRows(app.bootstrap?['categories']);
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: cats.isEmpty
          ? const EmptyState('The menu has not been downloaded yet.')
          : ListView(padding: const EdgeInsets.all(12), children: [
              for (final c in cats) ...[
                SectionTitle(localized(app, c)),
                for (final i in asRows(c['items']))
                  Card(
                    child: ListTile(
                      title: Text(localized(app, i)),
                      subtitle: Text(asRows(i['variants']).map((v) => '${localized(app, v)} ${fmtMoney(v['price'])}').join('  -  ')),
                      trailing: i['is_available'] == true ? null : const Text('Off', style: TextStyle(color: Brand.danger)),
                    ),
                  ),
              ],
            ]),
    );
  }
}

class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tables')),
      body: _RefLoader(
        builder: (context, ref) {
          final app = AppScope.of(context);
          final tables = asRows(ref['tables'] ?? app.bootstrap?['tables']);
          if (tables.isEmpty) {
            return const EmptyState('No tables for this branch.');
          }
          return GridView.count(
            padding: const EdgeInsets.all(12),
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final t in tables)
                Card(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.table_restaurant, color: context.brand),
                    const SizedBox(height: 4),
                    Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${t['seats'] ?? ''} seats', style: TextStyle(fontSize: 11, color: context.muted)),
                    const SizedBox(height: 4),
                    StatusChip('${t['status']}'),
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }
}
