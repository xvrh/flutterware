import 'package:flutter_studio/src/test_runner/runtime/widget_tester.dart';
export 'package:flutter_studio/src/test_runner/runtime/widget_tester.dart'
    show WidgetTester;
import 'package:flutter_test/flutter_test.dart' as flutter_test;
export 'package:flutter_test/flutter_test.dart'
    show find, setUp, tearDown, setUpAll, tearDownAll, group;

void testWidgets(
    String description, Future<void> Function(WidgetTester tester) body) {
  flutter_test.testWidgets(description, (tester) {
    return body(WidgetTester.fromOriginal(tester));
  });
}
