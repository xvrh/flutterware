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

  test('ANSI color codes are not stripped', () async {
    final pty = await spawnPty(
      '/bin/bash',
      ['-c', "printf '\\033[31mred\\033[0m\\n'"],
    );
    final bytes = <int>[];
    await pty.output.listen(bytes.addAll).asFuture<void>();
    // ESC [ 31 m  =  0x1b 0x5b 0x33 0x31 0x6d
    expect(bytes, containsAllInOrder([0x1b, 0x5b, 0x33, 0x31, 0x6d]));
  });

  test('cols/rows on spawn are respected by child', () async {
    final pty = await spawnPty(
      '/bin/bash',
      ['-c', 'stty size'],
      cols: 123,
      rows: 40,
    );
    final bytes = <int>[];
    await pty.output.listen(bytes.addAll).asFuture<void>();
    expect(utf8.decode(bytes), contains('123'));
  });

  test('resize() updates window size mid-run', () async {
    // Spawn a script that prints size on SIGWINCH then exits.
    final pty = await spawnPty(
      '/bin/bash',
      [
        '-c',
        'trap "stty size; exit 0" WINCH; sleep 5 & wait',
      ],
      cols: 80,
      rows: 24,
    );
    // Give bash a moment to install the trap.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    pty.resize(150, 50);

    final bytes = <int>[];
    await pty.output.listen(bytes.addAll).asFuture<void>();
    expect(utf8.decode(bytes), contains('150'));
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('writeInput forwards bytes to child stdin', () async {
    final pty = await spawnPty(
      '/bin/bash',
      ['-c', 'read x; echo got=\$x'],
    );
    // Give bash a moment to reach the `read` call.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    pty.writeInput(utf8.encode('hello\n'));

    final bytes = <int>[];
    await pty.output.listen(bytes.addAll).asFuture<void>();
    expect(utf8.decode(bytes), contains('got=hello'));
  });

  test('1000 lines from child are all received in order', () async {
    final pty = await spawnPty(
      '/bin/bash',
      ['-c', 'for i in \$(seq 1 1000); do echo line\$i; done'],
    );
    final bytes = <int>[];
    await pty.output.listen(bytes.addAll).asFuture<void>();
    final text = utf8.decode(bytes);
    for (final i in [1, 250, 500, 750, 1000]) {
      expect(text, contains('line$i'));
    }
    final pos1 = text.indexOf('line1\n');
    final pos1000 = text.indexOf('line1000');
    expect(pos1, lessThan(pos1000));
  });
}
