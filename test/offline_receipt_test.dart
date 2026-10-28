import 'package:dt_restora/core/local_db.dart';
import 'package:dt_restora/features/orders/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final order = <String, dynamic>{
    'invoice_no': 'BR01-T01-20261028-200424-GAME',
    'token_no': 'T01-007',
    'order_type': 'dine_in',
    'table': 'T5',
    'note': 'No onion',
    'subtotal': '560.00',
    'total': '676.00',
    'items': [
      {
        'name': 'Beef Tehari (Regular)',
        'quantity': 2,
        'unit_price': '280.00',
        'line_total': '560.00',
        'add_ons': [
          {'name': 'Egg', 'price': '30', 'qty': 1},
        ],
      },
    ],
    'payments': [
      {'method': 'cash', 'amount': '676.00', 'change_due': '24.00'},
    ],
  };

  test('kitchen token uses the device token, or the end of the invoice', () {
    expect(KitchenTokenData(order).token, 'T01-007');
    expect(KitchenTokenData({...order, 'token_no': null}).token, 'GAME');
  });

  test('kitchen ticket says where the order goes', () {
    expect(KitchenTokenData(order).where, 'Dine In  -  Table T5');
  });

  test('kitchen ticket and receipt render to PDF without a network', () async {
    expect((await KitchenTokenData(order).toPdf()).isNotEmpty, isTrue);
    expect((await ReceiptData(order, const {'name': 'Gulshan'}).toPdf()).isNotEmpty, isTrue);
  });

  test('receipt shows cash and change for a paid offline sale', () {
    final rows = ReceiptData(order, const {}).paymentRows();
    expect(rows.map((r) => r.left), containsAll(['Cash', 'Change']));
  });

  test('local orders round trip through the database row format', () {
    final local = LocalOrder(
      clientId: 'abc',
      kind: 'order',
      invoiceNo: 'INV-1',
      tokenNo: 'T01-001',
      order: order,
      createdAt: '2026-10-28T14:00:00Z',
    );
    final back = LocalOrder.fromRow(local.toRow());

    expect(back.invoiceNo, 'INV-1');
    expect(back.tokenNo, 'T01-001');
    expect(back.synced, isFalse);
    expect(back.order['total'], '676.00');
  });
}
