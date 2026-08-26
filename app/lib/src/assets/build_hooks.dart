import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file/local.dart';
import 'package:hooks_runner/hooks_runner.dart';
import 'package:logging/logging.dart' as logging;
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

final _log = logging.Logger('flutterware.buildHooks');

/// What one [BuildHooks.run] found, so a caller can say something about it.
///
/// [failure] is a sentence, not an exception: a hook is a program a
/// *dependency* ships, and one that fails is closer to a compile error in that
/// dependency than to a broken catalog. Everything that did not need its output
/// still works, so the bundle is built either way and this is reported beside
/// it.
typedef BuildHooksResult = ({List<String> packages, String? failure});

/// Runs the `hook/build.dart` a project's dependencies ship, so the files they
/// produce exist before anything goes looking for them.
///
/// A package may generate part of itself at build time — `flutter_scene`
/// compiles its engine's shader bundles this way, and without them it throws
/// on the first frame. Nothing in flutterware ever ran those hooks, and a
/// preview of a 3D scene rendered anyway *because some other build had already
/// run them* and left the output in the shared pub cache. A clean checkout
/// rendered nothing, a developer who had run the app once rendered everything,
/// and neither could tell which they were.
///
/// **We ask for no asset types at all**, and that is the whole design rather
/// than an omission:
///
/// - It is what `flutter_tools` does on beta and stable, where `dartDataAssets`
///   is not yet a feature. A well-behaved hook answers by writing into its own
///   package directory, which its pubspec declares as an ordinary asset and
///   [AssetBundleBuilder] already ships. Ask for data assets instead and the
///   same hook takes the other branch — output lands beside the package
///   unbundled, and we would have to key and copy every file ourselves to keep
///   what already works working.
/// - It is what keeps this cheap. A hook that compiles native code begins
///   `if (!input.config.buildCodeAssets) return;`, so it costs a process spawn
///   and nothing else. Measured on this workspace: 40ms, whose one hook is
///   `objective_c`'s.
///
/// Native code is therefore still not built for previews — as it never was.
/// See `docs/superpowers/specs/2026-08-26-build-hooks-in-the-bundle-design.md`
/// for the two pieces this deliberately leaves for the day the toolchain needs
/// them.
///
/// Measured on a project that loads a `.glb`: **49.9s the first time on a
/// machine, 110–125ms after that**, and neither number is ours to improve —
/// `package:hooks_runner` caches the run, and the hook caches its own output
/// again inside it. Asking whether there is anything to run at all costs 30ms,
/// which is what a project with no hooks pays and all it pays.
class BuildHooks {
  BuildHooks({
    required this.dartExecutable,
    required this.packageConfigPath,
    required this.rootPackageRoot,
  });

  /// The `dart` that runs each hook — the project's SDK, never PATH's.
  final String dartExecutable;

  final String packageConfigPath;

  /// The package whose dependencies are the ones with hooks. Only its closure
  /// is asked, which is why a workspace sibling's dependency is never built:
  /// `sqlite3` sits in this repo's workspace and is not reachable from the app,
  /// so it is not even in the list.
  final String rootPackageRoot;

  /// Runs in flight or already finished, keyed by [_key].
  ///
  /// Two reasons, and each would be a bug on its own. `hooks_runner` documents
  /// that it does not support reentrancy for an identical input, and two
  /// bundle builds for one workspace are ordinary here. And a warm answer,
  /// while cheap, is not free — a preview reload rebuilds the bundle, and
  /// paying 222ms per reload to re-derive an answer that cannot have moved is
  /// the sort of tax that is never noticed and never removed.
  static final _runs = <String, Future<BuildHooksResult>>{};

  /// The resolution, hashed, plus who is asking about it.
  ///
  /// Content rather than mtime, and the same reason as
  /// [ManifestLoader]: `pub get` rewrites `package_config.json` whether or not
  /// anything moved, and flutterware runs `pub get` itself.
  ///
  /// What this key does *not* notice is a hook's own source changing under a
  /// path dependency. That is a package author editing their own hook, which
  /// no consumer does, and it costs them a restart rather than a wrong answer.
  String? _key() {
    var file = File(packageConfigPath);
    if (!file.existsSync()) return null;
    return '$rootPackageRoot\n${sha1.convert(file.readAsBytesSync())}';
  }

