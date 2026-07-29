import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutterware/src/build_output.dart';
import 'package:flutterware/src/constants.dart';
import 'package:flutterware/src/utils/list_files.dart';
import 'package:path/path.dart' as p;

/// The launcher: find the CLI, build it if it is missing, get out of the way.
///
/// Reached three ways and always the same code — `dart run flutterware`, and
/// (later) a global `fw` that execs exactly that. It does no real work; every
/// command lives in `FwCli`, which this process starts and then waits for.
///
/// It deliberately does **not** hold stdin or pipe the child's output. The
/// child owns the terminal, so a `flutter run` further down the chain keeps its
/// own interactive console and its logs arrive without a websocket to carry
/// them.
void main(List<String> arguments) async {
  var pubPackage = await Isolate.resolvePackageUri(
    Uri.parse('package:flutterware/lib'),
  );
  if (pubPackage == null) {
    stderr.writeln(
      'flutterware: could not resolve its own package.\n'
      'This entry point has to be run through pub:\n\n'
      '    dart run flutterware',
    );
    exit(70);
  }

  var packageRoot = pubPackage.resolve('..').toFilePath();
  if (!File(p.join(packageRoot, 'pubspec.yaml')).existsSync() ||
      !File(p.join(packageRoot, 'app', 'pubspec.yaml')).existsSync()) {
    stderr.writeln('flutterware: incomplete package at $packageRoot');
    exit(70);
  }

  var force = arguments.contains('--$forceCompileOption');
  // Read here and also passed on: this process builds the CLI and the CLI
  // builds the GUI, so both ends of the chain need to know before either can
  // ask the other.
  var verbose = arguments.contains('--verbose') || arguments.contains('-v');
  var editable = !_inPubCache(packageRoot);
  var root = editable
      // A checkout is already a writable tree, so there is nothing to copy
      // into. Skipping it is not only faster: a copy is a *different* tree from
      // the one being edited, which is why editing flutterware used to require
      // remembering a flag, and why its own CLI was developed by a loop that
      // never ran it.
      ? packageRoot
      : await _workingCopy(packageRoot, force: force, verbose: verbose);

  var appPath = p.join(root, 'app');
  var cli = await _ensureCli(
    appPath,
    force: force,
    resolved: editable,
    verbose: verbose,
  );

  var process = await Process.start(
    cli,
    arguments,
    environment: {
      dartExecutableEnvironmentKey: Platform.resolvedExecutable,
      appPathEnvironmentKey: p.absolute(appPath),
      // One question, asked once: are these sources being edited? It decides
      // both whether to copy and, downstream, whether the GUI runs under
      // `flutter run` or as a built binary.
      editableSourcesEnvironmentKey: '$editable',
    },
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await process.exitCode);
}

/// True when the package was resolved out of the pub cache — i.e. an ordinary
/// consumer, rather than a path dependency on a checkout.
bool _inPubCache(String packageRoot) {
  var cache =
      Platform.environment['PUB_CACHE'] ??
      p.join(_userHomePath(), Platform.isWindows ? 'Pub/Cache' : '.pub-cache');
  return p.isWithin(p.canonicalize(cache), p.canonicalize(packageRoot));
}

/// Mirrors a pub-cache package into `~/.flutterware/<hash>` so there is a
/// writable tree to resolve and build in.
///
/// The hash is of the *flutterware package root*, which for a hosted dependency
/// already contains the version — so this is one copy per flutterware version
/// per machine, shared across every project that uses it, not one per project.
Future<String> _workingCopy(
  String packageRoot, {
  required bool force,
  required bool verbose,
}) async {
  var destination = p.join(_userHomePath(), '.flutterware', _hash(packageRoot));

  var stampFile = File(p.join(destination, '.source_stamp'));
  var stamp = _sourceStamp(packageRoot);
  if (!force &&
      stampFile.existsSync() &&
      stampFile.readAsStringSync() == stamp) {
    return destination;
  }

  await Step(
    'Unpacking flutterware',
    out: stdout,
    interactive: outputIsInteractive && !verbose,
  ).run(() async {
    for (var file in listFilesInDirectory(packageRoot)) {
      var target = p.join(
        destination,
        p.relative(file.path, from: packageRoot),
      );
      File(target).createSync(recursive: true);
      await file.copy(target);
    }
  });
  stampFile.writeAsStringSync(stamp);
  return destination;
}

