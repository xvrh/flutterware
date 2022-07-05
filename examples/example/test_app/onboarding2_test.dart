import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_example/main.dart';

// Start flutterware tool to run those tests:
// dart run flutterware app
void main() {
  testApp('On-boarding', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.screenshot('Start');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.screenshot('Push 1');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.screenshot('Push 2');
  });

  testApp('Login', (tester) async {
    print('Login test');
  });

  testApp('Dashboard', (tester) async {
    //
  });

  testApp('Products', (tester) async {
    //
  });

  group('Basket', () {
    testApp('Empty', (tester) async {
      //
    });
    testApp('One product', (tester) async {
      //
    });
  });

  testApp('Logout', (tester) async {
    //
  });

  group('My group', () {
    testApp('More sub', (tester) async {
      print('bla');
    });
  });
}
