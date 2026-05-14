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
}
