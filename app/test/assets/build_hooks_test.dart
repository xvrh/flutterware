import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/assets/build_hooks.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Against the real resolution, on purpose.
///
/// A fixture can say that [BuildHooks] calls what it is told to call. What it
/// cannot say is whether the thing being called still behaves the way the whole
/// design rests on — that asking for no asset types leaves a native hook doing
/// nothing, and that the runner reads a package graph the same way it did when
/// this was written. Both of those live in packages that move under us, so this
/// asks them.
void main() {
  late FlutterSdkPath sdk;
  var repoRoot = p.normalize(p.absolute('..'));

  setUpAll(() async {
    var found = await FlutterSdkPath.tryFind(Platform.resolvedExecutable);
    if (found == null) {
      fail(
        'Could not find the Flutter SDK from ${Platform.resolvedExecutable}',
      );
    }
    sdk = found;
  });

  test('an unresolved project has nothing to run and nothing to say', () async {
    var temp = Directory.systemTemp.createTempSync('fw_hooks');
    addTearDown(() => temp.deleteSync(recursive: true));

    var result = await BuildHooks(
      dartExecutable: sdk.dart,
      packageConfigPath: p.join(temp.path, '.dart_tool', 'package_config.json'),
      rootPackageRoot: temp.path,
    ).run();

    // Not an error. The caller is about to fail on the resolution itself and
    // will say so better than a complaint about hooks would.
    expect(result.packages, isEmpty);
    expect(result.failure, isNull);
  });

  test(
    'this workspace runs its own hooks without building native code',
    () async {
      var watch = Stopwatch()..start();
      var result = await BuildHooks(
        dartExecutable: sdk.dart,
        packageConfigPath: p.join(
          repoRoot,
          '.dart_tool',
          'package_config.json',
        ),
        rootPackageRoot: p.join(repoRoot, 'app'),
      ).run();
      watch.stop();

      expect(result.failure, isNull);
      // Which packages ship a hook is the resolution's business and differs by
      // host — `objective_c` is here on macOS and not on Linux. What must hold
      // everywhere is that running them is a rounding error, because every hook
      // in reach compiles native code and we ask for none of it. Measured 40ms
      // on macOS; an order of magnitude of headroom against a loaded CI host.
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 20)),
        reason: 'ran ${result.packages}',
      );
    },
  );

  test('a root the resolution cannot name is a failure, not silence', () async {
    var temp = Directory.systemTemp.createTempSync('fw_hooks_root');
    addTearDown(() => temp.deleteSync(recursive: true));

    // A real resolution, and a root that is not in it. Nothing can be asked of
    // a closure that cannot be found, and reporting that as "no hooks here"
    // would switch the whole feature off silently.
    var result = await BuildHooks(
      dartExecutable: sdk.dart,
      packageConfigPath: p.join(repoRoot, '.dart_tool', 'package_config.json'),
      rootPackageRoot: temp.path,
    ).run();

    expect(result.packages, isEmpty);
    expect(result.failure, contains('does not name a package'));
  });

  test('a second ask is the same run, not a second one', () async {
    var hooks = BuildHooks(
      dartExecutable: sdk.dart,
      packageConfigPath: p.join(repoRoot, '.dart_tool', 'package_config.json'),
      rootPackageRoot: p.join(repoRoot, 'app'),
    );
    // `hooks_runner` documents that it does not support reentrancy for an
    // identical input, and two bundle builds for one workspace are ordinary.
    expect(hooks.run(), same(hooks.run()));
  });

  test('the pinned hooks_runner is the one the SDK builds with', () {
    var tools = p.join(sdk.root, 'packages', 'flutter_tools', 'pubspec.yaml');
    if (!File(tools).existsSync()) {
      fail('No flutter_tools pubspec at $tools');
    }
    Object? pinIn(String pubspec) {
      var yaml = loadYaml(File(pubspec).readAsStringSync()) as YamlMap;
      return (yaml['dependencies'] as YamlMap)['hooks_runner'];
    }

    var theirs = pinIn(tools);
    var ours = pinIn(p.absolute('pubspec.yaml'));

    expect(
      '$ours',
      '$theirs',
      reason:
          'A hook and the runner negotiate a protocol version, so the runner '
          'the SDK resolved a project against is the one that can speak to '
          "that project's hooks. Bump app/pubspec.yaml to match — and check "
          'what the new constraint does to the rest of the resolution before '
          'you do: 1.6.3 requires `code_assets ^2.0.0`, which evicts '
          '`native_toolchain_c` and takes `sqlite3` back a major version.',
    );
  });
}
