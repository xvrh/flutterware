import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Card(
        child: Markdown(
          controller: _scrollController,
          data: '''          
## App test

### Features
- Screenshot every step of the test
- Hot Reload to instantaneously see the result
- Preview all screens in all supported languages
- Switch to any screen size
- Enable all accessibility settings
- Split the test to explore all paths

### Steps
- Add a test file in a folder called `test_app` (ie. `test_app/checkout_test.dart`)
- Import `package:flutterware/flutter_test.dart` and use the API to write a test
- Call `screenshot()` method when you want to take a screenshot.

Example:
```dart
import 'package:flutterware/flutter_test.dart';

void main() {
  testApp('Checkout flow', CheckoutTest());
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
```
''',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
