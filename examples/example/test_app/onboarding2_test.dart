import 'package:flutter/material.dart';
import 'package:flutter_studio/flutter_test.dart';
import 'package:flutter_studio_example/main.dart';

// Start flutter_studio tool to run those tests:
// dart run flutter_studio app
void main() {
  testWidgets('On-boarding', (tester) async {
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
      },
      'not ok': () async {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.screenshot();
      },
    });
  });

  testWidgets('Login', (tester) async {
    print('Login test');
  });

  testWidgets('Dashboard', (tester) async {
    //
  });

  testWidgets('Products', (tester) async {
    //
  });

  group('Basket', () {
    testWidgets('Empty', (tester) async {
      //
    });
    testWidgets('One product', (tester) async {
      //
    });
  });

  testWidgets('Logout', (tester) async {
    //
  });

  group('My group', () {
    testWidgets('More sub', (tester) async {
      print('bla');
    });
  });
}
