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

  testApp('With auto screenshot', _OnboardingTest());
  testApp('Without auto screenshot', _OnboardingNotAutoTest());
}

class _OnboardingTest extends AppTest {
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
    await tap(find.byIcon(Icons.add), screenshot: Screenshot.none);
    await tap(find.byIcon(Icons.add),
        screenshot: Screenshot(name: 'Custom name'));
    await splitTest({
      'ok': () async {
        await tap(find.byIcon(Icons.add));
      },
      'not ok': () async {
        for (var i = 0; i < 10; i++) {
          await tap(find.byIcon(Icons.add));
        }
      },
    });
  }
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
    autoScreenshot = false;
    await pumpWidget(MyApp());
    await screenshot();
    await tap(find.byIcon(Icons.add));
    await screenshot();
    await tap(find.byIcon(Icons.add));
    await screenshot();
    await splitTest({
      'ok': () async {
        await tap(find.byIcon(Icons.add));
        await screenshot();
      },
      'not ok': () async {
        for (var i = 0; i < 10; i++) {
          await tap(find.byIcon(Icons.add));
          await screenshot();
        }
      },
    });
  }
}
