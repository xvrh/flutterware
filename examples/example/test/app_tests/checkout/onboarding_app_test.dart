import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_example/main.dart';

// Start flutterware tool to run those tests:
// dart run flutterware app
void main() {
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
    await pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Container(
            color: Colors.blue,
            child: Center(
              child: Icon(
                Icons.ac_unit,
                size: 300,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
    await screenshot(name: 'Splash');
    await pumpWidget(
      AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Container(color: Colors.blue),
      ),
    );
    await screenshot(name: 'Splash 2');
    await pumpWidget(MyApp());
    await screenshot(name: 'App');
    await tap(find.byIcon(Icons.add));
    await screenshot(name: 'Tap icon');
    await tap(find.byIcon(Icons.add));
    await screenshot(name: 'Tap icon 2');
    await enterText(TextField, 'My password');
    await screenshot(name: 'Enter text');
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
