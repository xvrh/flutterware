import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_example/main.dart';

// Start flutterware tool to run those tests:
// dart run flutterware app
void main() {
  setUp(() {
    print('Some code to configure the mocks');
  });

  testApp('On-boarding should do this and should to that', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.screenshot('Start');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.screenshot();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.screenshot();
  });

  testApp('Login', (tester) async {
    print('Login test');

    expect(1, 0);
  });

  testApp('Dashboard', (tester) async {
    //
  });

  testApp('Products', (tester) async {
    //
  });

  group('Basket of all the products', () {
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
