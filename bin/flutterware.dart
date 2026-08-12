import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutterware/src/build_output.dart';
import 'package:flutterware/src/constants.dart';
import 'package:flutterware/src/desktop_gui.dart';
import 'package:flutterware/src/launch_plan.dart';
import 'package:flutterware/src/live_region.dart';
import 'package:flutterware/src/utils/list_files.dart';
import 'package:path/path.dart' as p;

/// The launcher: make sure the artifacts are current, then get out of the way.
///
/// Reached three ways and always the same code — `dart run flutterware`, and
/// (later) a global `fw` that execs exactly that. It does no real work; every
/// command lives in `FwCli`, which this process starts and then waits for.
///
/// It deliberately does **not** hold stdin or pipe the child's output. The
/// child owns the terminal, so a `flutter run` further down the chain keeps its
/// own interactive console and its logs arrive without a websocket to carry
/// them.
///
/// The one thing it does that looks like real work is **starting the GUI build
/// beside the CLI build**. Measured, cold: 5.6s then 38.4s serially against
/// 34s together, because `flutter build` spends most of its wall time in Xcode
/// rather than on a core the Dart compiler wants. It does not learn how to
/// build the GUI to do that — [DesktopGui] is the one place that knows — but it
/// does have to *predict* whether the CLI is about to want one. See
/// [_willBuildGui] for why that prediction is allowed to exist.
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
      : _workingCopyPath(packageRoot);

  var appPath = p.join(root, 'app');
  var cliExecutable = p.join(appPath, 'build', 'cli', 'bundle', 'bin', 'fw');
  var sdkRoot = findFlutterSdkRoot(Platform.resolvedExecutable);
  var gui = sdkRoot == null
      ? null
      : DesktopGui(appPath: appPath, flutterSdk: sdkRoot);

  var guiBuild = await _work(
    arguments,
    packageRoot: packageRoot,
    root: root,
    appPath: appPath,
    cliExecutable: cliExecutable,
    gui: gui,
    editable: editable,
    force: force,
    verbose: verbose,
  );

  var process = await Process.start(
    cliExecutable,
    arguments,
    environment: {
      dartExecutableEnvironmentKey: Platform.resolvedExecutable,
      appPathEnvironmentKey: p.absolute(appPath),
      // One question, asked once: are these sources being edited? It decides
      // both whether to copy and, downstream, whether the GUI runs under
      // `flutter run` or as a built binary.
      editableSourcesEnvironmentKey: '$editable',
      if (guiBuild != null)
        guiBuildResultEnvironmentKey: '${guiBuild.exitCode}',
    },
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await process.exitCode);
}

/// Everything that has to exist before `fw` can run, narrated as a plan.
///
/// Returns the GUI build's result, or null when there was no GUI build — which
/// is the whole contract with [guiBuildResultEnvironmentKey].
///
/// **The stages are decided before any of them runs.** That is the reason this
/// function exists rather than each `_ensure…` narrating itself: listing what
/// is going to happen is the only thing that answers "how much is left", and
/// nothing can list what it has not yet decided.
Future<ProcessLog?> _work(
  List<String> arguments, {
  required String packageRoot,
  required String root,
  required String appPath,
  required String cliExecutable,
  required DesktopGui? gui,
  required bool editable,
  required bool force,
  required bool verbose,
}) async {
  var stamp = editable ? null : _sourceStamp(packageRoot);
  var stampFile = File(p.join(root, '.source_stamp'));
  var unpacks =
      stamp != null &&
      (force ||
          !stampFile.existsSync() ||
          stampFile.readAsStringSync() != stamp);

  // A fresh copy has never been resolved. Everything else reached `main`
  // through `dart run flutterware`, which resolved the whole workspace — and
  // `app/` is a member of it, so getting it again resolves the same thing
  // twice for nothing.
  var resolves = unpacks;
  var buildsCli = force || !_isFresh(cliExecutable, appPath);
  var buildsGui =
      gui != null &&
      _willBuildGui(arguments, editable: editable) &&
      (force || !gui.binary.existsSync());

  var unpack = unpacks
      ? LaunchStage('unpack flutterware', budget: const Duration(seconds: 3))
      : null;
  var resolve = resolves
      ? LaunchStage('resolve dependencies', budget: const Duration(seconds: 5))
      : null;
  var buildCli = buildsCli
      ? LaunchStage('build the CLI', budget: const Duration(seconds: 10))
      : null;
  var buildGui = buildsGui
      ? LaunchStage('build the GUI', budget: const Duration(seconds: 30))
      : null;

  var stages = [?unpack, ?resolve, ?buildCli, ?buildGui];
  // The warm path, which is every run but a handful: say nothing, cost nothing.
  if (stages.isEmpty) return null;

  var log = File(p.join(appPath, 'build', 'cli-build.log'));
  // `mcp` is about to speak JSON-RPC on stdout, and a cold first run is exactly
  // when there is something to narrate. Writing the plan there would put a
  // progress panel in front of the handshake, so the narration moves rather
  // than being suppressed — a 40s silent start is the other way to look broken.
  var protocolOwnsStdout = _ownsStdout(arguments);
  var plan = LaunchPlan(
    stages,
    out: protocolOwnsStdout ? stderr : stdout,
    // A live panel and a firehose cannot both own the bottom of the terminal,
    // so `-v` gets the plain rendering: one line per stage saying what is about
    // to make all the noise below it. So does a redirected stderr, which no
    // amount of cursor movement is going to redraw.
    interactive: outputIsInteractive && !verbose && !protocolOwnsStdout,
    title: 'flutterware · ${p.basename(Directory.current.path)}',
    subtitle: buildGui == null
        ? null
        : 'Building the tools — once per flutterware version.',
  )..start();

  if (unpack != null) {
    await plan.run(unpack, () async => _copyInto(packageRoot, root, stamp!));
  }

  if (resolve != null) {
    var result = await plan.run(
      resolve,
      () => runLogged(
        Platform.resolvedExecutable,
        ['pub', 'get'],
        workingDirectory: appPath,
        log: log,
        verbose: verbose,
      ),
      ok: (result) => result.ok,
    );
    if (!result.ok) {
      plan.finish();
      describeFailure(stderr, 'could not resolve the flutterware app.', result);
      exit(70);
    }
  }

  // The overlap. Both are CPU-bound in bursts and neither reads the other's
  // output, so the only thing they contend for is the machine — and the
  // measurement says that costs the CLI build 0.2s.
  var cliFuture = buildCli == null
      ? null
      : plan.run(
          buildCli,
          () => runLogged(
            Platform.resolvedExecutable,
            [
              'build',
              'cli',
              '-t',
              p.join('bin', 'fw.dart'),
              '-o',
              p.join(appPath, 'build', 'cli'),
            ],
            workingDirectory: appPath,
            log: log,
            append: resolve != null,
            verbose: verbose,
          ),
          ok: (result) => result.ok,
        );
  var guiFuture = buildGui == null
      ? null
      : plan.run(
          buildGui,
          () => gui!.build(verbose: verbose),
          ok: (result) => result.ok,
        );

  await Future.wait([?cliFuture, ?guiFuture]);
  var cliResult = await cliFuture;
  var guiResult = await guiFuture;

  if (cliResult != null && !cliResult.ok) {
    plan.finish();
    describeFailure(stderr, 'could not build the CLI.', cliResult);
    exit(70);
  }

  // A failed GUI build is not reported here — see
  // [guiBuildResultEnvironmentKey]. The plan still shows which stage failed,
  // and the CLI writes the error a moment later.
  plan.finish(
    closing: guiResult == null || guiResult.ok
        ? '${Ansi.style('ready', Ansi.ok)} in ${plan.elapsed.inSeconds}s'
        : null,
  );
  return guiResult;
}

