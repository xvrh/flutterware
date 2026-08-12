import 'dart:io';

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
      var result = await Process.run(Platform.resolvedExecutable, [
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
    var result = await Process.run(Platform.resolvedExecutable, [
      p.join(Directory.current.path, 'bin', 'walker.dart'),
      'status',
    ], workingDirectory: tmp.path);
    expect(result.exitCode, 64);
    expect(result.stderr, contains('no project set up'));
  });
}
