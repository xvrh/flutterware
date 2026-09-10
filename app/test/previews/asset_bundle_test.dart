import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/previews/asset_bundle.dart';
import 'package:flutterware_app/src/previews/asset_transformer.dart';
import 'package:flutterware_app/src/previews/project_shaders.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:hooks_runner/hooks_runner.dart'
    show KernelAsset, KernelAssetAbsolutePath, Target;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/dart_executable.dart';

/// The in-place contract: a rebuild updates the directory the engine holds a
/// file descriptor to, and never replaces it. Each test is one clause of that
/// contract; the live-guest consequence — a replaced directory bricks every
/// asset load — is in `integration_test/asset_refresh_test.dart` and the
/// 2026-07-30 mid-session spec.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_bundle_test'));
  tearDown(() => root.deleteSync(recursive: true));

  String projectRoot() => p.join(root.path, 'project');
  String output() => p.join(root.path, 'bundle');

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  AssetBundleBuilder builder({List<KernelAsset>? nativeAssets}) =>
      AssetBundleBuilder(
        // A cache directory that holds nothing: every SDK payload link is
        // skipped, which keeps these tests about the project's own assets.
        cache: FlutterCache(p.join(root.path, 'cache')),
        rootPackageRoot: projectRoot(),
        packageConfigPath: p.join(
          projectRoot(),
          '.dart_tool',
          'package_config.json',
        ),
        nativeAssetsForTesting: nativeAssets,
      );

  setUp(() {
    write('project/.dart_tool/package_config.json', '''
{"configVersion": 2, "packages": []}
''');
    write('project/pubspec.yaml', '''
name: project
flutter:
  assets:
    - assets/images/
''');
    write('project/assets/images/logo.png', 'logo');
  });

  test('a rebuild keeps the directory and reports no change', () async {
    var first = await builder().build(output());
    expect(first.changed, isTrue, reason: 'The first build made everything.');

    // What the engine actually holds is a file descriptor; what a test can
    // hold is a file *in* the directory that a delete-and-recreate would
    // destroy. The daemon's kernel is exactly such a file.
    var kernel = File(p.join(output(), 'kernel_blob.bin'))
      ..writeAsStringSync('the kernel');

    var second = await builder().build(output());
    expect(second.changed, isFalse);
    expect(second.fontsChanged, isFalse);
    expect(kernel.readAsStringSync(), 'the kernel');
  });

  test('an added asset appears, as a change', () async {
    await builder().build(output());
    write('project/assets/images/added.png', 'added');

    var sync = await builder().build(output());

    expect(sync.changed, isTrue);
    expect(sync.fontsChanged, isFalse);
    expect(
      Link(p.join(output(), 'assets', 'images', 'added.png')).targetSync(),
      p.join(projectRoot(), 'assets', 'images', 'added.png'),
    );
  });

  test('a removed asset is pruned, manifest included', () async {
    write('project/assets/images/doomed.png', 'doomed');
    await builder().build(output());
    var link = Link(p.join(output(), 'assets', 'images', 'doomed.png'));
    expect(link.existsSync(), isTrue);

    File(p.join(projectRoot(), 'assets', 'images', 'doomed.png')).deleteSync();
    var sync = await builder().build(output());

    expect(sync.changed, isTrue);
    // existsSync resolves the target; what must be gone is the link itself.
    expect(FileSystemEntity.isLinkSync(link.path), isFalse);
  });

  test('a font change is called out as one', () async {
    await builder().build(output());
    write('project/assets/fonts/Brand.ttf', 'ttf');
    write('project/pubspec.yaml', '''
name: project
flutter:
  assets:
    - assets/images/
  fonts:
    - family: Brand
      fonts:
        - asset: assets/fonts/Brand.ttf
''');

    var sync = await builder().build(output());

    expect(sync.changed, isTrue);
    expect(sync.fontsChanged, isTrue);

    // And only a font change: the same pubspec again is quiet.
    var again = await builder().build(output());
    expect(again.changed, isFalse);
  });

  test('editing an asset file is not a bundle change', () async {
    await builder().build(output());
    write('project/assets/images/logo.png', 'repainted');

    var sync = await builder().build(output());

    expect(
      sync.changed,
      isFalse,
      reason:
          'The bundle entry is a symlink to the file, so the edit is already '
          'in the bundle. This is what makes edits need no rebundle at all.',
    );
  });

  group('a declared transformer', () {
    /// A cache whose `dart` is the SDK's, so `dart run` in the builder is a
    /// real spawn. Everything else in this cache is still absent, which is what
    /// keeps the SDK payload links out of these tests.
    AssetBundleBuilder builderWithDart() {
      var dart = p.join(root.path, 'cache', 'dart-sdk', 'bin', 'dart');
      if (!File(dart).existsSync()) {
        Directory(p.dirname(dart)).createSync(recursive: true);
        Link(dart).createSync(resolveDartExecutable());
      }
      return builder();
    }

    /// Resolves the fixture so `dart run <package>` finds the transformer.
    Future<void> resolveProject() async {
      var result = await Process.run(resolveDartExecutable(), [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: projectRoot());
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    }

    setUp(() async {
      write(
        'upcase/pubspec.yaml',
        'name: upcase\nenvironment:\n  sdk: ^3.0.0\n',
      );
      write('upcase/bin/upcase.dart', """
import 'dart:io';
void main(List<String> args) {
  var input = args.firstWhere((a) => a.startsWith('--input=')).substring(8);
  var output = args.firstWhere((a) => a.startsWith('--output=')).substring(9);
  File(output)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(File(input).readAsStringSync().toUpperCase());
}
""");
      write('project/pubspec.yaml', '''
name: project
environment:
  sdk: ^3.0.0
dependencies:
  upcase:
    path: ../upcase
flutter:
  assets:
    - path: assets/icons/logo.svg
      transformers:
        - package: upcase
''');
      write('project/assets/icons/logo.svg', 'source bytes');
      await resolveProject();
    });

    test('puts the transformed bytes at the declared key', () async {
      // The end of the whole mechanism: the key is what the app names, and what
      // stands behind it is what a build would ship. Reading through the link
      // is the point — an app asking for `assets/icons/logo.svg` gets this.
      await builderWithDart().build(output());

      var entry = File(p.join(output(), 'assets/icons/logo.svg'));
      expect(entry.readAsStringSync(), 'SOURCE BYTES');
      expect(
        Link(entry.path).targetSync(),
        isNot(p.join(projectRoot(), 'assets/icons/logo.svg')),
        reason: 'linking the source is the bug this exists to end',
      );
    });

    test('an edited asset reaches the bundle transformed', () async {
      await builderWithDart().build(output());
      write('project/assets/icons/logo.svg', 'repainted');

      var sync = await builderWithDart().build(output());

      // Unlike an untransformed asset, this *is* a bundle change: the entry
      // pointed at the old content's cache entry and now points at the new
      // one, so the guest has to be told.
      expect(sync.changed, isTrue);
      expect(
        File(p.join(output(), 'assets/icons/logo.svg')).readAsStringSync(),
        'REPAINTED',
      );
    });

    test(
      'a failing transformer fails the build rather than serving source',
      () async {
        write('upcase/bin/upcase.dart', """
import 'dart:io';
void main(List<String> args) {
  stderr.writeln('bad glyph');
  exit(3);
}
""");
        write('project/assets/icons/logo.svg', 'unseen content');

        await expectLater(
          builderWithDart().build(output()),
          throwsA(isA<AssetTransformerException>()),
        );
      },
    );
  });

  group('the framework shaders', () {
    late String? saved;

    setUp(() {
      saved = flutterwareDirOverride;
      flutterwareDirOverride = p.join(root.path, 'flutterware');
    });
    tearDown(() => flutterwareDirOverride = saved);

    /// The real SDK, because what is under test is what `impellerc` produces
    /// and which of its outputs the cache hands back. A fixture cache has no
    /// shader sources, and [AssetBundleBuilder] then compiles nothing at all.
    var cache = FlutterCache(
      p.join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache'),
    );

    AssetBundleBuilder shaderBuilder() => AssetBundleBuilder(
      cache: cache,
      rootPackageRoot: projectRoot(),
      packageConfigPath: p.join(
        projectRoot(),
        '.dart_tool',
        'package_config.json',
      ),
    );

    test('a shader an older flutterware compiled is not served', () async {
      // What `~/.flutterware` looked like on every machine that had run
      // previews before `--runtime-stage-metal` was added: a file at the key
      // this used to cache under, holding four stages and no Metal. Serving it
      // is the whole bug — `FragmentProgram.fromAsset` throws on the first M3
      // ripple, and the fix is invisible until the developer deletes a
      // directory nobody told them about.
      var stale = File(
        p.join(
          flutterwareDirOverride!,
          'shaders',
          cache.engineRevision,
          'ink_sparkle.frag',
        ),
      )..parent.createSync(recursive: true);
      stale.writeAsStringSync('four stages and no Metal');

      await shaderBuilder().build(output());

      expect(
        File(p.join(output(), 'shaders', 'ink_sparkle.frag')).readAsBytesSync(),
        isNot(stale.readAsBytesSync()),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('two builders compiling at once do not share a scratch', () async {
      // The comparison runner lists both sides at once, and each side is a
      // `TesterHost` with a bundle of its own — two builders, one process. A
      // scratch named for the process alone is one path both impellerc
      // invocations write, and the loser's rename finds nothing there. Cold
      // caches are the only time either compiles, which used to mean a fresh
      // machine and now means the first run after any change to the stage
      // list.
      var bundles = [
        for (var n in ['a', 'b', 'c', 'd']) p.join(root.path, n),
      ];

      await Future.wait([
        for (var bundle in bundles) shaderBuilder().build(bundle),
      ]);

      var shaders = [
        for (var bundle in bundles)
          File(p.join(bundle, 'shaders', 'ink_sparkle.frag')).readAsBytesSync(),
      ];
      for (var bytes in shaders.skip(1)) {
        expect(bytes, shaders.first);
      }
      expect(
        shaders.first.length,
        greaterThan(1024),
        reason: 'a compiled shader, not a truncated interleave of two',
      );
      expect(
        Directory(p.join(flutterwareDirOverride!, 'shaders'))
            .listSync(recursive: true)
            .map((e) => p.basename(e.path)),
        isNot(contains(matches(r'\.frag\.\d+'))),
        reason: 'every scratch was renamed in, none abandoned',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group("the project's own shaders", () {
    late String? saved;

    setUp(() {
      saved = flutterwareDirOverride;
      flutterwareDirOverride = p.join(root.path, 'flutterware');
      resetShaderReportsForTesting();
      resetProjectShaderFailuresForTesting();
      write('project/pubspec.yaml', '''
name: project
flutter:
  shaders:
    - shaders/glow.frag
''');
      write('project/shaders/glow.frag', glow());
    });
    tearDown(() {
      flutterwareDirOverride = saved;
      beforeProjectShaderCompileForTesting = null;
    });

    /// The real SDK, as for the framework shaders: what is under test is what
    /// `impellerc` makes of the project's GLSL.
    var cache = FlutterCache(
      p.join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache'),
    );

    AssetBundleBuilder shaderBuilder() => AssetBundleBuilder(
      cache: cache,
      rootPackageRoot: projectRoot(),
      packageConfigPath: p.join(
        projectRoot(),
        '.dart_tool',
        'package_config.json',
      ),
    );

    String source() => p.join(projectRoot(), 'shaders', 'glow.frag');
    File entry([String name = 'glow.frag']) =>
        File(p.join(output(), 'shaders', name));

    /// Where [compileProjectShader] keeps its entries for this SDK.
    String cacheRoot() => p.join(
      flutterwareDirOverride!,
      'shaders',
      'project',
      '${cache.engineRevision}-$shaderStagesKey',
    );

    test('a declared shader lands at its key, compiled', () async {
      var sync = await shaderBuilder().build(output());

      expect(entry().existsSync(), isTrue);
      expect(
        entry().readAsBytesSync(),
        isNot(File(source()).readAsBytesSync()),
        reason:
            'FragmentProgram.fromAsset parses the compiled form, and '
            'throws on the GLSL',
      );
      expect(sync.shaders, {'shaders/glow.frag'});
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('its reflection lands beside the compiled bytes', () async {
      var compiled = await compileProjectShader(cache: cache, source: source());

      var reflection =
          jsonDecode(File(compiled.reflection).readAsStringSync()) as Map;
      expect(
        {
          for (var uniform in reflection['uniforms'] as List)
            (uniform as Map)['name'],
        },
        {'uSize', 'uTint'},
        reason: 'uSize is declared and unused, and still listed',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an edited shader is compiled again and reported', () async {
      await shaderBuilder().build(output());
      var before = entry().readAsBytesSync();
      write('project/shaders/glow.frag', glow(tint: 'uTint * 0.5'));

      var sync = await shaderBuilder().build(output());

      expect(sync.changed, isTrue);
      expect(sync.shaders, {'shaders/glow.frag'});
      expect(entry().readAsBytesSync(), isNot(before));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an edited include is compiled again', () async {
      write('project/shaders/common.glsl', 'vec3 tint(vec3 c) { return c; }');
      write(
        'project/shaders/glow.frag',
        glow(include: '#include "common.glsl"', tint: 'tint(uTint)'),
      );
      await shaderBuilder().build(output());
      var before = entry().readAsBytesSync();

      // The `.frag` itself is untouched: only a hash that reads its includes
      // can tell this build from the last.
      write(
        'project/shaders/common.glsl',
        'vec3 tint(vec3 c) { return c * 0.5; }',
      );
      var sync = await shaderBuilder().build(output());

      expect(entry().readAsBytesSync(), isNot(before));
      expect(sync.shaders, {'shaders/glow.frag'});
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a rebuild with nothing changed reports no shader', () async {
      await shaderBuilder().build(output());

      var sync = await shaderBuilder().build(output());

      expect(sync.changed, isFalse);
      expect(sync.shaders, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'a shader that does not compile is left out, and the rest still land',
      () async {
        write('project/pubspec.yaml', '''
name: project
flutter:
  shaders:
    - shaders/glow.frag
    - shaders/broken.frag
''');
        write('project/shaders/broken.frag', glow(tint: 'uTint * 0.5'));
        await shaderBuilder().build(output());
        expect(entry('broken.frag').existsSync(), isTrue);

        // Broken after it once compiled, so what is asserted is also that the
        // link to its last good bytes goes, and goes unreported: a load not
        // yet made finds nothing, and a guest already holding the program
        // keeps drawing it until the file compiles again.
        write('project/shaders/broken.frag', 'void main() { this is not glsl');
        var compiles = 0;
        beforeProjectShaderCompileForTesting = (source) {
          if (p.basename(source) == 'broken.frag') compiles++;
        };
        var err = StringBuffer();
        var sync = await capturingStderr(
          err,
          () => shaderBuilder().build(output()),
        );

        expect(entry().existsSync(), isTrue);
        expect(FileSystemEntity.isLinkSync(entry('broken.frag').path), isFalse);
        expect(sync.changed, isTrue);
        expect(sync.shaders, isEmpty);

        // The daemon rebundles every few seconds while previews are open; a
        // file that stays broken is neither compiled nor reported again.
        await capturingStderr(err, () => shaderBuilder().build(output()));
        expect(compiles, 1);
        expect(
          'broken.frag does not compile'.allMatches(err.toString()),
          hasLength(1),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      "a shader named like the framework's leaves the framework's",
      () async {
        write('project/pubspec.yaml', '''
name: project
flutter:
  shaders:
    - shaders/ink_sparkle.frag
''');
        write('project/shaders/ink_sparkle.frag', glow());

        var err = StringBuffer();
        var sync = await capturingStderr(
          err,
          () => shaderBuilder().build(output()),
        );
        await capturingStderr(err, () => shaderBuilder().build(output()));

        expect(
          Link(p.join(output(), 'shaders', 'ink_sparkle.frag')).targetSync(),
          isNot(contains(p.join('shaders', 'project'))),
          reason: 'every Material ripple loads this key',
        );
        expect(sync.shaders, isEmpty);
        expect(
          'shaders/ink_sparkle.frag is the name'.allMatches(err.toString()),
          hasLength(1),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a save during a compile does not file its bytes under the old content',
      () async {
        var before = projectShaderHash(source());
        var saves = 0;
        beforeProjectShaderCompileForTesting = (_) {
          // Once: hashed as the old text, compiled as the new.
          if (saves++ == 0) {
            write('project/shaders/glow.frag', glow(tint: 'uTint * 0.5'));
          }
        };

        var raced = await compileProjectShader(cache: cache, source: source());

        expect(
          p.dirname(raced.binary),
          p.join(cacheRoot(), projectShaderHash(source())),
        );
        expect(
          File(p.join(cacheRoot(), before, 'shader.iplr')).existsSync(),
          isFalse,
        );

        // The old text back, and it compiles as itself rather than being
        // served the program the race would have filed under it.
        write('project/shaders/glow.frag', glow());
        var restored = await compileProjectShader(
          cache: cache,
          source: source(),
        );
        expect(p.dirname(restored.binary), p.join(cacheRoot(), before));
        expect(
          File(restored.binary).readAsBytesSync(),
          isNot(File(raced.binary).readAsBytesSync()),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a source that will not hold still is compiled but not cached',
      () async {
        var saves = 0;
        beforeProjectShaderCompileForTesting = (_) => write(
          'project/shaders/glow.frag',
          glow(tint: 'uTint * 0.${++saves}'),
        );

        var compiled = await compileProjectShader(
          cache: cache,
          source: source(),
        );

        expect(saves, 3, reason: 'a bounded number of attempts');
        expect(File(compiled.binary).existsSync(), isTrue);
        expect(File(compiled.reflection).existsSync(), isTrue);
        expect(
          Directory(cacheRoot())
              .listSync(recursive: true)
              .whereType<File>()
              .map((file) => p.split(p.relative(file.path, from: cacheRoot())))
              .map((parts) => parts.first)
              .toSet(),
          {'unsettled'},
          reason: 'no content entry holds bytes of other content',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('a warm compile spawns nothing', () async {
      var first = await compileProjectShader(cache: cache, source: source());
      var modified = File(first.binary).lastModifiedSync();

      var second = await compileProjectShader(cache: cache, source: source());

      expect(second.binary, first.binary);
      expect(File(second.binary).lastModifiedSync(), modified);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('two builders compiling it at once do not share a scratch', () async {
      var bundles = [
        for (var n in ['a', 'b', 'c', 'd']) p.join(root.path, n),
      ];

      await Future.wait([
        for (var bundle in bundles) shaderBuilder().build(bundle),
      ]);

      var shaders = [
        for (var bundle in bundles)
          File(p.join(bundle, 'shaders', 'glow.frag')).readAsBytesSync(),
      ];
      for (var bytes in shaders.skip(1)) {
        expect(bytes, shaders.first);
      }
      var project = Directory(
        p.join(flutterwareDirOverride!, 'shaders', 'project'),
      );
      expect(
        project
            .listSync(recursive: true)
            .whereType<File>()
            .map((e) => p.basename(e.path))
            .toSet(),
        {'shader.iplr', 'reflection.json'},
        reason: 'every scratch, binary and reflection, was renamed in',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('a compiler that exits 0 without its outputs', () {
    late String? saved;
    late FlutterCache cache;

    setUp(() {
      saved = flutterwareDirOverride;
      flutterwareDirOverride = p.join(root.path, 'flutterware');
      resetShaderReportsForTesting();
      resetProjectShaderFailuresForTesting();
      cache = FlutterCache(p.join(root.path, 'cache'));
      write('cache/engine.stamp', 'fake');
      // Writes the binary and nothing else: no `.spirv`, no reflection.
      var impellerc = p.relative(cache.impellerc, from: root.path);
      write(impellerc, r'''
#!/bin/sh
for arg in "$@"; do
  case "$arg" in --sl=*) printf half > "${arg#--sl=}";; esac
done
''');
      Process.runSync('chmod', ['+x', cache.impellerc]);
      write('project/pubspec.yaml', '''
name: project
flutter:
  shaders:
    - shaders/glow.frag
''');
      write('project/shaders/glow.frag', glow());
    });
    tearDown(() => flutterwareDirOverride = saved);

    test('leaves no scratch beside the destination', () async {
      var destination = p.join(root.path, 'out', 'glow.iplr');
      Directory(p.dirname(destination)).createSync(recursive: true);

      await expectLater(
        compileShader(
          cache: cache,
          source: p.join(projectRoot(), 'shaders', 'glow.frag'),
          destination: destination,
          stages: shaderStages,
          reflection: p.join(root.path, 'out', 'glow.json'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(p.dirname(destination)).listSync(), isEmpty);
    });

    test('is reported, once, and not taken for a vanished source', () async {
      var err = StringBuffer();
      var builder = AssetBundleBuilder(
        cache: cache,
        rootPackageRoot: projectRoot(),
        packageConfigPath: p.join(
          projectRoot(),
          '.dart_tool',
          'package_config.json',
        ),
        nativeAssetsForTesting: [],
      );

      var sync = await capturingStderr(err, () => builder.build(output()));
      await capturingStderr(err, () => builder.build(output()));

      expect(
        File(p.join(output(), 'shaders', 'glow.frag')).existsSync(),
        isFalse,
      );
      expect(sync.shaders, isEmpty);
      expect(
        'shaders/glow.frag could not be compiled'.allMatches(err.toString()),
        hasLength(1),
      );
      expect(
        Directory(flutterwareDirOverride!)
            .listSync(recursive: true)
            .whereType<File>(),
        isEmpty,
        reason: 'neither a scratch nor a half-made entry is left',
      );
    });
  }, skip: Platform.isWindows ? 'the fake compiler is a shell script' : false);

  group('native libraries', () {
    late File lib;

    setUp(() {
      lib = File(p.join(root.path, 'hookout', 'libnative.dylib'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('machine code');
    });

    KernelAsset asset() => KernelAsset(
      id: 'package:native/native.dart',
      target: Target.current,
      path: KernelAssetAbsolutePath(lib.absolute.uri),
    );

    File copy() =>
        File(p.join(output(), nativeAssetsDirName, 'libnative.dylib'));

    Object? manifestEntry() {
      var manifest = jsonDecode(
        File(p.join(output(), 'NativeAssetsManifest.json')).readAsStringSync(),
      ) as Map;
      return ((manifest['native-assets'] as Map)['${Target.current}']
          as Map?)?['package:native/native.dart'];
    }

    // A copy where everything else is a link, because the file the guest maps
    // must be one nothing but this builder rewrites — the hook's own output is
    // rewritten in place by any tool that re-runs the hook on the checkout.
    test(
      'a bundled library is copied in and the manifest names the copy',
      () async {
        var sync = await builder(nativeAssets: [asset()]).build(output());

        expect(sync.changed, isTrue);
        expect(copy().readAsStringSync(), 'machine code');
        expect(FileSystemEntity.isLinkSync(copy().path), isFalse);
        expect(manifestEntry(), ['absolute', copy().path]);
      },
    );

    test('an unchanged library is quiet; a changed one is replaced', () async {
      await builder(nativeAssets: [asset()]).build(output());

      var second = await builder(nativeAssets: [asset()]).build(output());
      expect(second.changed, isFalse);

      // Longer bytes, so the stamp moves on size alone — a same-second
      // rewrite is not what this asserts.
      lib.writeAsStringSync('newer machine code');
      var third = await builder(nativeAssets: [asset()]).build(output());
      expect(third.changed, isTrue);
      expect(copy().readAsStringSync(), 'newer machine code');
    });

    test('a library the hooks no longer produce is pruned', () async {
      await builder(nativeAssets: [asset()]).build(output());
      expect(copy().existsSync(), isTrue);

      var sync = await builder(nativeAssets: []).build(output());

      expect(sync.changed, isTrue);
      expect(copy().existsSync(), isFalse);
      expect(File('${copy().path}.stamp').existsSync(), isFalse);
      expect(manifestEntry(), isNull);
    });

    // The load failure then names a real path, where dropping the entry would
    // fall back to process lookup — which succeeds wrongly on macOS.
    test('a missing source keeps its original path in the manifest', () async {
      lib.deleteSync();

      var sync = await builder(nativeAssets: [asset()]).build(output());

      expect(sync.changed, isTrue, reason: 'the manifest itself is new');
      expect(copy().existsSync(), isFalse);
      expect(manifestEntry(), ['absolute', lib.path]);
    });
  });
}

/// Runs [body] with what it writes to `stderr` going to [into], so a test of
/// a reported failure keeps the run's own output quiet and can count it.
Future<T> capturingStderr<T>(StringBuffer into, Future<T> Function() body) =>
    IOOverrides.runZoned(body, stderr: () => _CapturedStderr(into));

class _CapturedStderr implements Stdout {
  _CapturedStderr(this.into);

  final StringBuffer into;

  @override
  void write(Object? object) => into.write(object);

  @override
  void writeln([Object? object = '']) => into.writeln(object);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fragment shader with two uniforms, one of them unused.
String glow({String include = '', String tint = 'uTint'}) =>
    '''
#version 460 core
#include <flutter/runtime_effect.glsl>
$include
uniform vec2 uSize;
uniform vec3 uTint;
out vec4 fragColor;
void main() { fragColor = vec4($tint, 1.0); }
''';