/// Whether the command about to run is going to speak a protocol on stdout.
///
/// A prediction, like [_willBuildGui], and wrong in only one harmless
/// direction: narrating to stderr for a command that did not need it costs a
/// human nothing, where narrating to stdout for one that did costs it the
/// connection.
bool _ownsStdout(List<String> arguments) =>
    arguments.firstWhere((a) => !a.startsWith('-'), orElse: () => '') == 'mcp';

/// Whether the command about to run is going to want a built GUI.
///
/// A prediction, and therefore a duplicate of the first few lines of
/// `FwCli.run` and of `GuiLauncher.run`'s mode test. It is allowed because
/// being wrong is cheap in one direction and impossible in the other: predict
/// *no* and the CLI builds it exactly as it always did, one stage later.
/// Predicting *yes* wrongly would spend 38 seconds on a window nobody asked
/// for, which is why the test is the literal one — no arguments or `app`, and
/// a path dependency only when it is `--release`, because otherwise the GUI
/// runs under `flutter run` and there is nothing to build.
bool _willBuildGui(List<String> arguments, {required bool editable}) {
  var argv = arguments
      .where((a) => a != '--json' && a != '--verbose' && a != '-v')
      .toList();
  // Mirrors `FwCli.run`: a leading flag is the `app` command — except the
  // help flags, which must not spend 38 seconds building a window to print
  // usage.
  var first = argv.firstOrNull;
  var command = first == null
      ? 'app'
      : first == '--help' || first == '-h'
      ? 'help'
      : first.startsWith('-')
      ? 'app'
      : first;
  if (command != 'app') return false;
  return !editable || argv.contains('--release');
}

/// True when the package was resolved out of the pub cache — i.e. an ordinary
/// consumer, rather than a path dependency on a checkout.
bool _inPubCache(String packageRoot) {
  var cache =
      Platform.environment['PUB_CACHE'] ??
      p.join(_userHomePath(), Platform.isWindows ? 'Pub/Cache' : '.pub-cache');
  return p.isWithin(p.canonicalize(cache), p.canonicalize(packageRoot));
}

/// Where a pub-cache package is mirrored so there is a writable tree to resolve
/// and build in.
///
/// The hash is of the *flutterware package root*, which for a hosted dependency
/// already contains the version — so this is one copy per flutterware version
/// per machine, shared across every project that uses it, not one per project.
///
/// Split from the copy itself because the plan has to be decided before
/// anything runs, and deciding it means knowing this path first: whether the
/// CLI and the GUI need building are questions about files inside it.
String _workingCopyPath(String packageRoot) =>
    p.join(_userHomePath(), '.flutterware', _hash(packageRoot));

/// [packageRoot] is its own ignore root, here and in [_sourceStamp] and
/// [_isFresh]: this package sits in the pub cache, and a rule from some
/// unrelated repository above it — `$HOME` kept as a dotfiles repo is the way
/// that happens — would drop files the copy has to carry.
void _copyInto(String packageRoot, String destination, String stamp) {
  for (var file in listFilesInDirectory(packageRoot, ignoreRoot: packageRoot)) {
    var target = p.join(destination, p.relative(file.path, from: packageRoot));
    File(target).createSync(recursive: true);
    file.copySync(target);
  }
  // Last, so an interrupted copy is not recorded as a complete one.
  File(p.join(destination, '.source_stamp')).writeAsStringSync(stamp);
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
    for (var file in listFilesInDirectory(directory, ignoreRoot: packageRoot)) {
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
  for (var file in listFilesInDirectory(root, ignoreRoot: root)) {
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
