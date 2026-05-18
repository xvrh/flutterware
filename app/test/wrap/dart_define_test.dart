import 'package:flutterware_app/src/wrap/dart_define.dart';
import 'package:test/test.dart';

void main() {
  test('inserts the define immediately after the subcommand token', () {
    final out = injectDartDefine(
      ['--no-color', 'run', '--machine', 'lib/main.dart'],
      key: 'FW_MARKER',
      value: 'tok123',
    );
    expect(out, [
      '--no-color',
      'run',
      '--dart-define=FW_MARKER=tok123',
      '--machine',
      'lib/main.dart',
    ]);
  });

  test('appends the define when there is no non-flag token', () {
    final out = injectDartDefine(['--version'], key: 'FW_MARKER', value: 't');
    expect(out, ['--version', '--dart-define=FW_MARKER=t']);
  });

  test('handles a bare subcommand with no flags', () {
    final out = injectDartDefine(['test'], key: 'K', value: 'v');
    expect(out, ['test', '--dart-define=K=v']);
  });
}
