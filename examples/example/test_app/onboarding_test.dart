import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_example/main.dart';

// Start flutterware tool to run those tests:
// dart run flutterware app
void main() {
  setUp(() {
    // Configure your mocks here
  });

  testApp('On-boarding should do this and should to that', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.screenshot(name: 'Start');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.screenshot(name: 'Tap icon');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.screenshot(name: 'Tap icon');
  });
}
