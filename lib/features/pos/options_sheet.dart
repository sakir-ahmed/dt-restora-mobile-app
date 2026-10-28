import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../ui/food_image.dart';
import '../../ui/widgets.dart';

/// One order line chosen in the options sheet: a size (or none), how many,
/// and the add-ons for each unit. Each add-on map holds `id`, `name`,
/// `name_bn`, `price` and `qty`.
class OptionLine {
  const OptionLine(this.variant, this.quantity, this.addOns);

  final Map<String, dynamic>? variant;
  final int quantity;
  final List<Map<String, dynamic>> addOns;
}

const _maxAddOnQty = 9;
const _maxLineQty = 999;

/// The same item options dialog the web POS has: pick one or more sizes with
/// a quantity each, add extras to each size with their own quantity, then
/// confirm. Pass [editing] to change a line already in the order.
///
/// Returns the lines to add (or the one revised line), or null when closed.
Future<List<OptionLine>?> showOptionsSheet(
  BuildContext context, {
  required AppState app,
  required Map<String, dynamic> item,
  OptionLine? editing,
}) {
  return showModalBottomSheet<List<OptionLine>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
    builder: (_) => _OptionsSheet(app: app, item: item, editing: editing),
  );
}

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.app, required this.item, this.editing});

  final AppState app;
  final Map<String, dynamic> item;
  final OptionLine? editing;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late final List<Map<String, dynamic>> _variants = _sortedVariants();
  late final List<Map<String, dynamic>> _addOns = asRows(widget.item['add_ons'])
      .where((a) => a['is_active'] != false)
      .toList();

  /// Several sizes can be picked together, each with its own quantity and
  /// add-ons, but only when adding a new line.
  late final bool _picksSizes = widget.editing == null && _variants.length > 1;

  // Picking several sizes.
  final Map<int, int> _sizeQty = {};
  final Map<int, Map<int, int>> _sizeAddOns = {};
  int? _activeSize;

  // One size: a new item with a single size, or a line being edited.
  late int _quantity = widget.editing?.quantity ?? 1;
  late final Map<int, int> _addOnQty = {
    for (final a in widget.editing?.addOns ?? const <Map<String, dynamic>>[])
      (a['id'] as num).toInt(): (a['qty'] as num?)?.toInt() ?? 1,
  };
  late int? _sizeId = _initialSizeId();

  List<Map<String, dynamic>> _sortedVariants() {
    final rows = asRows(widget.item['variants']);
    rows.sort((a, b) => ((a['sort_order'] as num?) ?? 0).compareTo((b['sort_order'] as num?) ?? 0));
    return rows;
  }

  int? _initialSizeId() {
    final editing = widget.editing?.variant;
    if (editing != null) {
      return (editing['id'] as num).toInt();
    }
    final pick = _variants.where((v) => v['is_default'] == true).firstOrNull ?? _variants.firstOrNull;
    return (pick?['id'] as num?)?.toInt();
  }

  int _id(Map<String, dynamic> m) => (m['id'] as num).toInt();

  Map<String, dynamic>? _variantById(int? id) =>
      _variants.where((v) => _id(v) == id).firstOrNull;

  // -------------------------------------------------------------- state

  int _addOnQtyFor(int addOnId) => _picksSizes
      ? (_sizeAddOns[_activeSize]?[addOnId] ?? 0)
      : (_addOnQty[addOnId] ?? 0);

  void _setAddOn(int addOnId, int qty) {
    final clamped = qty.clamp(0, _maxAddOnQty);
    setState(() {
      if (!_picksSizes) {
        _addOnQty[addOnId] = clamped;
        return;
      }
      // An add-on belongs to one size: with none picked yet, picking an
      // add-on starts with the default size.
      if (_activeSize == null) {
        final first = _variants.where((v) => v['is_default'] == true).firstOrNull ?? _variants.first;
        _sizeQty[_id(first)] = 1;
        _activeSize = _id(first);
      }
      final current = Map<int, int>.of(_sizeAddOns[_activeSize] ?? const {});
      current[addOnId] = clamped;
      _sizeAddOns[_activeSize!] = current;
    });
  }

  void _setSizeQty(Map<String, dynamic> variant, int qty) {
    final id = _id(variant);
    final clamped = qty.clamp(0, _maxLineQty);
    setState(() {
      _sizeQty[id] = clamped;
      if (clamped > 0) {
        _activeSize = id;
        return;
      }
      _sizeAddOns.remove(id);
      if (_activeSize == id) {
        _activeSize = _variants.where((v) => (_sizeQty[_id(v)] ?? 0) > 0).map(_id).firstOrNull;
      }
    });
  }

  // First tap picks a size, tapping a picked size that is not active only
  // makes it active (to edit its add-ons), and tapping the active size adds
  // one more.
  void _tapSize(Map<String, dynamic> variant) {
    final qty = _sizeQty[_id(variant)] ?? 0;
    if (qty > 0 && _activeSize != _id(variant)) {
      setState(() => _activeSize = _id(variant));
      return;
    }
    _setSizeQty(variant, qty + 1);
  }

  List<Map<String, dynamic>> _picked(Map<int, int>? quantities) => [
        for (final a in _addOns)
          if ((quantities?[_id(a)] ?? 0) > 0)
            {
              'id': a['id'],
              'name': a['name'],
              'name_bn': a['name_bn'],
              'price': a['price'],
              'qty': quantities![_id(a)],
            },
      ];

  double _addOnsTotal(List<Map<String, dynamic>> addOns) =>
      addOns.fold(0.0, (s, a) => s + toNum(a['price']) * (a['qty'] as int));

  List<OptionLine> get _lines {
    if (_picksSizes) {
      return [
        for (final v in _variants)
          if ((_sizeQty[_id(v)] ?? 0) > 0) OptionLine(v, _sizeQty[_id(v)]!, _picked(_sizeAddOns[_id(v)])),
      ];
    }
    final variant = _variants.length > 1 ? _variantById(_sizeId) : _variants.firstOrNull;
    return [OptionLine(variant, _quantity, _picked(_addOnQty))];
  }

  double get _total => _lines.fold(
        0.0,
        (s, l) => s + (toNum(l.variant?['price'] ?? widget.item['base_price']) + _addOnsTotal(l.addOns)) * l.quantity,
      );

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final item = widget.item;
    final lines = _lines;
    final active = _variantById(_activeSize);
    final editing = widget.editing != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(height: 100, child: FoodImage(url: foodImageUrl(app, item), iconSize: 40)),
                  ),
                  const SizedBox(height: 10),
                  Text(localized(app, item), style: Theme.of(context).textTheme.titleLarge),
                  if ((item['description'] as String?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        localized(app, item, 'description'),
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                    ),
                  if (_picksSizes) ...[
                    const SectionTitle('Sizes'),
                    for (final v in _variants) _sizeRow(context, v),
                  ] else ...[
                    if (_variants.length > 1) ...[
                      const SectionTitle('Size'),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final v in _variants)
                          ChoiceChip(
                            label: Text('${localized(app, v)}  ${fmtMoney(v['price'])}'),
                            selected: _sizeId == _id(v),
                            onSelected: (_) => setState(() => _sizeId = _id(v)),
                          ),
                      ]),
                    ],
                    const SectionTitle('Quantity'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _Qty(
                        qty: _quantity,
                        min: 1,
                        max: _maxLineQty,
                        onChanged: (q) => setState(() => _quantity = q),
                      ),
                    ),
                  ],
                  if (_addOns.isNotEmpty) ...[
                    SectionTitle(
                      _picksSizes && active != null
                          ? 'Add-ons for ${localized(app, active)}'
                          : 'Add-ons',
                    ),
                    if (_picksSizes && active == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Pick a size, or tap an add-on to start with the default size. '
                          'Each size keeps its own add-ons.',
                          style: TextStyle(color: context.muted, fontSize: 12),
                        ),
                      ),
                    for (final a in _addOns) _addOnRow(context, a),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  lines.isEmpty
                      ? 'Choose a size'
                      : '${lines.fold<int>(0, (s, l) => s + l.quantity)} item(s)  -  ${fmtMoney(_total)}',
                  style: TextStyle(color: context.muted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 4),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(130, 46)),
                onPressed: lines.isEmpty ? null : () => Navigator.pop(context, lines),
                child: Text(editing ? 'Save changes' : 'Add to order'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _sizeRow(BuildContext context, Map<String, dynamic> v) {
    final qty = _sizeQty[_id(v)] ?? 0;
    final isActive = _activeSize == _id(v) && qty > 0;
    final extras = _addOnsTotal(_picked(_sizeAddOns[_id(v)]));
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isActive ? context.brand : context.lineColor, width: isActive ? 2 : 1),
      ),
      child: ListTile(
        onTap: () => _tapSize(v),
        title: Text(localized(widget.app, v), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          extras > 0
              ? '${fmtMoney(toNum(v['price']) + extras)}  (with add-ons)'
              : fmtMoney(v['price']),
          style: TextStyle(fontWeight: FontWeight.w700, color: context.brand),
        ),
        trailing: qty == 0
            ? IconButton.filled(
                tooltip: 'Add',
                onPressed: () => _tapSize(v),
                icon: const Icon(Icons.add, color: Colors.white),
              )
            : _Qty(qty: qty, min: 0, max: _maxLineQty, onChanged: (q) => _setSizeQty(v, q)),
      ),
    );
  }

  Widget _addOnRow(BuildContext context, Map<String, dynamic> a) {
    final id = _id(a);
    final qty = _addOnQtyFor(id);
    return Card(
      color: qty > 0 ? context.brand.withValues(alpha: 0.08) : null,
      child: ListTile(
        dense: true,
        onTap: () => _setAddOn(id, qty + 1),
        leading: Icon(
          qty > 0 ? Icons.check_box : Icons.check_box_outline_blank,
          color: qty > 0 ? context.brand : context.muted,
        ),
        title: Text(localized(widget.app, a)),
        subtitle: Text('+ ${fmtMoney(a['price'])}'),
        trailing: qty == 0
            ? null
            : _Qty(qty: qty, min: 0, max: _maxAddOnQty, onChanged: (q) => _setAddOn(id, q)),
      ),
    );
  }
}

/// A compact - 2 + stepper.
class _Qty extends StatelessWidget {
  const _Qty({required this.qty, required this.min, required this.max, required this.onChanged});

  final int qty;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, bool enabled, VoidCallback onTap, String tip) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: enabled ? onTap : null,
          icon: Icon(icon, size: 20),
        );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.lineColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        button(Icons.remove, qty > min, () => onChanged(qty - 1), 'Fewer'),
        SizedBox(
          width: 28,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        button(Icons.add, qty < max, () => onChanged(qty + 1), 'More'),
      ]),
    );
  }
}
