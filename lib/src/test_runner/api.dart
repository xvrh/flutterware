import 'package:flutter_studio/src/test_runner/runtime/widget_tester.dart';
export 'package:flutter_studio/src/test_runner/runtime/widget_tester.dart'
    show AppWidgetTester, splitTest;
import 'package:flutter_test/flutter_test.dart' as flutter_test;
export 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:meta/meta.dart';
export 'runtime/app_test.dart' show AppTest;

@isTest
void testApp(
    String description, Future<void> Function(AppWidgetTester tester) body) {
  flutter_test.testWidgets(description, wrapTestBody(body));
}
