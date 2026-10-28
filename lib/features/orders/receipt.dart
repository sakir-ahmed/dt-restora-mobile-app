import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/local_db.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../pos/pos_screen.dart';

/// One printed row: a plain text line, or a label and value pair.
class ReceiptRow {
  const ReceiptRow(
    this.left, [
    this.right,
    this.bold = false,
    this.rule = false,
  ]);

  final String left;
  final String? right;
  final bool bold;
  final bool rule;
}

String _money(Object? v) => toNum(v).toStringAsFixed(2);

/// Everything printed on the receipt, in the order from the design spec:
/// business, branch, invoice, date, table and cashier, items, totals,
/// payments, change and the footer message.
class ReceiptData {
  ReceiptData(this.order, this.branch);

  final Map<String, dynamic> order;
  final Map<String, dynamic> branch;

  String get invoice => '${order['invoice_no']}';

  List<ReceiptRow> headerRows() => [
    ReceiptRow('Invoice', invoice, true),
    if (order['created_at'] != null)
      ReceiptRow('Date', fmtDate(order['created_at'])),
    ReceiptRow('Type', titleCase('${order['order_type']}')),
    if (order['table'] != null) ReceiptRow('Table', '${order['table']}'),
    if (order['cashier'] != null)
      ReceiptRow('Served by', '${order['cashier']}'),
  ];

  List<Map<String, dynamic>> get items => asRows(order['items']);

  List<ReceiptRow> totalRows() {
    final subtotal =
        order['subtotal'] ??
        items.fold<double>(0, (sum, i) => sum + toNum(i['line_total']));
    final out = <ReceiptRow>[ReceiptRow('Subtotal', _money(subtotal))];
    if (toNum(order['discount_amount']) > 0) {
      out.add(ReceiptRow('Discount', '-${_money(order['discount_amount'])}'));
    }
    if (toNum(order['service_charge']) > 0) {
      out.add(ReceiptRow('Service charge', _money(order['service_charge'])));
    }
    if (toNum(order['vat_amount']) > 0) {
      out.add(ReceiptRow('VAT', _money(order['vat_amount'])));
    }
    if (toNum(order['delivery_fee']) > 0) {
      out.add(ReceiptRow('Delivery fee', _money(order['delivery_fee'])));
    }
    if (toNum(order['rounding']) != 0) {
      out.add(ReceiptRow('Rounding', _money(order['rounding'])));
    }
    out.add(ReceiptRow('TOTAL', 'BDT ${_money(order['total'])}', true, true));
    return out;
  }

  List<ReceiptRow> paymentRows() {
    final out = <ReceiptRow>[];
    for (final p in asRows(order['payments'])) {
      out.add(ReceiptRow(titleCase('${p['method']}'), _money(p['amount'])));
      if (toNum(p['change_due']) > 0) {
        out.add(ReceiptRow('Change', _money(p['change_due'])));
      }
    }
    if (out.isEmpty) {
      out.add(const ReceiptRow('Payment', 'Not paid yet'));
    }
    return out;
  }

  String get footer =>
      (branch['receipt_footer'] as String?)?.trim().isNotEmpty == true
      ? branch['receipt_footer'] as String
      : 'Thank you. Please come again.';

