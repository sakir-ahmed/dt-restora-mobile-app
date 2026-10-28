import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/local_db.dart';
import '../../core/offline_orders.dart';
import '../../core/sounds.dart';
import '../../core/theme.dart';
import '../../ui/food_image.dart';
import '../../ui/widgets.dart';
import '../orders/payment_sheet.dart';
import '../orders/receipt.dart';

/// Whole taka without decimals, e.g. `BDT 560`, for compact price tags.
String _short(double v) =>
    'BDT ${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

class CartLine {
  CartLine({
    required this.item,
    required this.variant,
    this.quantity = 1,
    List<Map<String, dynamic>> addOns = const [],
  }) : addOns = List.of(addOns);

  final Map<String, dynamic> item;
  final Map<String, dynamic>? variant;

  /// Chosen add-ons, each with `id`, `name` and `price`. One of each per unit.
  final List<Map<String, dynamic>> addOns;
  int quantity;

  int get itemId => (item['id'] as num).toInt();
  int? get variantId => (variant?['id'] as num?)?.toInt();
  double get addOnsPerUnit => addOns.fold(0, (s, a) => s + toNum(a['price']));

  /// Price of one unit including its add-ons.
  double get unitPrice =>
      toNum(variant?['price'] ?? item['base_price']) + addOnsPerUnit;
  double get total => unitPrice * quantity;
  String get addOnNames => addOns.map((a) => '${a['name']}').join(', ');
  String get key =>
      '$itemId:${variantId ?? 0}:${(addOns.map((a) => a['id'] as num).toList()..sort()).join('.')}';
}

/// The order being revised when the POS opens in edit mode.
///
/// [local] is set for an order or revision that has not reached the server
/// yet, so saving rewrites it on the device. Otherwise saving queues an
/// `order_edit` for the server order, found by [orderId] or [orderClientId].
class EditTarget {
  const EditTarget._({
    required this.order,
    this.local,
    this.orderId,
    this.orderClientId,
  });

  factory EditTarget.local(LocalOrder local) =>
      EditTarget._(order: local.order, local: local);

  factory EditTarget.server(
    Map<String, dynamic> order, {
    int? orderId,
    String? orderClientId,
  }) => EditTarget._(
    order: order,
    orderId: orderId,
    orderClientId: orderClientId,
  );

  final Map<String, dynamic> order;
  final LocalOrder? local;
  final int? orderId;
  final String? orderClientId;

  String get invoiceNo => '${order['invoice_no']}';
}

const _orderTypes = [
  ('dine_in', 'Dine in', Icons.restaurant),
  ('takeaway', 'Takeaway', Icons.shopping_bag_outlined),
  ('delivery', 'Delivery', Icons.delivery_dining),
];

