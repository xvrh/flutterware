import 'dart:io';

import 'package:flutterware_app/src/passthrough/passthrough_command.dart';
import 'package:test/test.dart';

/// Locate the `dart` executable.
///
/// `Platform.resolvedExecutable` would normally point at `dart`, but under
/// `flutter test` it points at `flutter_tester` (which can't run scripts the
/// same way). So we resolve `dart` from PATH at test time.
String _resolveDart() {
  if (Platform.resolvedExecutable.endsWith('/dart')) {
    return Platform.resolvedExecutable;
  }
  final r = Process.runSync('/usr/bin/which', ['dart']);
  if (r.exitCode == 0) {
    final path = (r.stdout as String).trim();
    if (path.isNotEmpty) return path;
  }
  throw StateError('Could not locate dart executable');
}

void main() {
  final dart = _resolveDart();

  test('runUnderPty returns 127 for nonexistent executable without throwing',
      () async {
    final code = await runUnderPty(
      executable: '/no/such/binary_xyz_for_test',
      arguments: const [],
      printSummary: false,
    );
    expect(code, equals(127));
  });

  test('runUnderPty returns 0 for /usr/bin/true', () async {
    final code = await runUnderPty(
      executable: '/usr/bin/true',
      arguments: const [],
      printSummary: false,
    );
    expect(code, equals(0));
  });

  test('CLI: echo hello via bin/passthrough.dart', () async {
    final result = await Process.run(
      dart,
      [
        'run',
        'bin/passthrough.dart',
        'run',
        '--no-print-capture-summary',
        '--',
        '/bin/echo',
        'integration-ok',
      ],
    );
    expect(result.exitCode, equals(0));
    expect(result.stdout.toString(), contains('integration-ok'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('CLI: missing -- separator yields usage error 64', () async {
    final result = await Process.run(
      dart,
      ['run', 'bin/passthrough.dart', 'run'],
    );
    expect(result.exitCode, equals(64));
    expect(result.stderr.toString(), contains('Usage:'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('CLI: exit-code passthrough for `bash -c "exit 42"`', () async {
    final result = await Process.run(
      dart,
      [
        'run',
        'bin/passthrough.dart',
        'run',
        '--no-print-capture-summary',
        '--',
        '/bin/bash',
        '-c',
        'exit 42',
      ],
    );
    expect(result.exitCode, equals(42));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