  Future<Uint8List> toPdf() async {
    final doc = pw.Document();
    pw.Widget pair(ReceiptRow r) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            r.left,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: r.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          if (r.right != null)
            pw.Text(
              r.right!,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: r.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
        ],
      ),
    );
    final line = pw.Divider(thickness: 0.5, height: 8);

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 5 * PdfPageFormat.mm,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'DT Restora',
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                '${branch['name'] ?? ''}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            if (branch['address'] != null)
              pw.Center(
                child: pw.Text(
                  '${branch['address']}',
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            if (branch['phone'] != null)
              pw.Center(
                child: pw.Text(
                  'Phone ${branch['phone']}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            line,
            for (final r in headerRows()) pair(r),
            line,
            for (final i in items) ...[
              pw.Text('${i['name']}', style: const pw.TextStyle(fontSize: 9)),
              pair(
                ReceiptRow(
                  '  ${i['quantity']} x ${_money(i['unit_price'] ?? toNum(i['line_total']) / (toNum(i['quantity']) == 0 ? 1 : toNum(i['quantity'])))}',
                  _money(i['line_total']),
                ),
              ),
              for (final a in asRows(i['add_ons']))
                pair(ReceiptRow('    + ${a['name']}', _money(a['price']))),
            ],
            line,
            for (final r in totalRows()) pair(r),
            line,
            for (final r in paymentRows()) pair(r),
            line,
            pw.Center(
              child: pw.Text(
                footer,
                style: const pw.TextStyle(fontSize: 8),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}

/// The kitchen ticket: a big token number, what to cook and any note. Built
/// from the order alone, so it prints with no network.
class KitchenTokenData {
  KitchenTokenData(this.order);

  final Map<String, dynamic> order;

  String get invoice => '${order['invoice_no']}';

  /// The device token when there is one, otherwise the short end of the
  /// invoice number so the kitchen still has something easy to call out.
  String get token {
    final t = order['token_no'];
    if (t != null && '$t'.isNotEmpty) {
      return '$t';
    }
    final parts = invoice.split('-');
    return parts.length > 1 ? parts.last : invoice;
  }

  String get where =>
      '${titleCase('${order['order_type']}')}'
      '${order['table'] == null ? '' : '  -  Table ${order['table']}'}';

  List<Map<String, dynamic>> get items => asRows(order['items']);

  Future<Uint8List> toPdf() async {
    final doc = pw.Document();
    final line = pw.Divider(
      thickness: 1,
      height: 10,
      borderStyle: pw.BorderStyle.dashed,
    );
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          58 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 3 * PdfPageFormat.mm,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'KITCHEN TOKEN',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                token,
                style: pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(invoice, style: const pw.TextStyle(fontSize: 7)),
            ),
            if (order['created_at'] != null)
              pw.Center(
                child: pw.Text(
                  fmtDate(order['created_at']),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            line,
            pw.Text(
              where,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            line,
            for (final i in items) ...[
              pw.Text(
                '${i['quantity']} x ${i['name']}',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              for (final a in asRows(i['add_ons']))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8),
                  child: pw.Text(
                    '+ ${a['qty'] ?? 1} x ${a['name']}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
            ],
            if ((order['note'] ?? '').toString().isNotEmpty) ...[
              line,
              pw.Text(
                '${order['note']}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
            line,
          ],
        ),
      ),
    );
    return doc.save();
  }
}

const _receiptFormat = PdfPageFormat(
  80 * PdfPageFormat.mm,
  double.infinity,
  marginAll: 5 * PdfPageFormat.mm,
);
const _tokenFormat = PdfPageFormat(
  58 * PdfPageFormat.mm,
  double.infinity,
  marginAll: 3 * PdfPageFormat.mm,
);

/// Receipt preview with print, PDF share, kitchen token and edit.
///
/// Give it an [orderId] to load the order from the server (or the device
/// cache), or a [localClientId] to show an order made on this device. The
/// local one needs no network at all, so it opens, prints and edits offline.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, this.orderId, this.localClientId, this.order})
    : assert(orderId != null || localClientId != null || order != null);

  final int? orderId;
  final String? localClientId;

  /// An order already in hand, such as one opened from the Orders list. It
  /// shows at once from this copy, so it works with no network.
  final Map<String, dynamic>? order;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final branch = Map<String, dynamic>.from(
      (app.bootstrap?['branch'] as Map?) ?? {},
    );
    final given = order;
    if (given != null) {
      final status = '${given['status']}';
      final editable = status != 'paid' && status != 'void' && app.can('orders.create') && given['id'] != null;
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt')),
        body: _ReceiptBody(
          order: given,
          branch: branch,
          edit: editable ? EditTarget.server(given, orderId: (given['id'] as num).toInt()) : null,
        ),
      );
    }
    if (localClientId != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt')),
        body: FutureBuilder<LocalOrder?>(
          future: app.db.localOrder(localClientId!),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final local = snap.data;
            if (local == null) {
              return const EmptyState('This order is no longer on the device.');
            }
            final order = {
              ...local.order,
              'invoice_no': local.invoiceNo,
              'token_no': local.tokenNo,
            };
            return _ReceiptBody(
              order: order,
              branch: branch,
              note: local.synced ? null : 'Saved on this device. It will sync when the network is back.',
              edit: local.synced
                  ? EditTarget.server(
                      order,
                      orderId: local.serverId,
                      orderClientId: local.kind == 'order'
                          ? local.clientId
                          : null,
                    )
                  : EditTarget.local(local),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: DataView<Map<String, dynamic>>(
        path: '/branches/${app.branchId}/orders/$orderId',
        transform: (raw) => Map<String, dynamic>.from(raw as Map),
        builder: (context, order, raw, reload) {
          final status = '${order['status']}';
          final editable =
              status != 'paid' && status != 'void' && app.can('orders.create');
          return _ReceiptBody(
            order: order,
            branch: branch,
            edit: editable
                ? EditTarget.server(
                    order,
                    orderId: (order['id'] as num).toInt(),
                  )
                : null,
          );
        },
      ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({
    required this.order,
    required this.branch,
    this.note,
    this.edit,
  });

  final Map<String, dynamic> order;
  final Map<String, dynamic> branch;
  final String? note;
  final EditTarget? edit;

  @override
  Widget build(BuildContext context) {
    final data = ReceiptData(order, branch);
    final kitchen = KitchenTokenData(order);

    Future<void> printPdf(
      Future<Uint8List> Function() build,
      PdfPageFormat format,
      String name,
    ) async {
      final ok = await guarded(context, () async {
        await Printing.layoutPdf(
          name: name,
          format: format,
          onLayout: (_) => build(),
        );
      });
      if (!ok && context.mounted) {
        snack(context, 'Could not open the print dialog.', error: true);
      }
    }

    return Column(
      children: [
        if (note != null)
          Container(
            width: double.infinity,
            color: Brand.warning.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.cloud_off, size: 16, color: Brand.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(note!, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [Center(child: _Paper(data: data))],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            printPdf(data.toPdf, _receiptFormat, data.invoice),
                        icon: const Icon(Icons.print),
                        label: const Text('Print receipt'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => printPdf(
                          kitchen.toPdf,
                          _tokenFormat,
                          'Token ${kitchen.token}',
                        ),
                        icon: const Icon(Icons.soup_kitchen_outlined),
                        label: Text(
                          'Token ${kitchen.token.length > 8 ? '' : kitchen.token}'
                              .trim(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async => Printing.sharePdf(
                          bytes: await data.toPdf(),
                          filename: '${data.invoice}.pdf',
                        ),
                        icon: const Icon(Icons.share),
                        label: const Text('Share PDF'),
                      ),
                    ),
                    if (edit != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PosScreen(edit: edit),
                            ),
                          ),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit order'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The on-screen "paper": always white with dark text, like the printout.
class _Paper extends StatelessWidget {
  const _Paper({required this.data});

  final ReceiptData data;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111827);
    const faint = Color(0xFF6B7280);
    final mono = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: ink,
      height: 1.35,
    );

    Widget pair(ReceiptRow r) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              r.left,
              style: mono.copyWith(fontWeight: r.bold ? FontWeight.w800 : null),
            ),
          ),
          if (r.right != null)
            Text(
              r.right!,
              style: mono.copyWith(fontWeight: r.bold ? FontWeight.w800 : null),
            ),
        ],
      ),
    );
    final rule = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '-' * 44,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: mono.copyWith(color: faint),
      ),
    );
    final b = data.branch;

    return Container(
      width: 340,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              'DT Restora',
              style: mono.copyWith(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          Center(child: Text('${b['name'] ?? ''}', style: mono)),
          if (b['address'] != null)
            Center(
              child: Text(
                '${b['address']}',
                textAlign: TextAlign.center,
                style: mono.copyWith(fontSize: 11, color: faint),
              ),
            ),
          if (b['phone'] != null)
            Center(
              child: Text(
                'Phone ${b['phone']}',
                style: mono.copyWith(fontSize: 11, color: faint),
              ),
            ),
          rule,
          for (final r in data.headerRows()) pair(r),
          rule,
          for (final i in data.items) ...[
            Text('${i['name']}', style: mono),
            pair(
              ReceiptRow(
                '  ${i['quantity']} x ${_money(i['unit_price'] ?? toNum(i['line_total']) / (toNum(i['quantity']) == 0 ? 1 : toNum(i['quantity'])))}',
                _money(i['line_total']),
              ),
            ),
            for (final a in asRows(i['add_ons']))
              pair(ReceiptRow('    + ${a['name']}', _money(a['price']))),
          ],
          rule,
          for (final r in data.totalRows()) pair(r),
          rule,
          for (final r in data.paymentRows()) pair(r),
          rule,
          Center(
            child: Text(
              data.footer,
              textAlign: TextAlign.center,
              style: mono.copyWith(fontSize: 11, color: faint),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Powered by Datatech BD',
              style: mono.copyWith(fontSize: 10, color: Brand.primary),
            ),
          ),
        ],
      ),
    );
  }
}
