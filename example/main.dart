import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  testWidgets('Checkout flow', CheckoutTest().call);
}

class CheckoutTest extends AppTest {
  @override
  Future<void> run() async {
    await pumpWidget(MyApp());
    await screenshot(name: 'Home page');

    await tap(find.byIcon(Icons.shopping_cart));
    await screenshot(name: 'Cart');

    await enterText(TextField, '4334');
    await screenshot(name: 'Enter coupon code');

    await tap(translations.checkoutButton);
    await screenshot();
  }
}

// == App code (for example purpose)
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
