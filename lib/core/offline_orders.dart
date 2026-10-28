import 'dart:math';

import 'app_state.dart';
import 'local_db.dart';

/// Everything a terminal needs to make an invoice and a kitchen token with
/// no network: numbers that cannot clash with other terminals, a printable
/// snapshot of the order, and the edit-before-sync path.
class OfflineOrders {
  const OfflineOrders._();

  static const _defaultPattern =
      '{BRANCH}-{TERMINAL}-{YYYY}{MM}{DD}-{TIME}-{RAND}';
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _randomCode([int length = 4]) {
    final rnd = Random.secure();
    return List.generate(
      length,
      (_) => _alphabet[rnd.nextInt(_alphabet.length)],
    ).join();
  }

  /// The branch's invoice pattern when it can be filled in offline. A
  /// counter pattern (`{SEQ}`) needs the server, so those fall back to the
  /// random default and the server renumbers on sync if it must.
  static String _pattern(AppState app) {
    final branch = Map<String, dynamic>.from(
      (app.bootstrap?['branch'] as Map?) ?? const {},
    );
    final settings = Map<String, dynamic>.from(
      (branch['pos_settings'] as Map?) ?? const {},
    );
    final pattern = '${settings['invoice_pattern'] ?? _defaultPattern}';
    return pattern.contains('{SEQ}') ? _defaultPattern : pattern;
  }

  /// A new invoice number such as `BR01-T01-20261028-143205-K7Q4`, never one
  /// this device has already issued.
  static Future<String> nextInvoice(
    AppState app, {
    String terminal = 'T01',
  }) async {
    final branch = Map<String, dynamic>.from(
      (app.bootstrap?['branch'] as Map?) ?? const {},
    );
    final code = '${branch['code'] ?? 'BR'}';
    final taken = (await app.db.localOrders()).map((o) => o.invoiceNo).toSet();
    final pattern = _pattern(app);

    for (var attempt = 0; attempt < 25; attempt++) {
      final now = DateTime.now();
      final candidate = pattern
          .replaceAll('{BRANCH}', code)
          .replaceAll('{TERMINAL}', terminal.toUpperCase())
          .replaceAll('{YYYY}', '${now.year}')
          .replaceAll('{YY}', _two(now.year % 100))
          .replaceAll('{MM}', _two(now.month))
          .replaceAll('{DD}', _two(now.day))
          .replaceAll(
            '{TIME}',
            '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}',
          )
          .replaceAll('{RAND}', _randomCode());
      if (!taken.contains(candidate)) {
        return candidate;
      }
    }
    return '$code-$terminal-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// The next kitchen token for today on this terminal, e.g. `T01-007`.
  /// The count starts again each day and survives restarts.
  static Future<String> nextToken(
    AppState app, {
    String terminal = 'T01',
  }) async {
    final now = DateTime.now();
    final day = '${now.year}${_two(now.month)}${_two(now.day)}';
    final savedDay = await app.db.meta('token_day');
    var n = savedDay == day
        ? int.tryParse(await app.db.meta('token_n') ?? '') ?? 0
        : 0;
    n += 1;
    await app.db.setMeta('token_day', day);
    await app.db.setMeta('token_n', '$n');
    return '${terminal.toUpperCase()}-${n.toString().padLeft(3, '0')}';
  }

  /// The order in the same shape the receipt screen reads from the server,
  /// built from what the cashier entered.
  static Map<String, dynamic> snapshot({
    required AppState app,
    required String invoiceNo,
    required String orderType,
    required List<Map<String, dynamic>> lines,
    required double subtotal,
    required double discount,
    required double service,
    required double vat,
    required double total,
    String? tableName,
    int? tableId,
    String? note,
    String? customerMobile,
    double? tendered,
    String? tokenNo,
    String? createdAt,
  }) {
    final rounding = total - (subtotal - discount + service + vat);
    return {
      'invoice_no': invoiceNo,
      'token_no': tokenNo,
      'status': tendered != null ? 'paid' : 'pending',
      'order_type': orderType,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
      'table': tableName,
      'table_id': tableId,
      'customer_mobile': customerMobile,
      'cashier': app.userName,
      'note': note,
      'subtotal': subtotal.toStringAsFixed(2),
      'discount_amount': discount.toStringAsFixed(2),
      'service_charge': service.toStringAsFixed(2),
      'vat_amount': vat.toStringAsFixed(2),
      'delivery_fee': '0.00',
      'rounding': rounding.toStringAsFixed(2),
      'total': total.toStringAsFixed(2),
      'items': lines,
      'payments': tendered == null
          ? const []
          : [
              {
                'method': 'cash',
                'amount': total.toStringAsFixed(2),
                'tendered': tendered.toStringAsFixed(2),
                'change_due': (tendered - total)
                    .clamp(0, double.infinity)
                    .toStringAsFixed(2),
              },
            ],
    };
  }

  /// Saves a new offline order: its receipt snapshot plus the outbox item.
  static Future<LocalOrder> saveNew(
    AppState app, {
    required String clientId,
    required String invoiceNo,
    required String tokenNo,
    required Map<String, dynamic> order,
  }) async {
    final saved = LocalOrder(
      clientId: clientId,
      kind: 'order',
      invoiceNo: invoiceNo,
      tokenNo: tokenNo,
      order: order,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await app.db.saveLocalOrder(saved);
    return saved;
  }
}
