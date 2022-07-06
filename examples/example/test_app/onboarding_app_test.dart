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

  testApp('Without auto screenshot', _OnboardingNotAutoTest());
}

class _OnboardingNotAutoTest extends AppTest {
  @override
  Future<void> setUp() async {
    // Setup mocks. This can be run several times per run.
  }

  @override
  Future<void> tearDown() async {
    // Tear down mock
  }

  @override
  Future<void> run() async {
    await pumpWidget(MyApp());
    await screenshot(name: 'App');
    await tap(find.byIcon(Icons.add));
    await screenshot(name: 'Tap icon');
    await tap(find.byIcon(Icons.add));
    await screenshot(name: 'Tap icon 2');
    await splitTest({
      'ok': () async {
        await tap(find.byIcon(Icons.add));
        await screenshot(name: 'Tap icon 3');
      },
      'not ok': () async {
        for (var i = 0; i < 10; i++) {
          await tap(find.byIcon(Icons.add));
          await screenshot(name: 'Tap icon $i');
        }
      },
    });
  }
}
