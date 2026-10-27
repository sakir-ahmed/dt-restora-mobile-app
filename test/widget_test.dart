import 'package:dt_restora/core/app_state.dart';
import 'package:dt_restora/ui/generic_view.dart';
import 'package:dt_restora/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats money and parses decimal strings', () {
    expect(fmtMoney('1250.5'), 'BDT 1,250.50');
    expect(toNum('12.30'), 12.3);
    expect(toNum(null), 0);
  });

  test('client ids are unique and fit the sync limit', () {
    final ids = {for (var i = 0; i < 200; i++) newClientId()};
    expect(ids.length, 200);
    expect(ids.every((id) => id.length <= 40), isTrue);
  });

  test('every demo account has the seeded username', () {
    expect(demoAccounts.map((a) => a.username), containsAll(['owner', 'cashier', 'kitchen', 'accountant', 'rider']));
  });

  testWidgets('generic view renders report rows with money formatting', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GenericView([
          {'date': '2026-10-01', 'orders': 3, 'net': '1200.00'},
        ]),
      ),
    ));

    expect(find.text('BDT 1,200.00'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
  });
}
