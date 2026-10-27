import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/food_image.dart';
import '../../ui/widgets.dart';

/// One editable variant (size) row.
class _VariantRow {
  _VariantRow(this.id, this.name, this.price);

  int? id;
  final TextEditingController name;
  final TextEditingController price;

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

/// One editable add-on row.
class _AddOnRow {
  _AddOnRow(this.id, this.name, this.price, this.active);

  int? id;
  final TextEditingController name;
  final TextEditingController price;
  bool active;

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

/// Add or edit a menu item: name, Bangla name, description, price, flags,
/// sizes (variants) and add-ons. Mirrors the web admin's menu form.
class MenuItemFormScreen extends StatefulWidget {
  const MenuItemFormScreen({super.key, required this.categories, this.item});

  /// Categories of the branch: [{id, name, ...}].
  final List<Map<String, dynamic>> categories;

  /// Null creates a new item.
  final Map<String, dynamic>? item;

  @override
  State<MenuItemFormScreen> createState() => _MenuItemFormScreenState();
}

class _MenuItemFormScreenState extends State<MenuItemFormScreen> {
  late final _name = TextEditingController(text: widget.item?['name'] as String? ?? '');
  late final _nameBn = TextEditingController(text: widget.item?['name_bn'] as String? ?? '');
  late final _description = TextEditingController(text: widget.item?['description'] as String? ?? '');
  late final _price = TextEditingController(
      text: widget.item == null ? '' : toNum(widget.item!['base_price']).toStringAsFixed(2));
  late int? _category = widget.item == null
      ? (widget.categories.firstOrNull?['id'] as num?)?.toInt()
      : (widget.item!['menu_category_id'] as num?)?.toInt();
  late bool _available = widget.item?['is_available'] as bool? ?? true;
  late bool _vegetarian = widget.item?['is_vegetarian'] as bool? ?? false;
  final List<_VariantRow> _variants = [];
  final List<_AddOnRow> _addOns = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final v in asRows(widget.item?['variants'])) {
      _variants.add(_VariantRow(
        (v['id'] as num?)?.toInt(),
        TextEditingController(text: '${v['name'] ?? ''}'),
        TextEditingController(text: toNum(v['price']).toStringAsFixed(2)),
      ));
    }
    for (final a in asRows(widget.item?['add_ons'])) {
      _addOns.add(_AddOnRow(
        (a['id'] as num?)?.toInt(),
        TextEditingController(text: '${a['name'] ?? ''}'),
        TextEditingController(text: toNum(a['price']).toStringAsFixed(2)),
        a['is_active'] as bool? ?? true,
      ));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _nameBn.dispose();
    _description.dispose();
    _price.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    for (final a in _addOns) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final price = double.tryParse(_price.text.trim());
    if (_name.text.trim().isEmpty || price == null || _category == null) {
      snack(context, 'Name, category and price are required.', error: true);
      return;
    }
    setState(() => _busy = true);
    final editing = widget.item != null;
    final body = {
      'menu_category_id': _category,
      'name': _name.text.trim(),
      if (_nameBn.text.trim().isNotEmpty) 'name_bn': _nameBn.text.trim(),
      if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
      'base_price': price,
      'is_available': _available,
      'is_vegetarian': _vegetarian,
      'variants': [
        for (final v in _variants)
          if (v.name.text.trim().isNotEmpty)
            {
              if (v.id != null) 'id': v.id,
              'name': v.name.text.trim(),
              'price': double.tryParse(v.price.text.trim()) ?? 0,
            }
      ],
      'addons': [
        for (final a in _addOns)
          if (a.name.text.trim().isNotEmpty)
            {
              if (a.id != null) 'id': a.id,
              'name': a.name.text.trim(),
              'price': double.tryParse(a.price.text.trim()) ?? 0,
              'is_active': a.active,
            }
      ],
    };
    final ok = await guarded(context, () async {
      if (editing) {
        await app.api.put('/branches/${app.branchId}/menu-items/${widget.item!['id']}', body: body);
      } else {
        await app.api.post('/branches/${app.branchId}/menu-items', body: body);
      }
      // Refresh the cached menu so POS and the kitchen see the change.
      await app.loadBootstrap();
    });
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      snack(context, editing ? 'Item updated.' : 'Item created.');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final editing = widget.item != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit menu item' : 'New menu item')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving...' : 'Save item')),
        ),
      ),
      body: Form(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<int>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in widget.categories)
                DropdownMenuItem(value: (c['id'] as num).toInt(), child: Text(localized(app, c))),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          field(_name, 'Name (English)'),
          field(_nameBn, 'Bangla name (optional)'),
          field(_description, 'Description (optional)', maxLines: 3),
          field(_price, 'Base price', type: const TextInputType.numberWithOptions(decimal: true)),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('Available'),
            subtitle: Text(_available ? 'Shows on the menu and in POS' : 'Hidden everywhere'),
            value: _available,
            onChanged: (v) => setState(() => _available = v),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('Vegetarian'),
            value: _vegetarian,
            onChanged: (v) => setState(() => _vegetarian = v),
          ),
          SectionTitle('Sizes (variants)', color: groupColor(context, 'Inventory')),
          for (var i = 0; i < _variants.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(flex: 3, child: field(_variants[i].name, 'Size name', dense: true)),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: field(_variants[i].price, 'Price',
                      type: const TextInputType.numberWithOptions(decimal: true), dense: true),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Brand.danger),
                  onPressed: () => setState(() {
                    _variants[i].dispose();
                    _variants.removeAt(i);
                  }),
                ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() =>
                  _variants.add(_VariantRow(null, TextEditingController(), TextEditingController()))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add size'),
            ),
          ),
          SectionTitle('Add-ons', color: groupColor(context, 'Inventory')),
          for (var i = 0; i < _addOns.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(children: [
                Row(children: [
                  Expanded(flex: 3, child: field(_addOns[i].name, 'Add-on name', dense: true)),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: field(_addOns[i].price, 'Price',
                        type: const TextInputType.numberWithOptions(decimal: true), dense: true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Brand.danger),
                    onPressed: () => setState(() {
                      _addOns[i].dispose();
                      _addOns.removeAt(i);
                    }),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Active', style: TextStyle(fontSize: 13)),
                  value: _addOns[i].active,
                  onChanged: (v) => setState(() => _addOns[i].active = v),
                ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() =>
                  _addOns.add(_AddOnRow(null, TextEditingController(), TextEditingController(), true))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add add-on'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The branch menu as an editable list: every item including unavailable
/// ones, grouped by category, with add and edit.
class MenuManageScreen extends StatefulWidget {
  const MenuManageScreen({super.key});

  @override
  State<MenuManageScreen> createState() => _MenuManageScreenState();
}

class _MenuManageScreenState extends State<MenuManageScreen> {
  final _key = GlobalKey<DataViewState<List<Map<String, dynamic>>>>();

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final app = AppScope.read(context);
    final categories = asRows(app.bootstrap?['categories']);
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MenuItemFormScreen(categories: categories, item: item),
      ),
    );
    if (saved == true) {
      _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Manage menu')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Item'),
      ),
      body: DataView<List<Map<String, dynamic>>>(
        key: _key,
        path: '/branches/${app.branchId}/menu-items',
        transform: asRows,
        builder: (context, rows, raw, reload) {
          if (rows.isEmpty) {
            return ListView(children: const [SizedBox(height: 160), EmptyState('No categories yet.')]);
          }
          return ListView(padding: const EdgeInsets.all(12), children: [
            for (final c in rows) ...[
              SectionTitle(localized(app, c), color: groupColor(context, 'Inventory')),
              for (final i in asRows(c['items']))
                Card(
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: FoodImage(url: foodImageUrl(app, i), iconSize: 18),
                      ),
                    ),
                    title: Text(localized(app, i), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${fmtMoney(i['base_price'])}'
                      '${asRows(i['variants']).isNotEmpty ? '  -  ${asRows(i['variants']).length} sizes' : ''}'
                      '${asRows(i['add_ons']).isNotEmpty ? '  -  ${asRows(i['add_ons']).length} add-ons' : ''}',
                      style: TextStyle(fontSize: 12, color: context.muted),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (i['is_available'] != true)
                        const StatusChip('inactive')
                      else
                        const Icon(Icons.check_circle, size: 18, color: Brand.success),
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _openForm(i),
                      ),
                    ]),
                    onTap: () => _openForm(i),
                  ),
                ),
            ],
          ]);
        },
      ),
    );
  }
}
