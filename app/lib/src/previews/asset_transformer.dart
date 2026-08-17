import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import '../assets/model/asset_catalog.dart';
import '../utils/run_dir.dart';

/// Runs a declaration's `transformers:` and hands back the bytes a build would
/// ship, cached by content.
///
/// **Why the catalog cannot simply link the source.** A build spawns each
/// transformer over the file and bundles the *output*; the entry keeps the
/// declared key, so `assets/logo.svg` in the app is the compiled vector, not the
/// SVG. Serving the source resolves the key to the wrong bytes — the loader
/// that decodes the output gets the input and draws nothing, and nothing about
/// it looks like an error. A blank icon with a healthy audit is the most
/// expensive answer a preview tool can give, which is why this exists.
///
/// **The invocation is `flutter_tools`' own** (`asset_transformer.dart`, 3.47):
/// `dart run <package> --input=<tmp> --output=<tmp> <args…>`, in the project
/// directory, with `FLUTTER_BUILD_MODE` in the environment, each transformer's
/// output chained into the next. Reproduced rather than approximated, because
/// the whole value here is that the bytes are the same bytes — verified on a
/// real 21-asset catalog, where every output matched the tool's byte for byte.
///
/// `dart run` rather than the resolved `bin/…dart` spawned directly, and it is
/// the *faster* of the two by 7×: pub precompiles executables to
/// `.dart_tool/pub/bin/<package>/<name>.dart-<sdk>.snapshot` and `dart run`
/// executes that, where naming the source recompiles it on every asset.
/// Measured alternately, one asset: 0.12s against 0.86s.
///
/// The `dart` is the SDK's, handed in — never a bare `dart`, which
/// `test/ambient_sdk_test.dart` fails the build over.
class AssetTransformerRunner {
  AssetTransformerRunner({
    required this.dart,
    required this.projectRoot,
    required this.packageConfigPath,
    String? cacheDir,
  }) : cacheDir = cacheDir ?? p.join(flutterwareDir(), 'transformed');

  /// The SDK's `dart`.
  final String dart;

  /// Where a transformer runs, which is what the tool does — a transformer may
  /// resolve its own inputs relative to the project.
  final String projectRoot;

  /// Read to key the cache on each transformer's *resolved* package.
  final String packageConfigPath;

  /// Outside the project on purpose, beside the shader cache and for the same
  /// reason: the output is a pure function of its inputs, so two worktrees of
  /// one repository share every hit and a deleted `build/` costs nothing.
  final String cacheDir;

  /// Resolved roots by package name — `…/vector_graphics_compiler-1.2.0/`,
  /// whose version segment is what makes a bumped transformer a new cache key
  /// without anything here having to read a version.
  Map<String, String>? _roots;

  /// How many transformers run at once. Four, which is `flutter_tools`'
  /// `DevelopmentAssetTransformer` pool — a number chosen against the same cost
  /// (a process per asset) on the same machines.
  static const concurrency = 4;

  /// The file whose bytes belong at [file]'s key: the transformed output, or
  /// [file] itself when nothing transforms it.
  ///
  /// Cheap and offline on a hit, which is the ordinary case — an unchanged
  /// asset never spawns anything.
  Future<String> pathFor(AssetFile file, List<AssetTransformer> chain) async {
    if (chain.isEmpty) return file.path;
    var source = File(file.path);
    if (!source.existsSync()) return file.path;

    var output = p.join(
      cacheDir,
      '${await _key(source, chain)}${p.extension(file.path)}',
    );
    if (File(output).existsSync()) return output;

    await _run(source, chain, output);
    _sweep();
    return output;
  }

  /// Drops cache entries nothing has produced in [_keepFor], and scratch
  /// directories a killed process left behind.
  ///
  /// **On a miss only**, which is what makes it free: the warm path — every
  /// build of an unchanged project — does no extra I/O at all, and a cold path
  /// has just paid for a process, so one directory listing is nothing beside it.
  /// Once per runner, so a 200-asset first build sweeps once rather than 200
  /// times.
  ///
  /// Keyed by content, so an entry is only ever *stale*, never wrong: sweeping
  /// one that is still in use costs a recompile on the next build and nothing
  /// else. That is what lets this be a blunt age rule rather than a reference
  /// count — and this cache has no natural bound otherwise, because every
  /// edited asset leaves its predecessor behind for ever. `~/.flutterware/run`
  /// grew to 161MB that way, having had sweep rules and no caller.
  void _sweep() {
    if (_swept) return;
    _swept = true;
    var directory = Directory(cacheDir);
    if (!directory.existsSync()) return;
    var cutoff = DateTime.now().subtract(_keepFor);
    for (var entity in directory.listSync(followLinks: false)) {
      try {
        if (entity is File) {
          if (entity.statSync().modified.isBefore(cutoff)) entity.deleteSync();
        } else if (entity is Directory && p.basename(entity.path) == _workDir) {
          // Scratch from a run that was killed between its temp dir and its
          // `finally`. The live ones are minutes old at most.
          for (var scratch in entity.listSync(followLinks: false)) {
            if (scratch.statSync().modified.isBefore(cutoff)) {
              scratch.deleteSync(recursive: true);
            }
          }
        }
      } on FileSystemException {
        // Another builder swept it first, or is writing it. Both are fine: this
        // is opportunistic housekeeping, never something a build depends on.
      }
    }
  }

