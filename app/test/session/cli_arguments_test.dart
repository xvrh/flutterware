import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/session/cli.dart';

/// `fw run <plugin> <action> --flag=value`: how the flags become the action's
/// argument map.
void main() {
  const file = ActionParameter('file', 'File', repeatable: true);

  test('a repeatable flag given twice is both values, comma-joined', () {
    expect(
      FwCli.parseArguments(
        [
          'scenarios',
          'run',
          '--file=test/a_test.dart',
          '--file=test/b_test.dart',
        ],
        declared: const [file],
      ),
      {'file': 'test/a_test.dart,test/b_test.dart'},
    );
    expect(
      FwCli.parseArguments(
        ['run', '--file', 'a', '--file', 'b'],
        declared: const [file],
      ),
      {'file': 'a,b'},
    );
  });

  test('any other flag given twice is refused, not joined or last-wins', () {
    expect(
      () => FwCli.parseArguments(
        ['run', '--output=a', '--output=b'],
        declared: const [file],
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('--output given twice'), contains('"a"')),
        ),
      ),
    );
  });

  test('a flag given once is its value, and a bare one is true', () {
    expect(
      FwCli.parseArguments(
        ['run', '--file=a', '--json'],
        declared: const [
          ActionParameter('json', 'JSON', kind: ActionParameterKind.boolean),
        ],
      ),
      {'file': 'a', 'json': true},
    );
  });
}
