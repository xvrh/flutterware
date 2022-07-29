
# Flutterware

A collection of GUI tools for Flutter development.

![screenshot](doc/screenshots/test_visualizer.png)

## Quick start

Add `flutterware` package in your `pubspec.yaml`

`dart pub add flutterware`

```yaml
dependencies:
  flutterware:
```

Run the GUI app

```shell
# Run this in your Flutter project directory
dart run flutterware
```
The first launch is a bit slow because the desktop app need to be compiled.

<img src="doc/screenshots/shell.png" alt="Flutterware shell" width="600">

## Features

### Test visualizer

A new kind of testing built on top of the standard `flutter_test` framework.

- Screenshot every step of your test
- Hot-reload a test instantly (~1s) after any change
- Preview your app at any screen size and in all languages
- Easier to write tests that exercise the whole app
- Deploy the tests as a Web page for an internal documentation of the app.

Example code
```dart
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
```

Or using the high-level API
```dart
import 'package:flutterware/flutter_test.dart';

void main() {
  testWidgets('Checkout flow', CheckoutTest());
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

### Dependency manager

Overview of your dependencies to monitor the quality.

- See Pub & GitHub scores
- Run `pub upgrade` and preview all changelogs

### App's icon change

Quickly replace your app's launcher icon.

### More tools to come...

Any contribution is welcome.  
Open GitHub issues and pull requests with your ideas :-)