  var _swept = false;

  /// Long enough that a project returned to after a holiday is still warm,
  /// short enough that a year of edits does not accumulate.
  static const _keepFor = Duration(days: 30);

  static const _workDir = '.work';

  /// Applies [chain] to [source], landing the last output at [output].
  ///
  /// Chained through scratch files the way the tool chains them, so a
  /// transformer that reads its input twice sees a real file rather than a pipe.
  Future<void> _run(
    File source,
    List<AssetTransformer> chain,
    String output,
  ) async {
    var work = Directory(p.join(cacheDir, _workDir))
      ..createSync(recursive: true);
    var scratch = work.createTempSync('transform');
    try {
      var input = source.path;
      String? produced;
      for (var (index, transformer) in chain.indexed) {
        produced = p.join(scratch.path, '$index${p.extension(source.path)}');
        await _spawn(transformer, input: input, output: produced);
        input = produced;
      }
      // Renamed in rather than written in place: two builders racing on a cold
      // cache each produce their own scratch, and the renames — of identical
      // bytes — land whole either way. The same trick `_compiledShader` uses.
      Directory(p.dirname(output)).createSync(recursive: true);
      File(produced!).renameSync(output);
    } finally {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    }
  }

  Future<void> _spawn(
    AssetTransformer transformer, {
    required String input,
    required String output,
  }) async {
    var result = await Process.run(
      dart,
      [
        'run',
        transformer.package,
        '--input=$input',
        '--output=$output',
        ...transformer.args,
      ],
      workingDirectory: projectRoot,
      environment: {
        // The tool passes the build mode, and a transformer is entitled to read
        // it. The guest is a debug build and says so rather than claiming the
        // release the app ships — a transformer whose output differs by mode
        // would otherwise be asked for bytes under a mode nobody is in.
        'FLUTTER_BUILD_MODE': 'debug',
      },
    );
    if (result.exitCode != 0 || !File(output).existsSync()) {
      throw AssetTransformerException(
        transformer: transformer,
        input: input,
        exitCode: result.exitCode,
        output: '${result.stdout}${result.stderr}'.trim(),
      );
    }
  }

  /// sha1 over the input bytes and, per transformer, its resolved package root
  /// and its arguments.
  ///
  /// **The bytes, not the mtime**: a checkout that rewrites a file to its own
  /// content must not recompile the world. **The resolved root, not the package
  /// name**: a hosted root carries its version, so a consumer bumping the
  /// transformer gets a new key for free and a path dependency keys on where it
  /// is — which is the best either can do without reading a lockfile this class
  /// has no business reading.
  Future<String> _key(File source, List<AssetTransformer> chain) async {
    var roots = _roots ??= await _resolveRoots();
    // Two steps rather than one buffer: an asset can be megabytes, and copying
    // it to prepend a short spec is a copy per asset per build for nothing.
    var content = sha1.convert(source.readAsBytesSync());
    var spec = [
      for (var transformer in chain)
        [
          roots[transformer.package] ?? transformer.package,
          ...transformer.args,
        ].join(' '),
    ].join(' | ');
    return sha1.convert(utf8.encode('$content $spec')).toString();
  }

  Future<Map<String, String>> _resolveRoots() async {
    try {
      var config = await loadPackageConfig(File(packageConfigPath));
      return {
        for (var package in config.packages)
          if (package.root.isScheme('file'))
            package.name: p.normalize(p.fromUri(package.root)),
      };
    } on Object {
      // A config that will not load is not this class's problem to report — the
      // compile is about to say so far more usefully. Keying on the bare name
      // is weaker, never wrong: the bytes still dominate the key.
      return const {};
    }
  }
}

/// A transformer that exited non-zero, or produced no output file.
///
/// **Raised rather than fallen back from.** Linking the source instead would
/// put the wrong bytes at a key that resolves, which is the exact failure this
/// whole mechanism exists to end — and it is how a blank icon shipped for
/// months. A build fails on this too.
class AssetTransformerException implements Exception {
  AssetTransformerException({
    required this.transformer,
    required this.input,
    required this.exitCode,
    required this.output,
  });

  final AssetTransformer transformer;

  /// What it was given — the source for the first in a chain, the previous
  /// transformer's output after that.
  final String input;

  final int exitCode;

  /// Everything the process said, both streams, so the message is the
  /// transformer's own rather than a paraphrase of it.
  final String output;

  @override
  String toString() =>
      '${transformer.package} failed on ${p.basename(input)} '
      '(exit $exitCode)${output.isEmpty ? '' : ':\n$output'}';
}
