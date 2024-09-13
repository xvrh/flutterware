import 'package:flutter_test/flutter_test.dart' as flutter_test;
import 'package:meta/meta.dart';
import 'runtime/setup_test_values.dart';

export 'package:flutter_test/flutter_test.dart' hide testWidgets;
export 'runtime/app_test.dart' show AppTest, Screenshot;
export 'runtime/widget_tester_assets.dart' show WidgetTesterAssetsExtension;
export 'runtime/widget_tester_screenshot.dart'
    show WidgetTesterScreenshotExtension;

/// Runs the [callback] inside the Flutter test environment.
///
/// This function is the same as [flutter_test.testWidgets] with the addition
/// to apply the test values from the Flutterware GUI (selected locale, screen sizes,
/// accessibility settings etc...).
///
/// ## Sample code
///
/// ```dart
/// testApp('MyWidget', (tester) async {
///   await tester.pumpWidget(MyWidget());
///   await tester.screenshot();
///
///   await tester.tap(find.text('Save'));
///   expect(find.text('Success'), findsOneWidget);
///   await tester.screenshot(name: 'Success');
/// });
/// ```
@isTest
void testApp(String description,
    Future<void> Function(flutter_test.WidgetTester tester) body) {
  flutter_test.testWidgets(description, withTestValues(body));
}
