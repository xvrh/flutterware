import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  testWidgets('Checkout flow', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.screenshot(name: 'Home page');

    await tester.tap(find.byIcon(Icons.shopping_cart));
    await tester.screenshot(name: 'Cart');

    await tester.enterText(find.byType(TextField), '4334');
    await tester.screenshot(name: 'Enter coupon code');

    await tester.tap(find.text(translations.checkoutButton));
    await tester.screenshot();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

final translations = Translations();

class Translations {
  String get checkoutButton => '';
}
