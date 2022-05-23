import 'package:flutter_studio/test.dart';
import 'package:flutter_studio_example/main.dart';

// Start test_ui tool to run those tests:
// dart run test_ui
void main() {
  test('On-boarding', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.tap(find.text(''));
  });

  test('Login', (tester) async {
    //
  });
}
