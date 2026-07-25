import 'dart:convert';
import 'dart:io';

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
/// Deliberately a plain `dart run`, per the plan's decision 4: no resident
/// compiler, no long-lived config process. It costs ~0.5s and is re-run when
/// the file changes.
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

    var result = await _run(dartExecutable, [
      'run',
      configFilePath,
    ], workingDirectory: worktreePath);

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
