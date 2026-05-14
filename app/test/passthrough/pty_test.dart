import 'dart:convert';
import 'package:flutterware_app/src/passthrough/pty/pty.dart';
import 'package:test/test.dart';

void main() {
  test('tracer: echo hello captures output and exits 0', () async {
    final pty = await spawnPty('/bin/echo', ['hello']);
    final bytes = <int>[];
    await pty.output.listen(bytes.addAll).asFuture<void>();
    final code = await pty.exitCode;
    expect(utf8.decode(bytes), contains('hello'));
    expect(code, equals(0));
  });

  test('exit 42 propagates correctly', () async {
    final pty = await spawnPty('/bin/bash', ['-c', 'exit 42']);
    await pty.output.drain<void>();
    expect(await pty.exitCode, equals(42));
  });

  test('successful command returns exit 0', () async {
    final pty = await spawnPty('/bin/bash', ['-c', 'true']);
    await pty.output.drain<void>();
    expect(await pty.exitCode, equals(0));
  });

  test('nonexistent binary exits 127', () async {
    final pty = await spawnPty('/no/such/binary_xyz', []);
    await pty.output.drain<void>();
    expect(await pty.exitCode, equals(127));
  });

  test('SIGINT death gives exit 130', () async {
    final pty = await spawnPty('/bin/bash', ['-c', 'kill -INT \$\$; sleep 5']);
    await pty.output.drain<void>();
    expect(await pty.exitCode, equals(130));
  });

  test('workingDirectory: /tmp makes pwd report /tmp', () async {
    final pty = await spawnPty('/bin/bash', ['-c', 'pwd'], workingDirectory: '/tmp');
    final bytes = <int>[];
    await pty.output.listen(bytes.addAll).asFuture<void>();
    final out = utf8.decode(bytes);
    // macOS resolves /tmp to /private/tmp; both are acceptable.
    expect(out, anyOf(contains('/tmp'), contains('/private/tmp')));
    expect(await pty.exitCode, equals(0));
  });

  test('child sees stdout as a TTY', () async {
    final pty = await spawnPty(
      '/bin/bash',
      ['-c', '[ -t 1 ] && echo IS_TTY || echo NOT_TTY'],
    );
    final bytes = <int>[];
    await pty.output.listen(bytes.addAll).asFuture<void>();
    expect(utf8.decode(bytes), contains('IS_TTY'));
  });
}
