import 'package:dt_restora/features/orders/receipt.dart';
import 'package:dt_restora/features/pos/pos_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final item = <String, dynamic>{'id': 7, 'name': 'Beef Tehari', 'base_price': '280'};
  final regular = <String, dynamic>{'id': 11, 'name': 'Regular', 'price': '280'};
  Map<String, dynamic> egg(int qty) => {'id': 3, 'name': 'Egg', 'price': '30', 'qty': qty};

  test('an add-on quantity multiplies into the unit price and line total', () {
    final line = CartLine(item: item, variant: regular, quantity: 2, addOns: [egg(2)]);

    expect(line.addOnsPerUnit, 60);
    expect(line.unitPrice, 340);
    expect(line.total, 680);
  });

  test('an add-on without a quantity counts as one', () {
    final line = CartLine(item: item, variant: regular, addOns: [
      {'id': 3, 'name': 'Egg', 'price': '30'},
    ]);

    expect(line.unitPrice, 310);
    expect(line.addOnNames, 'Egg');
  });

  test('lines with different add-on quantities are separate lines', () {
    final one = CartLine(item: item, variant: regular, addOns: [egg(1)]);
    final two = CartLine(item: item, variant: regular, addOns: [egg(2)]);
    final alsoTwo = CartLine(item: item, variant: regular, quantity: 3, addOns: [egg(2)]);

    expect(one.key, isNot(two.key));
    expect(two.key, alsoTwo.key);
    expect(two.addOnNames, '2x Egg');
  });

  test('receipts show the add-on quantity and its total price', () {
    final receipt = ReceiptData(const {}, const {});

    expect(receipt.addOnLabel(egg(2)), '    + 2 x Egg');
    expect(receipt.addOnAmount(egg(2)), '60.00');
    expect(receipt.addOnLabel(egg(1)), '    + Egg');
  });
}
