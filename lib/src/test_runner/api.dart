import 'package:flutter_studio/src/test_runner/runtime/widget_tester.dart';
export 'package:flutter_studio/src/test_runner/runtime/widget_tester.dart'
    show WidgetTester, splitTest;
import 'package:flutter_test/flutter_test.dart' as flutter_test;
export 'package:flutter_test/flutter_test.dart'
    show find, setUp, tearDown, setUpAll, tearDownAll, group;

void testApp(
    String description, Future<void> Function(WidgetTester tester) body) {
  flutter_test.testWidgets(description, wrapTestBody(body));
}
