import 'package:flutter_test/flutter_test.dart' as flutter_test;
import 'package:meta/meta.dart';
import 'runtime/setup_test_values.dart';

export 'package:flutter_test/flutter_test.dart' hide testWidgets;
export 'runtime/app_test.dart' show AppTest;
export 'runtime/widget_tester_assets.dart' show WidgetTesterAssetsExtension;
export 'runtime/widget_tester_screenshot.dart'
    show WidgetTesterScreenshotExtension;

@isTest
void testApp(String description,
    Future<void> Function(flutter_test.WidgetTester tester) body) {
  flutter_test.testWidgets(description, withTestValues(body));
}
