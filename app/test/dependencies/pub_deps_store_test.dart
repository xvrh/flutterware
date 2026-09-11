import 'dart:io';

import 'package:flutterware_app/src/dependencies/model/pub_deps.dart';
import 'package:flutterware_app/src/dependencies/model/pub_deps_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The smallest thing `PubDeps.parse` accepts. What is in it does not matter
/// here — every test below is about *how many times* pub was asked and *where*,
/// which is the whole point of the store.
const _answer = '''
{"root":"host","packages":[
  {"name":"host","version":"1.0.0","kind":"root","source":"root",
   "dependencies":[],"directDependencies":[],"devDependencies":[],
   "dependencyConstraints":{}}
]}
''';

void main() {
  late Directory temporary;
  late String root;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('pub_deps_store');
    // Resolved, because on macOS the temp directory is reached through a
    // symlink and the store reports the root it walked to. Comparing an
    // unresolved path against a resolved one fails for a reason that has
    // nothing to do with what is being tested.
    root = temporary.resolveSymbolicLinksSync();
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  /// A resolved project at [at], relative to the temp root: a lockfile, and
  /// [members] beside it with nothing of their own — which is exactly the shape
  /// pub gives a workspace.
  String resolved(String at, {List<String> members = const []}) {
    var directory = p.join(root, at);
    Directory(directory).createSync(recursive: true);
    File(p.join(directory, 'pubspec.lock')).writeAsStringSync('packages:\n');
    for (var member in members) {
      Directory(p.join(directory, member)).createSync(recursive: true);
    }
    return directory;
  }

  /// A runner that records every spawn instead of performing one.
  ({List<String> directories, RunProcess run}) counting({
    int exitCode = 0,
    String stdout = _answer,
  }) {
    var directories = <String>[];
    return (
      directories: directories,
      run: (executable, arguments, {workingDirectory}) async {
        directories.add('$workingDirectory');
        return ProcessResult(0, exitCode, stdout, 'nope');
      },
    );
  }

  test('every member of a workspace shares one process', () async {
    var project = resolved('workspace', members: ['app', 'fixtures/probe_app']);
    var runner = counting();
    var store = PubDepsStore(runProcess: runner.run);

    // Together, the way `computeAll` asks: the whole point is that a wave of
    // members costs one process rather than one each.
    await Future.wait([
      for (var member in ['.', 'app', 'fixtures/probe_app'])
        store.load(
          flutterExecutable: '/sdk/flutter',
          directory: p.join(project, member),
        ),
    ]);

    expect(runner.directories, hasLength(1));
  });

  test('and it runs at the resolution root, not in a member', () async {
    var project = resolved('workspace', members: ['app']);
    var runner = counting();

    await PubDepsStore(runProcess: runner.run).load(
      flutterExecutable: '/sdk/flutter',
      directory: p.join(project, 'app'),
    );

    expect(runner.directories, [project]);
  });

  test('every member gets the same resolution back', () async {
    var project = resolved('workspace', members: ['app']);
    var store = PubDepsStore(runProcess: counting().run);

    var results = await Future.wait([
      store.load(flutterExecutable: '/sdk/flutter', directory: project),
      store.load(
        flutterExecutable: '/sdk/flutter',
        directory: p.join(project, 'app'),
      ),
    ]);

    // Identity, not equality: sharing the process is only worth anything if
    // both callers are handed the one answer it produced.
    expect(identical(results[0], results[1]), isTrue);
  });

  test('two resolutions are two processes', () async {
    var project = resolved('workspace', members: ['app']);
    // A nested project with its own lockfile is not part of the workspace
    // above it, and pub would answer about it separately. So does the store —
    // which is why the key is the lockfile it walked to rather than the
    // session root.
    var nested = resolved(p.join('workspace', 'tool', 'standalone'));
    var runner = counting();
    var store = PubDepsStore(runProcess: runner.run);

    await Future.wait([
      store.load(
        flutterExecutable: '/sdk/flutter',
        directory: p.join(project, 'app'),
      ),
      store.load(flutterExecutable: '/sdk/flutter', directory: nested),
    ]);

    expect(runner.directories, unorderedEquals([project, nested]));
  });

  test('two SDKs are two processes', () async {
    var project = resolved('workspace', members: ['app']);
    var runner = counting();
    var store = PubDepsStore(runProcess: runner.run);

    await Future.wait([
      store.load(flutterExecutable: '/sdk/one/flutter', directory: project),
      store.load(flutterExecutable: '/sdk/two/flutter', directory: project),
    ]);

    expect(runner.directories, hasLength(2));
  });

  test('an unresolved package is asked about on its own', () async {
    // No lockfile anywhere above, so there is no resolution to share and
    // nothing to key on. Pub gets asked in the package's own directory, which
    // is the directory its "run pub get" message then names.
    var lonely = p.join(root, 'lonely');
    Directory(lonely).createSync(recursive: true);
    var runner = counting(exitCode: 1, stdout: '');

    await expectLater(
      PubDepsStore(runProcess: runner.run)
          .load(flutterExecutable: '/sdk/flutter', directory: lonely),
      throwsA(
        isA<PubDepsFailure>().having((e) => e.directory, 'directory', lonely),
      ),
    );
    expect(runner.directories, [lonely]);
  });

  test('a failure is dropped, so the next call is a retry', () async {
    var project = resolved('workspace');
    var calls = 0;
    var store = PubDepsStore(
      runProcess: (executable, arguments, {workingDirectory}) async {
        calls++;
        return ProcessResult(0, calls == 1 ? 1 : 0, _answer, 'nope');
      },
    );

    // The trap this avoids is memoising the *future*: cache it and the first
    // failure is permanent, so a panel that failed once can never load again
    // however many times its reload button is pressed.
    await expectLater(
      store.load(flutterExecutable: '/sdk/flutter', directory: project),
      throwsA(isA<PubDepsFailure>()),
    );
    await store.load(flutterExecutable: '/sdk/flutter', directory: project);

    expect(calls, 2);
  });

  test('a completed wave is not reused, so a reload really reloads', () async {
    var project = resolved('workspace');
    var runner = counting();
    var store = PubDepsStore(runProcess: runner.run);

    await store.load(flutterExecutable: '/sdk/flutter', directory: project);
    await store.load(flutterExecutable: '/sdk/flutter', directory: project);

    // The in-memory half is a wave, not a memo. Staying alive past the wave
    // would make a `pub get` in another terminal invisible to an open studio;
    // the disk half is where a repeat gets to be cheap, and it can be, because
    // its key says what the answer depends on.
    expect(runner.directories, hasLength(2));
  });

  group('the disk stamp', () {
    late String project;
    late File lock;
    late File packageConfig;

    setUp(() {
      project = resolved('workspace');
      lock = File(p.join(project, 'pubspec.lock'));
      packageConfig = File(p.join(project, '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true);
      packageConfig.writeAsStringSync('{"configVersion":2,"packages":[]}');
    });

    test('is stable while nothing moves', () {
      expect(
        PubDepsStore.stampFor(project, '/sdk/flutter'),
        PubDepsStore.stampFor(project, '/sdk/flutter'),
      );
    });

    test('changes when the lockfile does', () {
      var before = PubDepsStore.stampFor(project, '/sdk/flutter');
      lock.writeAsStringSync('packages:\n  path: {}\n');
      expect(PubDepsStore.stampFor(project, '/sdk/flutter'), isNot(before));
    });

    test('changes when the package config does', () {
      // The second half of what `pub deps` reads. A `pub get` that resolves to
      // the same versions but relocates a path dependency rewrites this and
      // leaves the lockfile alone.
      var before = PubDepsStore.stampFor(project, '/sdk/flutter');
      packageConfig.writeAsStringSync('{"configVersion":2,"packages":[{}]}');
      expect(PubDepsStore.stampFor(project, '/sdk/flutter'), isNot(before));
    });

    test('changes when the SDK does', () {
      expect(
        PubDepsStore.stampFor(project, '/sdk/one/flutter'),
        isNot(PubDepsStore.stampFor(project, '/sdk/two/flutter')),
      );
    });

    test('is null when the resolution is not on disk to be hashed', () {
      packageConfig.deleteSync();
      // Null means *do not trust a cache*, not *the cache is fine* — the
      // difference between paying for pub and serving an answer about a
      // resolution that is no longer there.
      expect(PubDepsStore.stampFor(project, '/sdk/flutter'), isNull);
    });
  });

  test('an injected runner writes nothing to disk', () async {
    var project = resolved('workspace');
    File(p.join(project, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"configVersion":2,"packages":[]}');

    await PubDepsStore(runProcess: counting().run)
        .load(flutterExecutable: '/sdk/flutter', directory: project);

    // A store answering from a fixture must not leave that fixture where the
    // real `pub deps` answer is read back from — the widget tests inject one
    // while pointing at real directories inside this repo, and a test run may
    // not change what `fw status` says afterwards.
    var stamp = PubDepsStore.stampFor(project, '/sdk/flutter')!;
    expect(PubDepsStore.cacheFileFor(project, stamp).existsSync(), isFalse);
  });
}
