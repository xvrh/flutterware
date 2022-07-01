import 'package:flutterware/src/test_runner/runtime/widget_tester.dart';
export 'package:flutterware/src/test_runner/runtime/widget_tester.dart'
    show AppWidgetTester, splitTest;
import 'package:flutter_test/flutter_test.dart' as flutter_test;
import 'package:meta/meta.dart';
export 'package:flutter_test/flutter_test.dart' hide testWidgets;
export 'runtime/app_test.dart' show AppTest, Screenshot;

@isTest
void testApp(
    String description, Future<void> Function(AppWidgetTester tester) body) {
  flutter_test.testWidgets(description, wrapTestBody(body));
}
