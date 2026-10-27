import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

const paymentMethods = ['cash', 'card', 'bkash', 'nagad'];

/// Collect payment for an order. Online it posts to the order's payment
/// endpoint; offline the payment is queued for `/sync/push`.
/// Returns a short result message, or null when cancelled.
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

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.orderId, required this.total});

  final int orderId;
  final double total;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  String _method = 'cash';
  late final _amount = TextEditingController(text: widget.total.toStringAsFixed(2));
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final app = AppScope.read(context);
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      snack(context, 'Enter an amount.', error: true);
      return;
    }
    setState(() => _busy = true);

    final body = _method == 'cash'
        ? {'tendered': amount}
        : {
            'lines': [
              {'method': _method, 'amount': amount}
            ]
          };

    String message;
    try {
      final result = await app.api.post(
        '/branches/${app.branchId}/orders/${widget.orderId}/payments',
        body: body,
        idempotencyKey: newClientId(),
      );
      final change = result is Map ? result['change'] : null;
      message = change != null && toNum(change) > 0 ? 'Paid. Change ${fmtMoney(change)}' : 'Payment recorded.';
    } on ApiException catch (e) {
      if (!e.isNetwork) {
        if (mounted) {
          setState(() => _busy = false);
          snack(context, e.fullMessage, error: true);
        }
        return;
      }
      await app.queue(
        'payment',
        {
          'order_id': widget.orderId,
          'method': _method,
          'amount': amount,
          'tendered': amount,
        },
        label: 'Payment for order ${widget.orderId}',
      );
      message = 'Offline: payment saved and will sync.';
    }
    if (mounted) {
      Navigator.pop(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('Total ${fmtMoney(widget.total)}',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: context.fg, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final m in paymentMethods)
          ChoiceChip(label: Text(titleCase(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
      ]),
      const SizedBox(height: 16),
      field(_amount, _method == 'cash' ? 'Cash received' : 'Amount', type: const TextInputType.numberWithOptions(decimal: true)),
      FilledButton(onPressed: _busy ? null : _pay, child: Text(_busy ? 'Saving...' : 'Take payment')),
    ]);
  }
}
