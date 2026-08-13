import 'dart:io';

import 'package:flutterware/src/constants.dart';
import 'package:flutterware/src/walker.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The global `fw` is frozen, so what it does is exactly what these tests
// pin: find a committed wrapper by its marker and exec it, or fall back to
// the recorded-SDK redirect untouched.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('fw-walker-test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File wrapper(String at, {String marker = '$wrapperMarker v1'}) {
    var file = File(p.join(tmp.path, at))..createSync(recursive: true);
    file.writeAsStringSync('#!/bin/sh\n$marker\necho "wrapper ran: $at \$@"\n');
    Process.runSync('chmod', ['+x', file.path]);
    return file;
  }

  /// A real `dart`, wherever this suite runs: under `dart test` it is the
  /// executable itself, under `flutter test` the executable is
  /// `flutter_tester` — which, spawned with a script, hangs to the timeout —
  /// and the SDK it belongs to is in `FLUTTER_ROOT`.
  String dartExecutable() {
    var exe = Platform.resolvedExecutable;
    if (p.basenameWithoutExtension(exe) == 'dart') return exe;
    var root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) fail('neither dart nor FLUTTER_ROOT to find one with');
    return p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', 'dart');
  }

  test('finds a marked wrapper walking up from a subdirectory', () {
    var script = wrapper('repo/fw');
    var inner = Directory(p.join(tmp.path, 'repo', 'app', 'lib'))
      ..createSync(recursive: true);
    expect(findWrapper(inner), script.path);
  });

  test('an fw without the marker is someone else, ancestors included', () {
    wrapper('repo/fw', marker: '# some other tool');
    var inner = Directory(p.join(tmp.path, 'repo', 'inner'))
      ..createSync(recursive: true);
    expect(findWrapper(inner), isNull);
  });

  test('the nearest marked wrapper wins over a farther one', () {
    wrapper('repo/fw');
    var nested = wrapper('repo/packages/one/fw');
    var inner = Directory(p.join(tmp.path, 'repo', 'packages', 'one', 'lib'))
      ..createSync(recursive: true);
    expect(findWrapper(inner), nested.path);
  });

  test('a directory named fw is not a wrapper', () {
    Directory(p.join(tmp.path, 'repo', 'fw')).createSync(recursive: true);
    expect(findWrapper(Directory(p.join(tmp.path, 'repo'))), isNull);
  });

  test(
    'the bin execs the wrapper it finds, forwarding the arguments',
    () async {
      wrapper('repo/fw');
      var inner = Directory(p.join(tmp.path, 'repo', 'sub'))..createSync();
      var result = await Process.run(dartExecutable(), [
        p.join(Directory.current.path, 'bin', 'walker.dart'),
        'status',
        '--json',
      ], workingDirectory: inner.path);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('wrapper ran: repo/fw status --json'));
    },
    testOn: '!windows',
  );

  test('without a wrapper the old redirect message still answers', () async {
    var result = await Process.run(dartExecutable(), [
      p.join(Directory.current.path, 'bin', 'walker.dart'),
      'status',
    ], workingDirectory: tmp.path);
    expect(result.exitCode, 64);
    expect(result.stderr, contains('no project set up'));
  });

  test('--version answers where a command would be refused', () async {
    // The diagnostic somebody reaches for to find out whether `fw` works at
    // all. Gating it on project setup withholds it exactly where it is asked.
    var result = await Process.run(dartExecutable(), [
      p.join(Directory.current.path, 'bin', 'walker.dart'),
      '--version',
    ], workingDirectory: tmp.path);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('fw $flutterwareVersion'));
    // And still teaches the setup, because that is the next thing wanted.
    expect(result.stdout, contains('dart run flutterware'));
  });

  test('the walker carries its own version across the exec', () async {
    // The far side prints two numbers, and this is the only process that
    // knows the first one.
    var file = File(p.join(tmp.path, 'repo', 'fw'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '#!/bin/sh\n$wrapperMarker v1\necho "walker=\$FW_WALKER_VERSION"\n',
      );
    Process.runSync('chmod', ['+x', file.path]);

    var result = await Process.run(dartExecutable(), [
      p.join(Directory.current.path, 'bin', 'walker.dart'),
      '--version',
    ], workingDirectory: p.join(tmp.path, 'repo'));
    expect(result.stdout, contains('walker=$flutterwareVersion'));
  }, testOn: '!windows');

  test('an ordinary command does not carry it', () async {
    var file = File(p.join(tmp.path, 'repo', 'fw'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '#!/bin/sh\n$wrapperMarker v1\necho "walker=[\$FW_WALKER_VERSION]"\n',
      );
    Process.runSync('chmod', ['+x', file.path]);

    var result = await Process.run(dartExecutable(), [
      p.join(Directory.current.path, 'bin', 'walker.dart'),
      'status',
    ], workingDirectory: p.join(tmp.path, 'repo'));
    expect(result.stdout, contains('walker=[]'));
  }, testOn: '!windows');
}
