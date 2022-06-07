import 'package:flutter_studio/flutter_test.dart';
import 'package:flutter_studio_example/main.dart';

// Start flutter_studio tool to run those tests:
// dart run flutter_studio app
void main() {
  testWidgets('On-boarding', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.tap(find.text(''));
  });

  testWidgets('Login', (tester) async {
    //
  });

  group('My group', () {
    testWidgets('More', (tester) async {
      print('bla');
    });
  });
}
