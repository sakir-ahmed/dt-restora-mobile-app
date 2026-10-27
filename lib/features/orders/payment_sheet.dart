import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/sounds.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

const paymentMethods = ['cash', 'bkash', 'nagad', 'card'];

bool _needsReference(String method) => method == 'bkash' || method == 'nagad';

/// Collect payment for an order, web-admin style: one or more lines, each
/// with a method, an amount and — for wallets — a transaction reference.
/// Supports split bills, quick cash amounts and change. Online it posts to
/// the order's payment endpoint; offline each line is queued for
/// `/sync/push`. Returns a short result message, or null when cancelled.
Future<String?> showPaymentSheet(
  BuildContext context, {
  required int orderId,
  required String invoiceNo,
  required Object? total,
}) {
  return showForm<String>(
    context,
    title: 'Pay $invoiceNo',
    builder: (_) => _PaymentForm(orderId: orderId, total: toNum(total)),
  );
}

class _PayLine {
  _PayLine(this.method, String amount)
      : amount = TextEditingController(text: amount),
        reference = TextEditingController();

  String method;
  final TextEditingController amount;
  final TextEditingController reference;
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.orderId, required this.total});

  final int orderId;
  final double total;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final List<_PayLine> _lines = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _lines.add(_PayLine('cash', widget.total.toStringAsFixed(2)));
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.amount.dispose();
      l.reference.dispose();
    }
    super.dispose();
  }

  double _amountOf(_PayLine l) => double.tryParse(l.amount.text.trim()) ?? 0;
  double get _paid => _lines.fold(0, (s, l) => s + _amountOf(l));
  double get _remaining => widget.total - _paid;

  void _setMethod(_PayLine line, String method) {
    setState(() {
      line.method = method;
      // A single non-cash payment always covers the whole bill, like the
      // web POS: auto-fill the exact amount.
      if (_lines.length == 1 && method != 'cash') {
        line.amount.text = widget.total.toStringAsFixed(2);
      }
    });
  }

  void _addLine() {
    setState(() {
      // Like the web POS: when the single line already covers the whole
      // bill, split it in half so both parts are meaningful.
      if (_lines.length == 1) {
        final a = _amountOf(_lines.first);
        if (a == 0 || (a - widget.total).abs() < 0.01) {
          _lines.first.amount.text = (widget.total / 2).ceil().toStringAsFixed(2);
        }
      }
      final used = _lines.map((l) => l.method).toSet();
      final method = paymentMethods.firstWhere((m) => !used.contains(m), orElse: () => 'cash');
      final remaining = _remaining > 0.009 ? max(0, _remaining).toStringAsFixed(2) : '';
      _lines.add(_PayLine(method, remaining));
    });
  }

  void _quickCash(_PayLine line, double add) {
    setState(() {
      final current = add == 0 ? 0 : _amountOf(line);
      line.amount.text = (add == 0 ? widget.total : current + add).toStringAsFixed(2);
    });
  }

  String? get _problem {
    for (final l in _lines) {
      if (_amountOf(l) <= 0) {
        return 'Every payment line needs an amount.';
      }
      if (_needsReference(l.method) && l.reference.text.trim().isEmpty) {
        return 'Add the transaction ID for the ${titleCase(l.method)} payment.';
      }
    }
    final first = _lines.first;
    if (_lines.length == 1 && first.method == 'cash' && _amountOf(first) < widget.total - 0.009) {
      return 'Cash received is less than the bill.';
    }
    if (_lines.length == 1 && first.method != 'cash' && (_amountOf(first) - widget.total).abs() > 0.01) {
      return 'A single card or wallet payment must cover the whole bill.';
    }
    if (_lines.length > 1 && _remaining.abs() > 0.01) {
      return _remaining > 0
          ? 'BDT ${_remaining.toStringAsFixed(2)} still left to assign.'
          : 'Payments exceed the bill by BDT ${(-_remaining).toStringAsFixed(2)}.';
    }
    return null;
  }

  Future<void> _pay() async {
    final problem = _problem;
    if (problem != null) {
      snack(context, problem, error: true);
      return;
    }
    final app = AppScope.read(context);
    setState(() => _busy = true);

    final first = _lines.first;
    final isSingleCash = _lines.length == 1 && first.method == 'cash';
    final body = isSingleCash
        ? {'tendered': _amountOf(first)}
        : {
            'lines': [
              for (final l in _lines)
                {
                  'method': l.method,
                  'amount': _amountOf(l),
                  if (l.reference.text.trim().isNotEmpty) 'reference': l.reference.text.trim(),
                }
            ],
          };

    String message;
    try {
      final result = await app.api.post(
        '/branches/${app.branchId}/orders/${widget.orderId}/payments',
        body: body,
        idempotencyKey: newClientId(),
      );
      SoundFx.play('order_paid');
      final change = result is Map ? result['change'] : null;
      final changeValue = toNum(change) > 0 ? toNum(change) : (isSingleCash ? max(0, _amountOf(first) - widget.total) : 0);
      message = changeValue > 0
          ? 'Paid. Change ${fmtMoney(changeValue)}'
          : _lines.length > 1
              ? 'Split payment recorded (${_lines.length} parts).'
              : 'Payment recorded.';
    } on ApiException catch (e) {
      if (!e.isNetwork) {
        if (mounted) {
          setState(() => _busy = false);
          snack(context, e.fullMessage, error: true);
        }
        return;
      }
      for (final l in _lines) {
        await app.queue(
          'payment',
          {
            'order_id': widget.orderId,
            'method': l.method,
            'amount': _amountOf(l),
            'tendered': _amountOf(l),
          },
          label: 'Payment ${titleCase(l.method)} ${fmtMoney(_amountOf(l))} for order ${widget.orderId}',
        );
      }
      SoundFx.play('order_paid');
      message = 'Offline: payment saved and will sync.';
    }
    if (mounted) {
      Navigator.pop(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final first = _lines.first;
    final change = _lines.length == 1 && first.method == 'cash' && _amountOf(first) > widget.total
        ? _amountOf(first) - widget.total
        : 0.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Text('Total ${fmtMoney(widget.total)}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: context.fg, fontWeight: FontWeight.w700)),
        ),
        if (_lines.length > 1)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Paid ${fmtMoney(_paid)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(
              _remaining.abs() <= 0.01 ? 'Fully covered' : 'Left ${fmtMoney(max(0, _remaining))}',
              style: TextStyle(
                fontSize: 12,
                color: _remaining.abs() <= 0.01 ? Brand.success : Brand.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
      ]),
      const SizedBox(height: 12),
      for (var i = 0; i < _lines.length; i++)
        _lineCard(context, _lines[i], i),
      TextButton.icon(
        onPressed: _busy ? null : _addLine,
        icon: const Icon(Icons.call_split, size: 16),
        label: const Text('Split payment (pay part by part)'),
      ),
      if (change > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Brand.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.south_east, size: 16, color: Brand.success),
              const SizedBox(width: 8),
              Text('Change ${fmtMoney(change)}',
                  style: const TextStyle(color: Brand.success, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      FilledButton(
        onPressed: _busy || problem != null ? null : _pay,
        child: Text(_busy
            ? 'Saving...'
            : _lines.length > 1
                ? 'Confirm split payment'
                : 'Take payment'),
      ),
      if (problem != null && _lines.any((l) => _amountOf(l) > 0))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(problem, textAlign: TextAlign.center, style: TextStyle(color: Brand.warning, fontSize: 12)),
        ),
    ]);
  }

  Widget _lineCard(BuildContext context, _PayLine line, int index) {
    final cash = line.method == 'cash';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(_lines.length > 1 ? 'Payment ${index + 1}' : 'Method',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            if (_lines.length > 1)
              IconButton(
                tooltip: 'Remove this part',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _lines.remove(line);
                          line.amount.dispose();
                          line.reference.dispose();
                        }),
              ),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in paymentMethods)
              ChoiceChip(
                label: Text(titleCase(m)),
                visualDensity: VisualDensity.compact,
                selected: line.method == m,
                onSelected: _busy ? null : (_) => _setMethod(line, m),
              ),
          ]),
          const SizedBox(height: 10),
          field(
            line.amount,
            cash ? 'Cash received' : 'Amount',
            type: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (cash)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final q in const [(null, 'Exact'), (100.0, '+100'), (500.0, '+500'), (1000.0, '+1000')])
                  ActionChip(
                    label: Text(q.$2),
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => _quickCash(line, q.$1 ?? 0),
                  ),
              ]),
            ),
          if (!cash)
            field(
              line.reference,
              _needsReference(line.method) ? 'Transaction ID (TrxID)' : 'Reference (optional)',
              type: TextInputType.text,
            ),
        ]),
      ),
    );
  }
}
