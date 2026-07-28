import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/session/init.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory sdk;
  late StringBuffer out;
  late StringBuffer err;

  /// A directory `FlutterSdkPath` will accept: it needs both binaries present.
  Directory fakeSdk(String name) {
    var dir = Directory.systemTemp.createTempSync(name);
    for (var binary in ['flutter', 'dart']) {
      File(p.join(dir.path, 'bin', binary))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh');
    }
    return dir;
  }

  ProjectInit initWith({bool alreadyIgnored = false}) => ProjectInit(
    root: root.path,
    dartExecutable: p.join(sdk.path, 'bin', 'dart'),
    out: out,
    err: err,
    // `git check-ignore` exits 0 when the path is already covered.
    runProcess: (_, _, {workingDirectory}) async =>
        ProcessResult(0, alreadyIgnored ? 0 : 1, '', ''),
  );

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
    root = Directory.systemTemp.createTempSync('fw-init');
    sdk = fakeSdk('fw-init-sdk');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    sdk.deleteSync(recursive: true);
  });

  test('records the SDK that ran it', () async {
    expect(await initWith().run(), 0);

    var link = Link(p.join(root.path, '.flutterware', 'sdk'));
    expect(link.existsSync(), isTrue);
    expect(
      p.canonicalize(link.resolveSymbolicLinksSync()),
      p.canonicalize(sdk.resolveSymbolicLinksSync()),
    );
  });

  test('prefers .fvm/flutter_sdk when it names the same SDK', () async {
    // So that switching fvm versions moves this pointer too, instead of
    // leaving an absolute path naming the SDK that happened to be current.
    Link(p.join(root.path, '.fvm', 'flutter_sdk'))
      ..parent.createSync(recursive: true)
      ..createSync(sdk.path);

    await initWith().run();

    expect(
      Link(p.join(root.path, '.flutterware', 'sdk')).targetSync(),
      p.join('..', '.fvm', 'flutter_sdk'),
    );
  });

  test('records the SDK directly when fvm names a different one', () async {
    var other = fakeSdk('fw-init-other');
    addTearDown(() => other.deleteSync(recursive: true));
    Link(p.join(root.path, '.fvm', 'flutter_sdk'))
      ..parent.createSync(recursive: true)
      ..createSync(other.path);

    await initWith().run();

    expect(
      p.canonicalize(
        Link(
          p.join(root.path, '.flutterware', 'sdk'),
        ).resolveSymbolicLinksSync(),
      ),
      p.canonicalize(sdk.resolveSymbolicLinksSync()),
    );
  });

  test(
    'ignores the directory, since it holds a machine-specific path',
    () async {
      await initWith().run();

      expect(
        File(p.join(root.path, '.gitignore')).readAsStringSync(),
        contains('.flutterware/'),
      );
    },
  );

  test('leaves .gitignore alone when a pattern already covers it', () async {
    // A repo ignoring every dotfile with `.*` needs no line, and appending a
    // redundant one to a tracked file is worse than doing nothing.
    File(p.join(root.path, '.gitignore')).writeAsStringSync('.*\n');

    await initWith(alreadyIgnored: true).run();

    expect(File(p.join(root.path, '.gitignore')).readAsStringSync(), '.*\n');
  });

  test('writes a starter config when the project has none', () async {
    await initWith().run();

    var config = File(p.join(root.path, 'tool', 'flutterware.dart'));
    expect(config.existsSync(), isTrue);
    expect(config.readAsStringSync(), contains('Flutterware.configure'));
  });

  test('never overwrites an existing config', () async {
    File(p.join(root.path, 'tool', 'flutterware.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('// mine');

    await initWith().run();

    expect(
      File(p.join(root.path, 'tool', 'flutterware.dart')).readAsStringSync(),
      '// mine',
    );
  });

  test('is idempotent, and says nothing the second time', () async {
    await initWith().run();
    out.clear();

    expect(await initWith().run(), 0);
    expect(out.toString(), isNot(contains('.gitignore')));
    expect(out.toString(), isNot(contains('tool/flutterware.dart')));
    expect(Link(p.join(root.path, '.flutterware', 'sdk')).existsSync(), isTrue);
  });

  test('reports a dart that is not inside a Flutter SDK', () async {
    var init = ProjectInit(
      root: root.path,
      dartExecutable: '/usr/bin/dart',
      out: out,
      err: err,
      runProcess: (_, _, {workingDirectory}) async =>
          ProcessResult(0, 1, '', ''),
    );

    expect(await init.run(), 64);
    expect(err.toString(), contains('no Flutter SDK'));
    expect(init.isInitialized, isFalse);
  });

  test('isInitialized is what the walker will test for', () async {
    expect(initWith().isInitialized, isFalse);
    await initWith().run();
    expect(initWith().isInitialized, isTrue);
  });
}