  /// Runs whatever hooks this project has, once.
  ///
  /// A project that has not been resolved yet has no hooks to speak of and no
  /// package config to find them through; it reports nothing rather than
  /// failing, because the caller is about to fail on the resolution itself and
  /// will say so better.
  Future<BuildHooksResult> run() {
    var key = _key();
    if (key == null) return Future.value(_nothing);

    if (_runs[key] case var running?) return running;
    // Deliberately not `putIfAbsent`: a failure must not be remembered, so the
    // entry has to be removable, and the two halves read better apart.
    var started = _guarded(key);
    _runs[key] = started;
    return started;
  }

  /// [_run], with the memo torn down again on anything that did not work.
  Future<BuildHooksResult> _guarded(String key) async {
    BuildHooksResult result;
    try {
      result = await _run();
    } on Object {
      unawaited(_runs.remove(key));
      rethrow;
    }
    if (result.failure case var failure?) {
      unawaited(_runs.remove(key));
      _log.severe(failure);
    }
    return result;
  }

  /// Nothing to run, said in the shape a caller expects.
  static const BuildHooksResult _nothing = (
    packages: <String>[],
    failure: null,
  );

  Future<BuildHooksResult> _run() async {
    var fileSystem = const LocalFileSystem();
    var packageConfigUri = File(packageConfigPath).absolute.uri;
    var packageConfig = await loadPackageConfigUri(packageConfigUri);

    var runPackageName = _rootPackageName(packageConfig);
    if (runPackageName == null) {
      // A root that the resolution does not name is not something to guess at.
      return _nothing;
    }

    var runner = NativeAssetsBuildRunner(
      logger: _forwarder(),
      dartExecutable: Uri.file(dartExecutable),
      fileSystem: fileSystem,
      packageLayout: PackageLayout.fromPackageConfig(
        fileSystem,
        packageConfig,
        packageConfigUri,
        runPackageName,
        includeDevDependencies: true,
      ),
      userDefines: UserDefines(
        workspacePubspec: File(
          p.join(p.dirname(p.dirname(packageConfigPath)), 'pubspec.yaml'),
        ).absolute.uri,
      ),
    );

    List<String> packages;
    try {
      packages = await runner.packagesWithBuildHooks();
    } on Object catch (e) {
      return (
        packages: const <String>[],
        failure: 'Could not read the package graph: $e',
      );
    }
    if (packages.isEmpty) return _nothing;

    var watch = Stopwatch()..start();
    Result<BuildResult, HooksRunnerFailure> result;
    try {
      result = await runner.build(extensions: const [], linkingEnabled: false);
    } on Object catch (e) {
      return (packages: packages, failure: 'Build hooks failed: $e');
    }
    if (!result.isSuccess) {
      return (
        packages: packages,
        failure:
            'The build hooks of ${packages.join(', ')} did not finish '
            '(${result.asFailure.failure.name}). Anything that needed the '
            'files they generate will be missing from the bundle.',
      );
    }
    _log.fine(
      'ran the build hooks of ${packages.join(', ')} in '
      '${watch.elapsedMilliseconds}ms',
    );
    return (packages: packages, failure: null);
  }

  /// The name [rootPackageRoot] goes by in the resolution.
  String? _rootPackageName(PackageConfig config) {
    for (var package in config.packages) {
      if (p.equals(package.root.toFilePath(), rootPackageRoot)) {
        return package.name;
      }
    }
    return null;
  }

  /// `hooks_runner` speaks `package:logging`, and so does the app — but a
  /// hook's own console is verbose enough that only what it says about
  /// *failing* belongs anywhere a human is looking.
  logging.Logger _forwarder() => logging.Logger.detached('hooks')
    ..level = logging.Level.ALL
    ..onRecord.listen((record) {
      if (record.level >= logging.Level.SEVERE) {
        _log.severe(record.message);
      } else if (record.level >= logging.Level.WARNING) {
        _log.warning(record.message);
      } else {
        _log.finer(record.message);
      }
    });
}
