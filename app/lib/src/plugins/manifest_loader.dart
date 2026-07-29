import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

/// Where a project declares its plugins, relative to a worktree root.
const configFilePath = 'tool/flutterware.dart';

/// Thrown when the config file exists but could not be turned into a manifest.
class ManifestLoadException implements Exception {
  ManifestLoadException(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() =>
      details == null ? message : '$message\n${details!.trimRight()}';
}

/// Runs a worktree's `tool/flutterware.dart` and parses what it prints.
///
/// Still a plain `dart run` model, per the plan's decision 4 — no resident
/// compiler, no long-lived config process — with the compile step memoised on
/// disk. That is not a deviation: a `.dill` beside `package_config.json` holds
/// no state and is re-derived whenever either input moves.
///
/// It is worth the file. Measured, `dart run tool/flutterware.dart` costs
/// 510–590ms while the same file precompiled costs 70–80ms — which is the bare
/// VM floor, so the config's *own* work is unmeasurable and effectively all of
/// that half-second was `dart run` resolving and JIT-compiling 29 lines. Since
/// every `fw` invocation opens a session, it was most of the cost of every
/// command.
class ManifestLoader {
  ManifestLoader({
    required this.dartExecutable,
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    })?
    runProcess,
  }) : _run = runProcess ?? Process.run;

  /// The `dart` to run — the SDK pinned by the project, not whatever is on PATH.
  final String dartExecutable;

  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  _run;

  /// Returns the worktree's manifest, or null when it declares no config file.
  ///
  /// Throws [ManifestLoadException] when the file exists but fails — a broken
  /// config must be reported, never quietly treated as "no plugins".
  Future<PluginManifest?> load(String worktreePath) async {
    var configFile = File(p.join(worktreePath, configFilePath));
    if (!configFile.existsSync()) return null;

    var result = await _runConfig(worktreePath, configFile);

    if (result.exitCode != 0) {
      throw ManifestLoadException(
        '$configFilePath exited with ${result.exitCode}.',
        details: '${result.stderr}',
      );
    }

    // The dart tool writes its own chatter to stderr, so stdout is the
    // manifest and nothing else.
    var stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) {
      throw ManifestLoadException(
        '$configFilePath printed nothing. It must call Flutterware.configure.',
      );
    }
    try {
      return PluginManifest.parse(stdout);
    } on FormatException catch (e) {
      throw ManifestLoadException(
        'Could not read the manifest from $configFilePath.',
        details: '$e',
      );
    }
  }

  /// Runs the config, through its cached kernel when there is a good one.
  ///
  /// A kernel that will not load — most often one compiled by a different SDK
  /// — must not be reported as a broken config file, so a non-zero exit
  /// invalidates the cache and falls back to `dart run` before anything is
  /// blamed on the user. The config only prints a manifest, so running it
  /// twice on the error path costs a second and changes nothing.
  Future<ProcessResult> _runConfig(String worktreePath, File configFile) async {
    if (await _kernel(worktreePath, configFile) case var kernel?) {
      var result = await _run(dartExecutable, [
        kernel,
      ], workingDirectory: worktreePath);
      if (result.exitCode == 0) return result;
      _invalidate(worktreePath);
    }
    return _run(dartExecutable, [
      'run',
      configFilePath,
    ], workingDirectory: worktreePath);
  }

  /// A path to an up-to-date kernel of the config file, or null to use
  /// `dart run` — which is what happens when the project has not been resolved
  /// yet, or when compiling fails for a reason the fallback will report better.
  ///
  /// Keyed on the config file, the package resolution, and which `dart` is
  /// doing the compiling. The first two are what change the output; the third
  /// is there because an fvm switch changes the SDK without touching either —
  /// `package_config.json` names a `flutterRoot`, but only as of whenever pub
  /// last ran, so switching without resolving would otherwise go unnoticed.
  ///
  /// **Keyed on content, not mtime.** `pub get` rewrites
  /// `package_config.json` whether or not resolution moved, and the
  /// Dependencies plugin runs `pub get` itself — so a stat-based key made
  /// *using* flutterware invalidate flutterware's own cache, and every
  /// following command paid the ~450ms compile again. Content survives that,
  /// and survives a checkout or a stash that restores a file byte for byte.
  /// Hashing ~50KB to protect ~450ms is not a trade that needs measuring.
  Future<String?> _kernel(String worktreePath, File configFile) async {
    var packageConfig = File(
      p.join(worktreePath, '.dart_tool', 'package_config.json'),
    );
    if (!packageConfig.existsSync()) return null;

    var stamp = [
      sha1.convert(configFile.readAsBytesSync()),
      sha1.convert(packageConfig.readAsBytesSync()),
      dartExecutable,
    ].join('|');

    var dill = File(p.join(_cacheDir(worktreePath), 'manifest.dill'));
    var stampFile = File(p.join(_cacheDir(worktreePath), 'manifest.stamp'));
    if (dill.existsSync() &&
        stampFile.existsSync() &&
        stampFile.readAsStringSync() == stamp) {
      return dill.path;
    }

    Directory(_cacheDir(worktreePath)).createSync(recursive: true);
    var compiled = await _run(dartExecutable, [
      'compile',
      'kernel',
      '-o',
      dill.path,
      configFilePath,
    ], workingDirectory: worktreePath);
    if (compiled.exitCode != 0) return null;

    stampFile.writeAsStringSync(stamp);
    return dill.path;
  }

  void _invalidate(String worktreePath) {
    var stampFile = File(p.join(_cacheDir(worktreePath), 'manifest.stamp'));
    if (stampFile.existsSync()) stampFile.deleteSync();
  }

  static String _cacheDir(String worktreePath) =>
      p.join(worktreePath, '.dart_tool', 'flutterware');

  /// Convenience for callers that would rather render an error than catch.
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String worktreePath,
  ) async {
    try {
      return (manifest: await load(worktreePath), error: null);
    } on ManifestLoadException catch (e) {
      return (manifest: null, error: '$e');
    }
  }
}

/// Decodes a manifest already captured as text (used by tests and by the CLI,
/// which may have run the config itself).
PluginManifest parseManifest(String source) =>
    PluginManifest.fromJson(jsonDecode(source) as Map<String, Object?>);
