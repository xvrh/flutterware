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

  test('finds a project whose sdk entry is a directory, not a link', () {
    // Windows-style: the SDK was copied in rather than symlinked. Still a
    // recorded SDK; the bin decides from there whether it actually works.
    var project = Directory(p.join(root.path, 'copied'))..createSync();
    Directory(p.join(project.path, sdkLinkPath)).createSync(recursive: true);

    expect(findInitializedRoot(project)?.path, project.path);
  });

  test('the message names the rule, not just a command', () {
    // The after-clone case is every teammate, every time, because the
    // directory is machine-specific and therefore ignored. What they need to
    // understand is why `fw` alone cannot work yet.
    expect(noProjectMessage, contains('dart run flutterware'));
    expect(noProjectMessage, contains('your own Flutter SDK'));
  });

  test('the message states the dependency prerequisite', () {
    // Without it, a user in a project that never added flutterware follows
    // the advice and hits pub's "Could not find package" with no guidance.
    expect(noProjectMessage, contains('dart pub add flutterware'));
  });

  test('the broken-sdk message names the path as a path', () {
    var message = brokenSdkMessage('/Users/x/myapp');
    expect(message, contains('/Users/x/myapp/$sdkLinkPath'));
    // Interpolating the Directory itself once printed "Directory: '/path'".
    expect(message, isNot(contains("Directory: '")));
    expect(message, contains('dart run flutterware init'));
  });

  test('help without a project explains the redirect and the setup', () {
    expect(noProjectHelp, contains(sdkLinkPath));
    expect(noProjectHelp, contains('dart run flutterware'));
    expect(noProjectHelp, contains('dart pub add flutterware'));
  });

  test('the help spellings match what the CLI accepts', () {
    // Mirrors FwCli's dispatcher, which the walker cannot import; this pins
    // the copy so a drift shows up here instead of as a silent exit 64.
    expect(helpArguments, {'help', '--help', '-h'});
  });
}