/// Returns the CLI executable, building it when it is missing or out of date.
///
/// `dart build cli` rather than `dart compile exe`: the latter refuses outright
/// once anything in the resolution has a build hook, and `objective_c` arrives
/// via `path_provider`. `dart build cli` runs the hooks and emits a bundle —
/// the executable beside the dylibs it needs — which is why the answer is a
/// path into `bundle/bin` and not a lone file.
///
/// [resolved] says the tree has already been resolved, in which case the
/// `pub get` is skipped. This process reached `main` through
/// `dart run flutterware`, which resolves the whole workspace — and `app/` is a
/// member of it, so getting it again re-resolves the same workspace a second
/// time for nothing. It is only false for a fresh copy under `~/.flutterware`,
/// which really has never been resolved.
///
/// That second resolution was also the loudest thing in the terminal, and the
/// reason is worth writing down: pub run from a *member* prints ``Resolving
/// dependencies in `<workspace root>`…`` while the same command from the root
/// prints a bare `Resolving dependencies…`. So output that looked like the
/// launcher resolving itself was in fact this function, and reading the path in
/// that message is how to tell those apart.
Future<String> _ensureCli(
  String appPath, {
  required bool force,
  required bool resolved,
  required bool verbose,
}) async {
  var output = p.join(appPath, 'build', 'cli');
  var executable = p.join(output, 'bundle', 'bin', 'fw');

  if (!force && _isFresh(executable, appPath)) return executable;

  // Beside the artifact it explains, rather than in the project: at this point
  // nothing has established that the working directory *is* a project, and a
  // failed build must not be the thing that creates `.flutterware/`.
  var log = File(p.join(appPath, 'build', 'cli-build.log'));
  var step = Step(
    'Building the flutterware CLI',
    out: stdout,
    // A live line and a firehose cannot both own the last row of the terminal,
    // so `-v` gets the plain rendering: one line saying what is about to make
    // all the noise below it.
    interactive: outputIsInteractive && !verbose,
    budget: const Duration(seconds: 10),
    note: 'first run only',
  );

  var result = await step.run(() async {
    if (!resolved) {
      var pubGet = await runLogged(
        Platform.resolvedExecutable,
        ['pub', 'get'],
        workingDirectory: appPath,
        log: log,
        verbose: verbose,
      );
      if (!pubGet.ok) return pubGet;
    }

    return runLogged(
      Platform.resolvedExecutable,
      ['build', 'cli', '-t', p.join('bin', 'fw.dart'), '-o', output],
      workingDirectory: appPath,
      log: log,
      append: !resolved,
      verbose: verbose,
    );
  }, ok: (result) => result.ok);

  if (!result.ok) {
    describeFailure(stderr, 'could not build the CLI.', result);
    exit(70);
  }
  return executable;
}

/// Whether the built CLI is newer than every source that goes into it.
///
/// Modification times rather than the content hash [_sourceStamp] computes:
/// this runs on every invocation, and stat-ing is cheap where hashing 1280
/// files is ~100ms — about what the whole command should cost.
bool _isFresh(String executable, String appPath) {
  var built = File(executable);
  if (!built.existsSync()) return false;
  var builtAt = built.lastModifiedSync();

  var packageRoot = p.dirname(appPath);
  for (var directory in [
    p.join(appPath, 'lib'),
    p.join(appPath, 'bin'),
    p.join(packageRoot, 'lib'),
  ]) {
    if (!Directory(directory).existsSync()) continue;
    for (var file in listFilesInDirectory(directory)) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.lastModifiedSync().isAfter(builtAt)) return false;
    }
  }
  return true;
}

/// Identifies the source tree, so a changed checkout is noticed without being
/// declared.
///
/// The same walk the copy uses, so what is fingerprinted is exactly what is
/// copied — a file the copy would skip must not be able to invalidate it.
String _sourceStamp(String root) {
  var digest = <String>[];
  for (var file in listFilesInDirectory(root)) {
    var stat = file.statSync();
    digest.add(
      '${p.relative(file.path, from: root)}'
      '|${stat.size}|${stat.modified.millisecondsSinceEpoch}',
    );
  }
  digest.sort();
  return sha1.convert(utf8.encode(digest.join('\n'))).toString();
}

String _userHomePath() {
  var envKey = Platform.isWindows ? 'APPDATA' : 'HOME';
  return Platform.environment[envKey] ?? '.';
}

String _hash(String input) => sha1
    .convert(utf8.encode(input))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();
