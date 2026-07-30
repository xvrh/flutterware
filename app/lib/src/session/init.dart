import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../shell/repo_layout.dart';
import '../utils/flutter_sdk.dart';

const _ignoreEntry = '.flutterware/';

/// Writes the small amount of state a project needs, so that later invocations
/// do not have to guess anything.
///
/// The whole reason this exists rather than a discovery heuristic: **whatever
/// runs `init` is already running under the right SDK.** `dart run flutterware`
/// arrives through the user's own `dart` — fvm, asdf, or whatever they use — so
/// the answer is there to be written down rather than inferred later from
/// conventions that may not hold.
///
/// Everything it writes is derived and disposable. Deleting `.flutterware/` and
/// running again produces the same directory.
class ProjectInit {
  ProjectInit({
    required this.root,
    required this.dartExecutable,
    required this.out,
    required this.err,
    Future<ProcessResult> Function(
      String,
      List<String>, {
      String? workingDirectory,
    })?
    runProcess,
  }) : _run = runProcess ?? Process.run;

  /// The repo root, as [findRepoRoot] resolves it — so `fw` from a
  /// subdirectory and `fw` from the top initialize the same place.
  final String root;

  /// The `dart` that launched us, which is inside the SDK we want recorded.
  final String dartExecutable;

  final StringSink out;
  final StringSink err;
  final Future<ProcessResult> Function(
    String,
    List<String>, {
    String? workingDirectory,
  })
  _run;

  Directory get directory => Directory(p.join(root, '.flutterware'));
  Link get sdkLink => Link(p.join(directory.path, 'sdk'));

  /// True when this project has been initialized — what the walker tests for.
  bool get isInitialized => sdkLink.existsSync();

  Future<int> run({bool quiet = false}) async {
    var sdk = await FlutterSdkPath.tryFind(dartExecutable);
    if (sdk == null) {
      err.writeln(
        'fw: no Flutter SDK above $dartExecutable.\n'
        'Run flutterware with the `dart` from a Flutter SDK.',
      );
      return 64;
    }

    directory.createSync(recursive: true);
    var target = _recordSdk(sdk);
    var ignored = await _ensureIgnored();
    var scaffolded = _scaffoldConfig();

    if (!quiet) {
      out.writeln('Initialized ${p.relative(directory.path, from: root)}/');
      out.writeln('  sdk -> $target');
      if (ignored) out.writeln('  added .flutterware/ to .gitignore');
      if (scaffolded) out.writeln('  wrote $configFileName');
    }
    return 0;
  }

  /// Points `.flutterware/sdk` at the SDK, preferring `.fvm/flutter_sdk` when
  /// it names the same one.
  ///
  /// Preferring it keeps fvm the single source of truth: switching versions
  /// there moves this pointer too, where an absolute path recorded once would
  /// quietly go on naming the old SDK. A relative target for the same reason —
  /// it survives the repo being moved.
  String _recordSdk(FlutterSdkPath sdk) {
    var fvm = Link(p.join(root, '.fvm', 'flutter_sdk'));
    var target = fvm.existsSync() && _realPath(fvm.path) == _realPath(sdk.root)
        ? p.join('..', '.fvm', 'flutter_sdk')
        : sdk.root;

    if (sdkLink.existsSync()) sdkLink.deleteSync();
    sdkLink.createSync(target);
    return target;
  }

  /// Both sides of the comparison have to be symlink-resolved.
  ///
  /// `FlutterSdkPath.root` is canonicalized *lexically*, which does not follow
  /// links — so comparing it against a resolved path is two different
  /// questions. On macOS a temp directory is `/var/...` lexically and
  /// `/private/var/...` resolved, and the two would never match.
  static String _realPath(String path) {
    try {
      return p.canonicalize(Directory(path).resolveSymbolicLinksSync());
    } on FileSystemException {
      return p.canonicalize(path);
    }
  }

  /// Makes sure `.flutterware/` is not committed. It holds an absolute SDK
  /// path and build output, so committing it breaks everyone else's checkout.
  ///
  /// Asks git rather than reading `.gitignore`, because a repo may ignore it
  /// through a broad pattern — this one ignores every dotfile with `.*` — and
  /// appending a redundant line to a tracked file is worse than doing nothing.
  Future<bool> _ensureIgnored() async {
    var probe = p.join(directory.path, 'sdk');
    try {
      var result = await _run('git', [
        'check-ignore',
        '-q',
        probe,
      ], workingDirectory: root);
      if (result.exitCode == 0) return false;
    } on ProcessException {
      return false; // No git. Nothing to protect it from.
    }

    var gitignore = File(p.join(root, '.gitignore'));
    var existing = gitignore.existsSync() ? gitignore.readAsStringSync() : '';

    // Our own line may already be there while git still says otherwise — a
    // `!.flutterware/` later in the file, a global excludes file, or no git at
    // all. Appending a second copy every run is the one outcome to rule out.
    if (const LineSplitter()
        .convert(existing)
        .any((line) => line.trim() == _ignoreEntry)) {
      return false;
    }
    gitignore.writeAsStringSync(
      '${existing.isEmpty || existing.endsWith('\n') ? existing : '$existing\n'}'
      '\n# flutterware: recorded SDK and build output, machine-specific.\n'
      '$_ignoreEntry\n',
    );
    return true;
  }

  /// Writes a starter `tool/flutterware.dart` when the project has none.
  ///
  /// A project with one package and the default plugins has nothing to say
  /// here, so this file is not required to work — but writing it is how anyone
  /// finds out that configuration exists at all, which an empty default never
  /// teaches.
  bool _scaffoldConfig() {
    var file = File(p.join(root, configFileName));
    if (file.existsSync()) return false;

    file.parent.createSync(recursive: true);
    file.writeAsStringSync('''
import 'package:flutterware/plugins.dart';

// Which tools this project gets, and what they work on.
//
// Run `fw status` to see what they say, and `fw actions` for what they can do.
// Every plugin listed here is available from the GUI, the CLI and MCP — they
// are three renderings of this file.

// One Pkg per package in the repo; the default is the single package here.
const app = Pkg('.');

void main() => Flutterware.configure((fw) {
  fw.packages([app]);

  fw.use(Dependencies(packages: [.new(app)]));

  // Renders the widgets you have annotated with `@Demo`.
  // `fw run ui_catalog entries` lists them.
  fw.use(UiCatalog(packages: [.new(app)]));
});
''');
    return true;
  }
}
