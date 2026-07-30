import 'dart:io';

import 'package:flutterware/src/walker.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  Directory initialized(String path) {
    var dir = Directory(p.join(root.path, path))..createSync(recursive: true);
    var link = Link(p.join(dir.path, sdkLinkPath))
      ..parent.createSync(recursive: true);
    // The target need not exist: the walker's question is whether a project
    // recorded an SDK, and a dangling link is reported separately from an
    // absent one so the two get different messages.
    link.createSync('/nonexistent/sdk');
    return dir;
  }

  setUp(() => root = Directory.systemTemp.createTempSync('fw-walker'));
  tearDown(() => root.deleteSync(recursive: true));

  test('finds the project from a deep subdirectory', () {
    var project = initialized('repo');
    var deep = Directory(p.join(project.path, 'app', 'lib', 'src'))
      ..createSync(recursive: true);

    expect(findInitializedRoot(deep)?.path, project.path);
  });

  test('finds it when standing in the root itself', () {
    var project = initialized('repo');
    expect(findInitializedRoot(project)?.path, project.path);
  });

  test('returns null when no parent has been initialized', () {
    var stray = Directory(p.join(root.path, 'elsewhere'))..createSync();
    expect(findInitializedRoot(stray), isNull);
  });

  test('stops at the nearest project, not the outermost', () {
    // A flutterware repo inside another one — the inner project wins, the way
    // a nested checkout should.
    initialized('outer');
    var inner = initialized(p.join('outer', 'vendor', 'inner'));
    var deep = Directory(p.join(inner.path, 'lib'))..createSync();

    expect(findInitializedRoot(deep)?.path, inner.path);
  });

  test('the message names the rule, not just a command', () {
    // The after-clone case is every teammate, every time, because the
    // directory is machine-specific and therefore ignored. What they need to
    // understand is why `fw` alone cannot work yet.
    expect(noProjectMessage, contains('dart run flutterware'));
    expect(noProjectMessage, contains('your own Flutter SDK'));
  });
}
