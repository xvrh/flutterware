import 'package:flutter/material.dart';
import 'package:flutter_studio/flutter_test.dart';
import 'package:flutter_studio_example/main.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;

// Start flutter_studio tool to run those tests:
// dart run flutter_studio app
void main() {
  setUp(() {
    print('Some code to configure the mocks');
  });

  testApp('On-boarding should do this and should to that', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.screenshot();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.screenshot();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.screenshot();
    await splitTest({
      'ok': () async {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.screenshot();
        //fail('This is a failure');
      },
      'not ok': () async {
        for (var i = 0; i < 10; i++) {
          await tester.tap(find.byIcon(Icons.add));
          await tester.pumpAndSettle();
          await tester.screenshot();
        }
      },
    });
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