/// Point of sale. Works from the menu cached at sign-in, so it keeps
/// working offline: orders are queued and sent when the network returns.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key, this.edit});

  /// Set to revise an existing order instead of starting a new one.
  final EditTarget? edit;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final List<CartLine> _cart = [];
  final _search = TextEditingController();
  final _note = TextEditingController();
  final _customerMobile = TextEditingController();
  int _category = 0; // 0 is "All", then 1..n are the categories
  String _orderType = 'takeaway';
  int? _tableId;
  String _query = '';
  bool _busy = false;
  bool _listMode = false;

  /// Order-level discount, like the web POS bill discount.
  String _discountType = 'percent';
  double _discountValue = 0;

  /// Parked orders: [{orderType, tableId, discountType, discountValue,
  /// customerMobile, note, heldAt, lines: [{i, v, q, a: [addOnIds]}]}].
  List<Map<String, dynamic>> _held = [];

  String get _prefsCartKey => 'pos_cart';
  String get _prefsHeldKey => 'pos_held';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) {
        return;
      }
      setState(() => _listMode = p.getBool('pos_list_mode') ?? false);
      _loadHeld();
      if (widget.edit != null) {
        _seedFromEdit();
      } else {
        _restoreCart();
      }
    });
  }

  Future<void> _toggleView() async {
    setState(() => _listMode = !_listMode);
    (await SharedPreferences.getInstance()).setBool('pos_list_mode', _listMode);
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    _customerMobile.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ cart logic

  double get _subtotal => _cart.fold(0, (s, l) => s + l.total);
  int get _count => _cart.fold(0, (s, l) => s + l.quantity);

  double get _discountAmount {
    if (_discountValue <= 0) {
      return 0;
    }
    final raw = _discountType == 'percent'
        ? _subtotal * _discountValue / 100
        : _discountValue;
    return raw.clamp(0, _subtotal);
  }

  int _qtyOfItem(int itemId) =>
      _cart.where((l) => l.itemId == itemId).fold(0, (s, l) => s + l.quantity);

  void _add(
    Map<String, dynamic> item,
    Map<String, dynamic>? variant, [
    int qty = 1,
    List<Map<String, dynamic>> addOns = const [],
  ]) {
    final line = CartLine(
      item: item,
      variant: variant,
      quantity: qty,
      addOns: addOns,
    );
    final existing = _cart.where((l) => l.key == line.key);
    setState(() {
      if (existing.isEmpty) {
        _cart.add(line);
      } else {
        existing.first.quantity += qty;
      }
    });
    SoundFx.play('item_added');
    _persist();
  }

  void _decrement(CartLine line) {
    setState(() => line.quantity <= 1 ? _cart.remove(line) : line.quantity--);
    _persist();
  }

  void _reset() {
    setState(() {
      _cart.clear();
      _tableId = null;
      _note.clear();
      _customerMobile.clear();
      _discountValue = 0;
    });
    _persist();
  }

  ({double service, double vat, double discount, double total}) _totals(
    AppState app,
  ) {
    final branch = app.bootstrap?['branch'] as Map? ?? {};
    final servicePct = toNum(branch['service_charge_percent']);
    final vatPct = toNum(branch['vat_percent']);
    final inclusive = branch['vat_inclusive'] == true;
    final discount = _discountAmount;
    final net = _subtotal - discount;
    final service = net * servicePct / 100;
    final vat = inclusive ? 0.0 : (net + service) * vatPct / 100;
    // The server rounds order totals to whole taka.
    return (
      service: service,
      vat: vat,
      discount: discount,
      total: (net + service + vat).roundToDouble(),
    );
  }

  // ------------------------------------------------------------ persistence

  Map<String, dynamic> _snapshot() => {
    'orderType': _orderType,
    'tableId': _tableId,
    'discountType': _discountType,
    'discountValue': _discountValue,
    'customerMobile': _customerMobile.text,
    'note': _note.text,
    'lines': [
      for (final l in _cart)
        {
          'i': l.itemId,
          'v': l.variantId,
          'q': l.quantity,
          'a': [for (final a in l.addOns) a['id']],
        },
    ],
  };

  Future<void> _persist() async {
    if (widget.edit != null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCartKey, jsonEncode(_snapshot()));
  }

  Future<void> _loadHeld() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsHeldKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List && mounted) {
        setState(
          () => _held = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      }
    } on FormatException {
      // Ignore a corrupted list; held orders are a convenience.
    }
  }

  Future<void> _persistHeld() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsHeldKey, jsonEncode(_held));
  }

  /// Rebuilds a cart from a snapshot by matching ids against the current
  /// menu; lines whose item has disappeared are skipped.
  List<CartLine> _linesFromSnapshot(List<dynamic> raw, AppState app) {
    final items = [
      for (final c in asRows(app.bootstrap?['categories']))
        ...asRows(c['items']),
    ];
    final lines = <CartLine>[];
    for (final row in raw.whereType<Map>()) {
      final item = items
          .where((i) => (i['id'] as num?)?.toInt() == row['i'])
          .firstOrNull;
      if (item == null) {
        continue;
      }
      final variants = asRows(item['variants']);
      final variant = variants
          .where((v) => (v['id'] as num?)?.toInt() == row['v'])
          .firstOrNull;
      final addOnIds = ((row['a'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toSet();
      final addOns = _activeAddOns(item)
          .where((a) => addOnIds.contains((a['id'] as num).toInt()))
          .map(
            (a) => {
              'id': a['id'],
              'name': a['name'],
              'name_bn': a['name_bn'],
              'price': a['price'],
            },
          )
          .toList();
      lines.add(
        CartLine(
          item: item,
          variant: variant,
          quantity: (row['q'] as num).toInt(),
          addOns: addOns,
        ),
      );
    }
    return lines;
  }

  Future<void> _restoreCart() async {
    final app = AppScope.read(context);
    if (_cart.isNotEmpty ||
        (app.bootstrap?['categories'] as List?)?.isEmpty != false) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsCartKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final lines = _linesFromSnapshot(
        decoded['lines'] as List? ?? const [],
        app,
      );
      if (lines.isEmpty || !mounted) {
        return;
      }
      setState(() {
        _cart.addAll(lines);
        _orderType = '${decoded['orderType']}';
        _tableId = decoded['tableId'] as int?;
        _discountType = '${decoded['discountType']}';
        _discountValue = toNum(decoded['discountValue']);
        _customerMobile.text = '${decoded['customerMobile'] ?? ''}';
        _note.text = '${decoded['note'] ?? ''}';
      });
    } on FormatException {
      // Ignore a corrupted ticket.
    }
  }

  // ------------------------------------------------------------ hold / resume

  /// Parks the current order and clears the terminal, like the web POS.
  void _hold() {
    if (_cart.isEmpty) {
      return;
    }
    setState(() {
      _held.insert(0, {
        ..._snapshot(),
        'heldAt': DateTime.now().toIso8601String(),
      });
      _reset();
    });
    _persistHeld();
    SoundFx.play('order_held');
    snack(
      context,
      'Order parked. Resume it from the held list in the app bar.',
    );
  }

  void _resume(Map<String, dynamic> ticket) {
    final app = AppScope.read(context);
    final lines = _linesFromSnapshot(ticket['lines'] as List? ?? const [], app);
    if (lines.isEmpty) {
      snack(
        context,
        'This order\'s items are no longer on the menu.',
        error: true,
      );
      return;
    }
    setState(() {
      _reset();
      _cart.addAll(lines);
      _orderType = '${ticket['orderType']}';
      _tableId = ticket['tableId'] as int?;
      _discountType = '${ticket['discountType']}';
      _discountValue = toNum(ticket['discountValue']);
      _customerMobile.text = '${ticket['customerMobile'] ?? ''}';
      _note.text = '${ticket['note'] ?? ''}';
      _held.remove(ticket);
    });
    _persistHeld();
    _persist();
  }

  void _discardHeld(Map<String, dynamic> ticket) {
    setState(() => _held.remove(ticket));
    _persistHeld();
  }

  Future<void> _showHeld() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Parked orders',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Hold an order mid-way and take it back later. Saved on this device.',
                  style: TextStyle(color: ctx.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: _held.isEmpty
                      ? const EmptyState('No parked orders.')
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final t in List.of(_held))
                              Card(
                                child: ListTile(
                                  leading: const Icon(Icons.pause_presentation),
                                  title: Text(
                                    '${(t['lines'] as List? ?? const []).fold<int>(0, (s, l) => s + (((l as Map)['q'] as num?) ?? 0).toInt())} items'
                                    '${t['tableId'] != null ? '  -  Table ${t['tableId']}' : ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${titleCase('${t['orderType']}')} parked ${t['heldAt'] == null ? '' : fmtDate(t['heldAt'])}',
                                    style: TextStyle(
                                      color: ctx.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        onPressed: () async {
                                          // Do not silently throw away a cart
                                          // that is already being worked on.
                                          if (_cart.isNotEmpty) {
                                            final replace = await confirm(
                                              ctx,
                                              'Replace the current order?',
                                              body: 'The items already in the terminal will be cleared.',
                                              action: 'Replace',
                                            );
                                            if (!replace) {
                                              return;
                                            }
                                          }
                                          if (ctx.mounted) {
                                            Navigator.pop(ctx);
                                          }
                                          _resume(t);
                                        },
                                        child: const Text('Resume'),
                                      ),
                                      IconButton(
                                        tooltip: 'Discard',
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                          color: Brand.danger,
                                        ),
                                        onPressed: () {
                                          _discardHeld(t);
                                          setSheet(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ item picking

  Future<void> _pick(AppState app, Map<String, dynamic> item) async {
    final variants = asRows(item['variants']);
    final addOns = _activeAddOns(item);
    if (variants.length <= 1 && addOns.isEmpty) {
      _add(item, variants.isEmpty ? null : variants.first);
      return;
    }
    // Sizes, or one "quantity" row when there is a single size.
    final rows = variants.length > 1
        ? variants
        : [
            {
              'id': (variants.firstOrNull?['id'] as num?)?.toInt() ?? 0,
              'name': variants.isEmpty
                  ? 'Quantity'
                  : '${variants.first['name']}',
              'name_bn': variants.firstOrNull?['name_bn'],
              'price': variants.firstOrNull?['price'] ?? item['base_price'],
            },
          ];
    final itemId = (item['id'] as num).toInt();
    final chosenAddOns = <int>{};

    // Every tap changes the order at once; the sheet only shows what is in it.
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final selected = [
            for (final a in addOns)
              if (chosenAddOns.contains((a['id'] as num).toInt()))
                {'id': a['id'], 'name': localized(app, a), 'price': a['price']},
          ];
          final selectedKey =
              (selected.map((a) => a['id'] as num).toList()..sort()).join('.');
          CartLine? lineFor(Map<String, dynamic> v) {
            final vid = variants.length > 1
                ? (v['id'] as num).toInt()
                : (variants.firstOrNull?['id'] as num?)?.toInt() ?? 0;
            return _cart
                .where((l) => l.key == '$itemId:$vid:$selectedKey')
                .firstOrNull;
          }

          final inOrder = _cart.where((l) => l.itemId == itemId);
          final count = inOrder.fold(0, (s, l) => s + l.quantity);
          final total = inOrder.fold<double>(0, (s, l) => s + l.total);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              height: 110,
                              child: FoodImage(
                                url: foodImageUrl(app, item),
                                iconSize: 40,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            localized(app, item),
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                          if ((item['description'] as String?)?.isNotEmpty ==
                              true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                localized(app, item, 'description'),
                                style: TextStyle(
                                  color: ctx.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          if (addOns.isNotEmpty) ...[
                            const SectionTitle(
                              'Add-ons (tick before choosing a size)',
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final a in addOns)
                                  FilterChip(
                                    label: Text(
                                      '${localized(app, a)}  +${_short(toNum(a['price']))}',
                                    ),
                                    selected: chosenAddOns.contains(
                                      (a['id'] as num).toInt(),
                                    ),
                                    onSelected: (on) => setSheet(() {
                                      final id = (a['id'] as num).toInt();
                                      on
                                          ? chosenAddOns.add(id)
                                          : chosenAddOns.remove(id);
                                    }),
                                  ),
                              ],
                            ),
                          ],
                          SectionTitle(
                            variants.length > 1
                                ? 'Tap a size to add it'
                                : 'Tap to add',
                          ),
                          for (final v in rows)
                            Builder(
                              builder: (_) {
                                final line = lineFor(v);
                                final unit =
                                    toNum(v['price']) +
                                    selected.fold<double>(
                                      0,
                                      (s, a) => s + toNum(a['price']),
                                    );
                                void add() {
                                  _add(
                                    item,
                                    variants.length > 1
                                        ? v
                                        : variants.firstOrNull,
                                    1,
                                    selected,
                                  );
                                  setSheet(() {});
                                }

                                return Card(
                                  child: ListTile(
                                    onTap: add,
                                    title: Text(
                                      localized(app, v),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      fmtMoney(unit),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: ctx.brand,
                                      ),
                                    ),
                                    trailing: line == null
                                        ? _RoundButton(
                                            icon: Icons.add,
                                            onTap: add,
                                            size: 32,
                                          )
                                        : _Stepper(
                                            qty: line.quantity,
                                            onMinus: () {
                                              _decrement(line);
                                              setSheet(() {});
                                            },
                                            onPlus: add,
                                          ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          count == 0
                              ? 'Nothing added yet'
                              : '$count in order  -  ${fmtMoney(total)}',
                          style: TextStyle(
                            color: ctx.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ item card

  List<Map<String, dynamic>> _activeAddOns(Map<String, dynamic> item) =>
      asRows(item['add_ons']).where((a) => a['is_active'] != false).toList();

  ({
    String price,
    int qty,
    CartLine? line,
    bool multi,
    bool sheet,
    bool available,
  })
  _facts(Map<String, dynamic> item) {
    final id = (item['id'] as num).toInt();
    final variants = asRows(item['variants']);
    final multi = variants.length > 1;
    final price = multi
        ? 'from ${_short(variants.map((v) => toNum(v['price'])).reduce((a, b) => a < b ? a : b))}'
        : _short(
            toNum(
              variants.isEmpty ? item['base_price'] : variants.first['price'],
            ),
          );
    return (
      price: price,
      qty: _qtyOfItem(id),
      line: multi || _activeAddOns(item).isNotEmpty
          ? null
          : _cart.where((l) => l.itemId == id).firstOrNull,
      multi: multi,
      sheet: multi || _activeAddOns(item).isNotEmpty,
      available: item['is_available'] != false,
    );
  }

  Widget _control(
    AppState app,
    Map<String, dynamic> item,
    ({
      String price,
      int qty,
      CartLine? line,
      bool multi,
      bool sheet,
      bool available,
    })
    f,
  ) {
    if (!f.available) {
      return const SizedBox.shrink();
    }
    final line = f.line;
    return line != null
        ? _Stepper(
            qty: line.quantity,
            onMinus: () => _decrement(line),
            onPlus: () => _add(item, line.variant),
            size: 28,
          )
        : _RoundButton(icon: Icons.add, onTap: () => _pick(app, item));
  }

  /// Small tile for a three column grid: a short photo, then the name and the
  /// price with a add button. A "+" after the price means the item has sizes.
  Widget _itemCard(AppState app, Map<String, dynamic> item) {
    final f = _facts(item);
    final line = f.line;
    final price = f.price
        .replaceFirst('from BDT ', '')
        .replaceFirst('BDT ', '');
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: f.available ? () => _pick(app, item) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 62,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FoodImage(url: foodImageUrl(app, item), iconSize: 20),
                  if (f.qty > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: context.brand,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${f.qty}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  if (!f.available)
                    Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      alignment: Alignment.center,
                      child: const Text(
                        'Unavailable',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 3, 4, 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localized(app, item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            f.multi ? '$price+' : price,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: context.brand,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (f.available)
                          line != null
                              ? _Stepper(
                                  qty: line.quantity,
                                  onMinus: () => _decrement(line),
                                  onPlus: () => _add(item, line.variant),
                                  size: 22,
                                )
                              : _RoundButton(
                                  icon: Icons.add,
                                  onTap: () => _pick(app, item),
                                  size: 24,
                                ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One row per item: the densest layout, about nine items per screen.
  Widget _itemRow(AppState app, Map<String, dynamic> item) {
    final f = _facts(item);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: f.available ? () => _pick(app, item) : null,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FoodImage(url: foodImageUrl(app, item), iconSize: 22),
                    if (!f.available)
                      Container(color: Colors.black.withValues(alpha: 0.55)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            localized(app, item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      f.available ? f.price : 'Unavailable',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: f.available ? context.brand : Brand.danger,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _control(app, item, f),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ cart sheet

  Future<void> _openCart(AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void refresh() {
            setState(() {});
            setSheet(() {});
            _persist();
            if (_cart.isEmpty) {
              Navigator.pop(ctx);
            }
          }

          final totals = _totals(app);
          final tables = asRows(app.bootstrap?['tables']);
          return Padding(
            // Keyboard inset while typing and a footer-height gap above the
            // gesture bar when closed, so the Place order / Pay buttons
            // always stay comfortably tappable.
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  28,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Current order',
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          _reset();
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in _orderTypes)
                        ChoiceChip(
                          avatar: Icon(t.$3, size: 18),
                          label: Text(t.$2),
                          selected: _orderType == t.$1,
                          onSelected: (_) {
                            setState(() => _orderType = t.$1);
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                  if (_orderType == 'dine_in' && tables.isNotEmpty) ...[
                    const SectionTitle('Table'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in tables)
                          ChoiceChip(
                            avatar: CircleAvatar(
                              radius: 5,
                              backgroundColor: '${t['status']}' == 'free'
                                  ? Brand.success
                                  : Brand.warning,
                            ),
                            label: Text('${t['name']}'),
                            selected: _tableId == (t['id'] as num).toInt(),
                            onSelected: (_) {
                              setState(
                                () => _tableId = (t['id'] as num).toInt(),
                              );
                              setSheet(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                  const SectionTitle('Items'),
                  for (final l in List.of(_cart))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: FoodImage(
                                url: foodImageUrl(app, l.item),
                                iconSize: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  localized(app, l.item),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${l.variant == null ? '' : '${localized(app, l.variant!)}  -  '}${fmtMoney(l.unitPrice)}',
                                  style: TextStyle(
                                    color: ctx.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                if (l.addOns.isNotEmpty)
                                  Text(
                                    '+ ${l.addOnNames}',
                                    style: TextStyle(
                                      color: ctx.brand,
                                      fontSize: 11.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _Stepper(
                                qty: l.quantity,
                                onMinus: () {
                                  _decrement(l);
                                  refresh();
                                },
                                onPlus: () {
                                  setState(() => l.quantity++);
                                  refresh();
                                },
                              ),
                              const SizedBox(height: 2),
                              Text(
                                fmtMoney(l.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                  _row(ctx, 'Subtotal', fmtMoney(_subtotal)),
                  if (totals.discount > 0)
                    _row(
                      ctx,
                      'Discount',
                      '-${fmtMoney(totals.discount)}',
                      bold: false,
                      color: Brand.success,
                    ),
                  if (totals.service > 0)
                    _row(ctx, 'Service charge', fmtMoney(totals.service)),
                  if (totals.vat > 0) _row(ctx, 'VAT', fmtMoney(totals.vat)),
                  _row(ctx, 'Total', fmtMoney(totals.total), bold: true),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                          ),
                          onPressed: () => _editDiscount(ctx, setSheet),
                          icon: Icon(
                            _discountValue > 0
                                ? Icons.discount
                                : Icons.discount_outlined,
                            size: 18,
                            color: _discountValue > 0 ? Brand.success : null,
                          ),
                          label: Text(
                            _discountValue > 0
                                ? _discountType == 'percent'
                                      ? '${_trimNum(_discountValue)}% off'
                                      : '${fmtMoney(_discountValue)} off'
                                : 'Discount',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                          ),
                          onPressed: () {
                            _hold();
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.pause_presentation, size: 18),
                          label: const Text('Hold'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  field(
                    _customerMobile,
                    'Customer mobile (optional)',
                    type: TextInputType.phone,
                  ),
                  field(_note, 'Note for the kitchen (optional)'),
                  if (widget.edit != null)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _place(app, ctx, pay: false),
                      icon: const Icon(Icons.save_outlined),
                      label: Text('Save changes to ${widget.edit!.invoiceNo}'),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _place(app, ctx, pay: false),
                            child: const Text('Place order', maxLines: 1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 6,
                          child: FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _place(app, ctx, pay: true),
                            icon: const Icon(Icons.payments),
                            label: Text('Pay ${fmtMoney(totals.total)}'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String a,
    String b, {
    bool bold = false,
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          a,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : null,
            fontSize: bold ? 16 : 14,
            color: bold ? null : context.muted,
          ),
        ),
        Text(
          b,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontSize: bold ? 16 : 14,
            color: color,
          ),
        ),
      ],
    ),
  );

  String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Bill-level discount: a percentage of the subtotal or a fixed amount,
  /// like the web POS discount panel.
  Future<void> _editDiscount(
    BuildContext sheetContext,
    void Function(void Function()) setSheet,
  ) async {
    final controller = TextEditingController(
      text: _discountValue > 0 ? _trimNum(_discountValue) : '',
    );
    var type = _discountType;
    final saved = await showModalBottomSheet<bool>(
      context: sheetContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom +
                28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Bill discount', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Applied before service charge and VAT.',
                style: TextStyle(color: ctx.muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final t in const [
                    ('percent', 'Percent'),
                    ('fixed', 'Fixed amount'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: t.$1 == 'percent' ? 8 : 0,
                        ),
                        child: ChoiceChip(
                          label: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(t.$2),
                          ),
                          selected: type == t.$1,
                          onSelected: (_) => setDialog(() => type = t.$1),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              field(
                controller,
                type == 'percent'
                    ? 'Percent off (e.g. 10)'
                    : 'Amount off (BDT)',
                type: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Apply discount'),
              ),
              TextButton(
                onPressed: _discountValue > 0
                    ? () => Navigator.pop(ctx, false)
                    : null,
                child: const Text('Remove discount'),
              ),
            ],
          ),
        ),
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (saved == null) {
      return;
    }
    setState(() {
      _discountType = type;
      // Keep the value inside sane bounds so what the cashier sees is what
      // the server charges: percent within 0-100, fixed within the subtotal.
      var value = saved ? (double.tryParse(text) ?? 0.0) : 0.0;
      value =
          (type == 'percent'
                  ? value.clamp(0.0, 100.0)
                  : value.clamp(0.0, _subtotal))
              .toDouble();
      _discountValue = value;
    });
    setSheet(() {});
  }

  // ------------------------------------------------------------ edit mode

  /// Fills the cart from the order being revised, matching its lines to the
  /// menu cached on this device.
  void _seedFromEdit() {
    final app = AppScope.read(context);
    final order = widget.edit!.order;
    final lines = _linesFromSnapshot([
      for (final i in asRows(order['items']))
        {
          'i': (i['menu_item_id'] as num?)?.toInt(),
          'v': (i['variant_id'] as num?)?.toInt(),
          'q': (i['quantity'] as num).toInt(),
          'a': [
            for (final a in asRows(i['add_ons']))
              if (a['id'] != null) (a['id'] as num).toInt(),
          ],
        },
    ], app);
    final input = order['discount_input'] as Map?;
    setState(() {
      _cart.addAll(lines);
      _orderType = '${order['order_type'] ?? 'takeaway'}';
      _tableId = (order['table_id'] as num?)?.toInt();
      _note.text = '${order['note'] ?? ''}';
      _customerMobile.text = '${order['customer_mobile'] ?? ''}';
      if (input != null) {
        _discountType = '${input['type']}';
        _discountValue = toNum(input['value']);
      } else if (toNum(order['discount_amount']) > 0) {
        _discountType = 'fixed';
        _discountValue = toNum(order['discount_amount']);
      }
    });
  }

  /// The cart as receipt lines: names, prices and the ids needed to edit the
  /// order again later.
  List<Map<String, dynamic>> _receiptLines() => [
    for (final l in _cart)
      {
        'menu_item_id': l.itemId,
        'variant_id': l.variantId,
        'name': l.variant == null
            ? '${l.item['name']}'
            : '${l.item['name']} (${l.variant!['name']})',
        'name_bn': l.item['name_bn'],
        'quantity': l.quantity,
        'unit_price': toNum(l.variant?['price'] ?? l.item['base_price'])
            .toStringAsFixed(2),
        'add_ons': [
          for (final a in l.addOns)
            {'id': a['id'], 'name': a['name'], 'price': a['price'], 'qty': 1},
        ],
        'line_total': l.total.toStringAsFixed(2),
      },
  ];

  Map<String, dynamic> _snapshotFor(
    AppState app, {
    required String invoiceNo,
    required ({double service, double vat, double discount, double total})
    totals,
    String? tokenNo,
    double? tendered,
    String? createdAt,
  }) {
    final tableName = asRows(app.bootstrap?['tables'])
        .where((t) => (t['id'] as num?)?.toInt() == _tableId)
        .map((t) => '${t['name']}')
        .firstOrNull;
    return {
      ...OfflineOrders.snapshot(
        app: app,
        invoiceNo: invoiceNo,
        orderType: _orderType,
        lines: _receiptLines(),
        subtotal: _subtotal,
        discount: totals.discount,
        service: totals.service,
        vat: totals.vat,
        total: totals.total,
        tableName: _orderType == 'dine_in' ? tableName : null,
        tableId: _orderType == 'dine_in' ? _tableId : null,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        customerMobile: _customerMobile.text.trim().isEmpty
            ? null
            : _customerMobile.text.trim(),
        tendered: tendered,
        tokenNo: tokenNo,
        createdAt: createdAt,
      ),
      if (_discountValue > 0)
        'discount_input': {'type': _discountType, 'value': _discountValue},
    };
  }

  /// Order fields shared by every offline write.
  Map<String, dynamic> _orderFields(List<Map<String, dynamic>> items) => {
    'order_type': _orderType,
    'items': items,
    if (_orderType == 'dine_in' && _tableId != null)
      'restaurant_table_id': _tableId,
    if (_customerMobile.text.trim().isNotEmpty)
      'customer_mobile': _customerMobile.text.trim(),
    if (_discountValue > 0)
      'discount': {
        'type': _discountType,
        'value': _discountType == 'percent'
            ? _discountValue.clamp(0, 100)
            : _discountValue.clamp(0, _subtotal),
      },
    if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
  };

  void _openReceipt(String clientId, {bool replace = false}) {
    final route = MaterialPageRoute<void>(
      builder: (_) => ReceiptScreen(localClientId: clientId),
    );
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  /// A new order that could not reach the server: number it, keep a printable
  /// copy and queue it for sync.
  Future<void> _saveOffline(
    AppState app,
    BuildContext sheetContext,
    List<Map<String, dynamic>> items,
    ({double service, double vat, double discount, double total}) totals, {
    required bool pay,
  }) async {
    final clientId = newClientId();
    final invoice = await OfflineOrders.nextInvoice(app);
    final token = await OfflineOrders.nextToken(app);
    final order = _snapshotFor(
      app,
      invoiceNo: invoice,
      totals: totals,
      tokenNo: token,
      tendered: pay ? totals.total : null,
    );
    await OfflineOrders.saveNew(
      app,
      clientId: clientId,
      invoiceNo: invoice,
      tokenNo: token,
      order: order,
    );
    await app.queue(
      'order',
      {
        'branch_id': app.branchId,
        'terminal': 'T01',
        'invoice_no': invoice,
        ..._orderFields(items),
        if (pay) 'tendered': totals.total,
      },
      label: 'POS order $invoice (${fmtMoney(totals.total)})',
      clientId: clientId,
    );
    if (mounted && sheetContext.mounted) {
      SoundFx.play('order_created');
      _reset();
      Navigator.of(sheetContext).pop();
      snack(
        context,
        'Offline: $invoice saved. It will sync when the network is back.',
      );
      _openReceipt(clientId);
    }
  }

  /// Saves a revision. An order still waiting on this device is rewritten in
  /// place, keeping its invoice number and token; one already on the server
  /// gets a queued `order_edit` and a fresh printable copy.
  Future<void> _saveEdit(
    AppState app,
    BuildContext sheetContext,
    List<Map<String, dynamic>> items,
    ({double service, double vat, double discount, double total}) totals,
  ) async {
    final edit = widget.edit!;
    final local = edit.local;
    final invoice = edit.invoiceNo;
    final token = edit.order['token_no'] as String?;
    String clientId;

    if (local != null) {
      final queued = await app.db.outboxItem(local.clientId);
      if (queued == null || queued.status != OutboxStatus.pending) {
        if (sheetContext.mounted) {
          snack(
            sheetContext,
            'This order was just synced. Open it again from Orders to edit it.',
            error: true,
          );
        }
        return;
      }
      clientId = local.clientId;
      final wasPaid = queued.payload['tendered'] != null;
      final payload = {
        ...queued.payload,
        ..._orderFields(items),
        if (wasPaid) 'tendered': totals.total,
      };
      if (_orderType != 'dine_in') {
        payload.remove('restaurant_table_id');
      }
      if (_discountValue <= 0) {
        payload.remove('discount');
      }
      if (_customerMobile.text.trim().isEmpty) {
        payload.remove('customer_mobile');
      }
      if (_note.text.trim().isEmpty) {
        payload.remove('note');
      }
      await app.db.updateOutboxPayload(clientId, payload);
      final order = _snapshotFor(
        app,
        invoiceNo: invoice,
        totals: totals,
        tokenNo: token,
        tendered: wasPaid ? totals.total : null,
        createdAt: '${local.order['created_at']}',
      );
      await app.db.saveLocalOrder(local.copyWith(order: order));
      await app.refreshPending();
    } else {
      clientId = newClientId();
      final order = _snapshotFor(
        app,
        invoiceNo: invoice,
        totals: totals,
        tokenNo: token,
      );
      await app.db.saveLocalOrder(
        LocalOrder(
          clientId: clientId,
          kind: 'edit',
          invoiceNo: invoice,
          tokenNo: token,
          order: order,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          serverId: edit.orderId,
        ),
      );
      await app.queue(
        'order_edit',
        {
          if (edit.orderId != null) 'order_id': edit.orderId,
          'order_client_id': ?edit.orderClientId,
          ..._orderFields(items),
        },
        label: 'Edit $invoice',
        clientId: clientId,
      );
    }

    if (mounted && sheetContext.mounted) {
      SoundFx.play('order_created');
      _reset();
      Navigator.of(sheetContext).pop();
      snack(context, '$invoice updated.');
      _openReceipt(clientId, replace: true);
    }
  }

  Future<void> _place(
    AppState app,
    BuildContext sheetContext, {
    required bool pay,
  }) async {
    if (_orderType == 'dine_in' &&
        _tableId == null &&
        asRows(app.bootstrap?['tables']).isNotEmpty) {
      snack(sheetContext, 'Choose a table for dine in.', error: true);
      return;
    }
    if (widget.edit != null) {
      setState(() => _busy = true);
      try {
        await _saveEdit(app, sheetContext, [
          for (final l in _cart)
            {
              'menu_item_id': l.itemId,
              'variant_id': ?l.variantId,
              'quantity': l.quantity,
              if (l.addOns.isNotEmpty)
                'add_ons': [
                  for (final a in l.addOns) {'id': a['id'], 'qty': 1},
                ],
            },
        ], _totals(app));
      } finally {
        if (mounted) {
          setState(() => _busy = false);
        }
      }
      return;
    }
    setState(() => _busy = true);
    final items = [
      for (final l in _cart)
        {
          'menu_item_id': l.itemId,
          'variant_id': ?l.variantId,
          'quantity': l.quantity,
          if (l.addOns.isNotEmpty)
            'add_ons': [
              for (final a in l.addOns) {'id': a['id'], 'qty': 1},
            ],
        },
    ];
    final totals = _totals(app);

    try {
      final body = {
        'order_type': _orderType,
        'items': items,
        'terminal': 'T01',
        'restaurant_table_id': ?(_orderType == 'dine_in' ? _tableId : null),
        if (_customerMobile.text.trim().isNotEmpty)
          'customer_mobile': _customerMobile.text.trim(),
        if (_discountValue > 0)
          'discount': {
            'type': _discountType,
            'value': _discountType == 'percent'
                ? _discountValue.clamp(0, 100)
                : _discountValue.clamp(0, _subtotal),
          },
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      };
      final order = await app.api.post(
        '/branches/${app.branchId}/orders',
        body: body,
        idempotencyKey: newClientId(),
      ) as Map<String, dynamic>;

      if (!mounted || !sheetContext.mounted) {
        return;
      }
      final invoice = '${order['invoice_no']}';
      SoundFx.play('order_created');
      _reset();
      Navigator.of(sheetContext).pop();
      if (pay) {
        final msg = await showPaymentSheet(
          context,
          orderId: (order['id'] as num).toInt(),
          invoiceNo: invoice,
          total: order['total'],
        );
        if (mounted) {
          final orderId = (order['id'] as num).toInt();
          final paid = msg != null;
          snack(
            context,
            paid
                ? 'Order $invoice. $msg'
                : 'Order $invoice placed. Payment pending.',
            actionLabel: paid ? 'Receipt' : null,
            onAction: paid
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptScreen(orderId: orderId),
                    ),
                  )
                : null,
          );
        }
      } else if (mounted) {
        final orderId = (order['id'] as num).toInt();
        snack(
          context,
          'Order $invoice placed.',
          actionLabel: 'Print',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ReceiptScreen(orderId: orderId)),
          ),
        );
      }
    } on ApiException catch (e) {
      if (!e.isNetwork) {
        if (sheetContext.mounted) {
          snack(sheetContext, e.fullMessage, error: true);
        }
      } else if (sheetContext.mounted) {
        await _saveOffline(app, sheetContext, items, totals, pay: pay);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // ------------------------------------------------------------ screen

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cats = asRows(app.bootstrap?['categories']);
    final branch = (app.bootstrap?['branch'] as Map?)?['name'] as String?;

    List<Map<String, dynamic>> items;
    if (_query.isNotEmpty) {
      items = [for (final c in cats) ...asRows(c['items'])]
          .where(
            (i) =>
                localized(app, i).toLowerCase().contains(_query.toLowerCase()),
          )
          .toList();
    } else if (_category == 0) {
      items = [for (final c in cats) ...asRows(c['items'])];
    } else {
      items = asRows(cats[(_category - 1).clamp(0, cats.length - 1)]['items']);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('POS', style: TextStyle(fontSize: 18)),
            if (branch != null)
              Text(
                branch,
                style: TextStyle(fontSize: 12, color: context.brand),
              ),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: 'Parked orders',
                icon: const Icon(Icons.pause_presentation),
                onPressed: _held.isEmpty ? null : _showHeld,
              ),
              if (_held.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Brand.warning,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_held.length}',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: _listMode ? 'Show photos' : 'Show list',
            icon: Icon(_listMode ? Icons.grid_view : Icons.view_list),
            onPressed: _toggleView,
          ),
        ],
      ),
      bottomNavigationBar: _count == 0
          ? null
          : _CartBar(
              count: _count,
              total: _totals(app).total,
              onTap: () => _openCart(app),
            ),
      body: cats.isEmpty
          ? const EmptyState(
              'The menu has not been downloaded yet. Connect once to load it.',
            )
          : Column(
              children: [
                if (!app.online) const OfflineNote(null),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search food and drinks',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    itemCount: cats.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final label = i == 0
                          ? 'All'
                          : localized(app, cats[i - 1]);
                      final n = i == 0
                          ? cats.fold<int>(
                              0,
                              (s, c) => s + asRows(c['items']).length,
                            )
                          : asRows(cats[i - 1]['items']).length;
                      return ChoiceChip(
                        label: Text('$label  $n'),
                        selected: _category == i && _query.isEmpty,
                        onSelected: (_) => setState(() {
                          _category = i;
                          _query = '';
                          _search.clear();
                        }),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const EmptyState('No items match your search.')
                      : _listMode
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, i) => _itemRow(app, items[i]),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 150,
                                mainAxisExtent: 132,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                              ),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _itemCard(app, items[i]),
                        ),
                ),
              ],
            ),
    );
  }
}

/// Sticky bar at the bottom: how many items, the total, and a way to open the order.
class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.count,
    required this.total,
    required this.onTap,
  });

  final int count;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 10,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.brand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.shopping_basket, color: context.brand),
                  ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Brand.danger,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(color: context.muted, fontSize: 11),
                    ),
                    Text(
                      fmtMoney(total),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(150, 48)),
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('View order'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.size = 30});

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brand,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.6,
            color: context.isDark ? Brand.navy : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
    this.size = 32,
  });

  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback f, {bool filled = false}) =>
        Material(
          color: filled ? context.brand : context.brand.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: f,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: size * 0.55,
                color: filled
                    ? (context.isDark ? Brand.navy : Colors.white)
                    : context.brand,
              ),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove, onMinus),
        SizedBox(
          width: size * 0.75,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: size < 28 ? 11.5 : 14,
            ),
          ),
        ),
        btn(Icons.add, onPlus, filled: true),
      ],
    );
  }
}
