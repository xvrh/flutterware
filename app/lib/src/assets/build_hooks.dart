import 'dart:async';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:file/local.dart';
import 'package:hooks_runner/hooks_runner.dart';
import 'package:logging/logging.dart' as logging;
import 'package:meta/meta.dart';
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
///
/// [nativeAssetsManifest] is the content of the `NativeAssetsManifest.json`
/// the engine reads from the asset directory — the map the VM resolves
/// `@Native` external functions through. The empty map when nothing shipped
/// native code, and always the empty map after a [failure], because a mapping
/// that names libraries a failed build may not have produced is worse than one
/// that says to look in the process.
typedef BuildHooksResult = ({
  List<String> packages,
  String? failure,
  String nativeAssetsManifest,
});

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
/// **We ask for code assets for the machine we are on, and for no data
/// assets.** Each half of that is a decision:
///
/// - Code assets are what a scenario's own dependencies load —
///   `package:sqlite3` resolves `@Native` functions through the mapping this
///   run produces — and the tester lane is the one lane where nobody else
///   builds them. `flutter test` builds them before it spawns a tester;
///   spawning the tester ourselves means doing the same or shipping the empty
///   map, and the empty map does not fail honestly: the VM falls back to
///   looking the symbol up in the running process, which happens to succeed on
///   macOS `flutter_tester` and fail on Linux. A consumer's suite was green on
///   every laptop and red on CI, identically, on step 1 of all 51 scenarios.
///   The target is the host, the way `flutter test` builds for
///   `TargetPlatform.tester`, because `flutter_tester` *is* a host binary.
/// - No data assets is what `flutter_tools` does on beta and stable, where
///   `dartDataAssets` is not yet a feature. A well-behaved hook answers by
///   writing into its own package directory, which its pubspec declares as an
///   ordinary asset and [AssetBundleBuilder] already ships. Ask for data
///   assets instead and the same hook takes the other branch — output lands
///   beside the package unbundled, and we would have to key and copy every
///   file ourselves to keep what already works working.
///
/// No C compiler is named, deliberately: `flutter test` itself tolerates not
/// finding one for this target (`mustMatchAppBuild: false`), and a hook that
/// compiles C discovers the host toolchain the same way it does under a plain
/// `dart test`. A machine where that discovery fails gets the [failure]
/// sentence and the empty map — which is exactly what it got before this ran
/// hooks at all.
///
/// See `docs/superpowers/specs/2026-08-26-build-hooks-in-the-bundle-design.md`
/// — this is its piece 3, built the day a real suite needed it; piece 2 (data
/// assets) still waits on the feature reaching beta.
///
/// Measured on a project that loads a `.glb`: **49.9s the first time on a
/// machine, 110–125ms after that**, and neither number is ours to improve —
/// `package:hooks_runner` caches the run, and the hook caches its own output
/// again inside it. Asking whether there is anything to run at all costs 30ms,
/// which is what a project with no hooks pays and all it pays. A hook that
/// compiles native code now genuinely compiles, and the same cache holds: it
/// is paid once per machine per resolution, not per bundle.
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
      _announce(failure);
    }
    return result;
  }

  /// Says [failure] somewhere a human will actually see it.
  ///
  /// **Both channels, and the second is the one that works.** `Logger.root` is
  /// listened to in `app/lib/main.dart` and nowhere else — not in
  /// `app/bin/fw.dart`, not in the MCP server, not in the previews compiler
  /// daemon, which are between them where most bundles are built. A hook
  /// failure logged there is a hook failure nobody is told about, and what the
  /// reader gets instead is the dependency's own bewildering sentence about
  /// missing shaders.
  ///
  /// So stderr as well, which every one of those processes has and every one
  /// of them forwards. Same escape, and the same reason, as
  /// `announceFlutterGpuDiagnosis`: a failure that will never pass through a
  /// structured report has to take the channel that exists.
  ///
  /// This is why [run]'s result may be discarded by a caller that has nothing
  /// better to do with it.
  void _announce(String failure) {
    _log.severe(failure);
    stderr.writeln('[flutterware] $failure');
  }

  /// The manifest that maps nothing — what every bundle shipped before hooks
  /// ran at all, and what a failed or hookless run still ships.
  static final String emptyNativeAssetsManifest = KernelAssets()
      .toNativeAssetsFile();

  /// Nothing to run, said in the shape a caller expects.
  static final BuildHooksResult _nothing = (
    packages: const <String>[],
    failure: null,
    nativeAssetsManifest: emptyNativeAssetsManifest,
  );

  Future<BuildHooksResult> _run() async {
    var fileSystem = const LocalFileSystem();
    var packageConfigUri = File(packageConfigPath).absolute.uri;
    var packageConfig = await loadPackageConfigUri(packageConfigUri);

    var runPackageName = _rootPackageName(packageConfig);
    if (runPackageName == null) {
      // Not `_nothing`. Which packages have hooks is read from the closure of
      // *this* package, so a root the resolution cannot name means no hook is
      // ever asked — and reported as silence that is indistinguishable from a
      // project that genuinely has none. The whole feature would switch itself
      // off and every test would stay green.
      return (
        packages: const <String>[],
        failure:
            'The resolution at $packageConfigPath does not name a package '
            'rooted at $rootPackageRoot, so no build hook could be run for it. '
            'Anything a dependency generates at build time will be missing '
            'from the bundle.',
        nativeAssetsManifest: emptyNativeAssetsManifest,
      );
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
        nativeAssetsManifest: emptyNativeAssetsManifest,
      );
    }
    if (packages.isEmpty) return _nothing;

    var watch = Stopwatch()..start();
    Result<BuildResult, HooksRunnerFailure> result;
    try {
      result = await runner.build(
        extensions: hostCodeAssets(),
        // What `flutter test` decides for a debug build: link hooks are an
        // AOT concern, and this lane is JIT by construction.
        linkingEnabled: false,
      );
    } on Object catch (e) {
      return (
        packages: packages,
        failure: 'Build hooks failed: $e',
        nativeAssetsManifest: emptyNativeAssetsManifest,
      );
    }
    if (!result.isSuccess) {
      return (
        packages: packages,
        failure:
            'The build hooks of ${packages.join(', ')} did not finish '
            '(${result.asFailure.failure.name}). Anything that needed the '
            'files they generate will be missing from the bundle.',
        nativeAssetsManifest: emptyNativeAssetsManifest,
      );
    }
    _log.fine(
      'ran the build hooks of ${packages.join(', ')} in '
      '${watch.elapsedMilliseconds}ms',
    );
    return (
      packages: packages,
      failure: null,
      nativeAssetsManifest: KernelAssets([
        for (var encoded in result.success.encodedAssets)
          if (encoded.isCodeAsset) kernelAssetOf(encoded.asCodeAsset),
      ]).toNativeAssetsFile(),
    );
  }

  /// What the hooks are asked to produce: dynamic libraries for the machine we
  /// are on, which is the machine `flutter_tester` runs on.
  ///
  /// No `cCompiler` — see the class doc — and the macOS config is required
  /// whenever the target is macOS; the floor is flutter_tools' own
  /// `targetMacOSVersion`.
  static List<CodeAssetExtension> hostCodeAssets() => [
    CodeAssetExtension(
      targetArchitecture: Architecture.current,
      targetOS: OS.current,
      linkModePreference: LinkModePreference.dynamic,
      macOS: OS.current == OS.macOS ? MacOSCodeConfig(targetVersion: 13) : null,
    ),
  ];

  /// Where the VM will find [asset], in the wording the engine's
  /// `native_assets.cc` expects.
  ///
  /// The mapping is flutter_tools' `_targetLocationSingleArchitecture`, minus
  /// the copy: a bundled library is pointed at where the hook left it, under
  /// the project's own `.dart_tool/hooks_runner`. `flutter test` copies its
  /// dylibs into `build/native_assets/` first, but what it writes for the
  /// tester are absolute host paths either way, and the hook's output is as
  /// stable as the copy — per checkout, invalidated with the resolution.
  @visibleForTesting
  static KernelAsset kernelAssetOf(CodeAsset asset) {
    var linkMode = asset.linkMode;
    var path = switch (linkMode) {
      DynamicLoadingSystem() => KernelAssetSystemPath(linkMode.uri),
      LookupInProcess() => KernelAssetInProcess(),
      LookupInExecutable() => KernelAssetInExecutable(),
      DynamicLoadingBundled() => KernelAssetAbsolutePath(asset.file!),
      _ => throw StateError(
        'Unsupported link mode ${linkMode.runtimeType} in asset ${asset.id}',
      ),
    };
    return KernelAsset(id: asset.id, target: Target.current, path: path);
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
