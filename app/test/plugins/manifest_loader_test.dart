import 'dart:io';

import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _config = 'void main() => print(0);';
const _manifest = '{"version":1,"plugins":[]}';

/// Counts compiles, and writes a stand-in kernel so [ManifestLoader] sees the
/// artifact it expects without a real compiler being present.
class _Runs {
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
    runs = _Runs();
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
