import 'package:flutterware_app/src/run/launch.dart';
import 'package:test/test.dart';

List<String> _command({String? flavor, bool targetsWeb = false}) => runCommand(
  flutter: '/sdk/bin/flutter',
  device: targetsWeb ? 'chrome' : 'macos',
  target: '.dart_tool/flutterware/run/main_dev_guest.dart',
  flavor: flavor,
  targetsWeb: targetsWeb,
);

void main() {
  test('a flavor reaches the command line on a device that takes one', () {
    expect(_command(flavor: 'dev'), containsAllInOrder(['--flavor', 'dev']));
  });

  /// **Reported by a consumer whose every Chrome launch opened with the
  /// deprecation warning.** The flavor here is usually not something anyone
  /// typed — it is the pubspec's `flutter: default-flavor:`, resolved and
  /// promoted to an explicit flag. That field exists precisely because web
  /// takes no `--flavor`; it is how a web build gets `appFlavor` populated at
  /// all. Passing it back inverts what the field is for.
  test('no flavor reaches a web launch, however it was resolved', () {
    var command = _command(flavor: 'dev', targetsWeb: true);

    expect(command, isNot(contains('--flavor')));
    expect(command, isNot(contains('dev')));
  });

  /// The rest of the launch is untouched by the rule above — a web run still
  /// gets its target and its device, which is the whole point of not simply
  /// refusing the launch.
  test('a web launch keeps its target and device', () {
    expect(
      _command(flavor: 'dev', targetsWeb: true),
      containsAllInOrder([
        '/sdk/bin/flutter',
        'run',
        '--machine',
        '--device-id',
        'chrome',
        '--target',
        '.dart_tool/flutterware/run/main_dev_guest.dart',
      ]),
    );
  });

  test('defines follow the flavor, and survive without one', () {
    var command = runCommand(
      flutter: '/sdk/bin/flutter',
      device: 'chrome',
      target: 'lib/main.dart',
      flavor: 'dev',
      targetsWeb: true,
      defines: {'API': 'https://example.test'},
    );

    expect(
      command,
      containsAllInOrder(['--dart-define', 'API=https://example.test']),
    );
  });
}
