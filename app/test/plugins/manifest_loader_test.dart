import 'dart:io';

import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _config = 'void main() => print(0);';
const _manifest = '{"version":1,"plugins":[]}';

/// Counts compiles, and writes a stand-in kernel so [ManifestLoader] sees the
/// artifact it expects without a real compiler being present.
class _Runs {
  _Runs(this.depfileInputs);

  /// The sources the fake compiler claims to have read.
  List<String> depfileInputs;
  var compiles = 0;

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    if (arguments.firstOrNull == 'compile') {
      compiles++;
      var out = arguments[arguments.indexOf('-o') + 1];
      File(out)
        ..createSync(recursive: true)
        ..writeAsStringSync('kernel');
      // What the real compiler writes: everything the config reached. The
      // stamp is derived from this, so a test that omits it is testing a
      // cache that trusts nothing.
      var deps = arguments[arguments.indexOf('--depfile') + 1];
      File(deps)
        ..createSync(recursive: true)
        ..writeAsStringSync('$out: ${depfileInputs.join(' ')}\n');
      return ProcessResult(0, 0, '', '');
    }
    // Either `dart run tool/flutterware.dart` or `dart <kernel>` — both print
    // the manifest and nothing else.
    return ProcessResult(0, 0, _manifest, '');
  }
}

void main() {
  late Directory root;
  late File config;
  late File packageConfig;
  late _Runs runs;
  late ManifestLoader loader;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_manifest_loader');
    config = File(p.join(root.path, configFilePath))
      ..createSync(recursive: true)
      ..writeAsStringSync(_config);
    packageConfig = File(p.join(root.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"configVersion":2,"packages":[]}');
    runs = _Runs([config.path]);
    loader = ManifestLoader(dartExecutable: '/sdk/dart', runProcess: runs.call);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('compiles once, then reuses the kernel', () async {
    expect((await loader.load(root.path))!.plugins, isEmpty);
    expect(runs.compiles, 1);

    await loader.load(root.path);
    expect(runs.compiles, 1, reason: 'the second load must hit the cache');
  });

  test('a rewritten config with identical bytes does not recompile', () async {
    await loader.load(root.path);
    expect(runs.compiles, 1);

    // What a `git checkout` away and back leaves behind: same content, later
    // mtime. A stat-based key recompiled here.
    config.writeAsStringSync(_config);
    config.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));

    await loader.load(root.path);
    expect(runs.compiles, 1);
  });

  test(
    'a rewritten package_config with identical bytes does not recompile',
    () async {
      await loader.load(root.path);
      expect(runs.compiles, 1);

      // `pub get` rewrites this file whether or not resolution moved, and the
      // Dependencies plugin runs `pub get` itself — so this is the case that
      // used to make using flutterware invalidate flutterware's own cache.
      var contents = packageConfig.readAsStringSync();
      packageConfig.writeAsStringSync(contents);
      packageConfig.setLastModifiedSync(
        DateTime.now().add(const Duration(minutes: 5)),
      );

      await loader.load(root.path);
      expect(runs.compiles, 1);
    },
  );

  test('an edit to an imported file recompiles', () async {
    // `dart compile kernel` bundles the whole program, so a declaration can
    // move in a file the config imports without the config itself changing a
    // byte. Keying on the config alone served a stale kernel — and a stale
    // manifest reads as "no changes", which is the one wrong answer the reload
    // machinery cannot recover from.
    var imported = File(p.join(root.path, 'tool', 'plugins.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('const label = "One";');
    runs.depfileInputs = [config.path, imported.path];

    await loader.load(root.path);
    expect(runs.compiles, 1);

    await loader.load(root.path);
    expect(runs.compiles, 1, reason: 'nothing moved');

    imported.writeAsStringSync('const label = "Two";');
    await loader.load(root.path);
    expect(
      runs.compiles,
      2,
      reason: 'the closure moved, so the kernel is stale',
    );
  });

  test('a missing dependency list is not trusted', () async {
    await loader.load(root.path);
    expect(runs.compiles, 1);

    File(p.join(root.path, '.dart_tool', 'flutterware', 'manifest.deps'))
        .deleteSync();

    await loader.load(root.path);
    expect(
      runs.compiles,
      2,
      reason: 'unknown inputs means recompile, not reuse',
    );
  });

  test('changed config content recompiles', () async {
    await loader.load(root.path);
    config.writeAsStringSync('void main() => print(1);');

    await loader.load(root.path);
    expect(runs.compiles, 2);
  });

  test('changed package resolution recompiles', () async {
    await loader.load(root.path);
    packageConfig.writeAsStringSync(
      '{"configVersion":2,"packages":[],"flutterVersion":"3.48.0"}',
    );

    await loader.load(root.path);
    expect(runs.compiles, 2);
  });

  test('a different dart recompiles, even with both files untouched', () async {
    await loader.load(root.path);
    expect(runs.compiles, 1);

    // An fvm switch with no `pub get` after it: `flutterRoot` in
    // package_config.json still names the old SDK, so the executable is the
    // only thing that says otherwise.
    await ManifestLoader(
      dartExecutable: '/other-sdk/dart',
      runProcess: runs.call,
    ).load(root.path);
    expect(runs.compiles, 2);
  });
}
