import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../shell/repo_layout.dart';
import '../utils/flutter_sdk.dart';

const _ignoreEntry = '.flutterware/';

/// Where an agent looks for the servers a project offers.
///
/// Committed rather than ignored, unlike everything else `init` writes: it says
/// what this project *is*, not what one machine happens to have, and a
/// checkout that arrives already knowing its own tools is the entire point.
const mcpConfigFileName = '.mcp.json';

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

  /// True when `.flutterware/sdk` is there — what the walker tests for.
  ///
  /// Deliberately not what decides whether [run] happens. It names one
  /// artifact, and standing it in for "everything init writes" is what used to
  /// keep later additions out of any project that had run once already.
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
    var registered = _registerMcpServer();

    if (!quiet) {
      out.writeln('Initialized ${p.relative(directory.path, from: root)}/');
      out.writeln('  sdk -> $target');
      if (ignored) out.writeln('  added .flutterware/ to .gitignore');
      if (scaffolded) out.writeln('  wrote $configFileName');
      if (registered) {
        out.writeln('  registered `fw mcp` in $mcpConfigFileName');
        // The entry names `fw`, so it resolves only if `fw` is installed. Said
        // here because this is the moment the file starts claiming otherwise,
        // and an agent that cannot spawn the command reports nothing useful
        // about why.
        out.writeln('    agents need `fw` on PATH: dart install flutterware');
        // A repo that ignores every dotfile — `.*`, which is common and is
        // what this one does — has just had the file written and hidden. It
        // still works for whoever ran this, so it is not worth refusing to
        // write; it is worth not implying the rest of the team got it.
        if (await _isIgnoredByGit(p.join(root, mcpConfigFileName))) {
          out.writeln('    .gitignore hides it, so it stays on this machine');
        }
      }
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

    // Leave an unchanged link alone. This runs before every command now, and
    // delete-then-create is a write where nothing has moved — briefly, a
    // window with no link at all.
    if (sdkLink.existsSync()) {
      if (sdkLink.targetSync() == target) return target;
      sdkLink.deleteSync();
    }
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

  /// Whether git already ignores [path].
  ///
  /// Asked of git rather than read off `.gitignore`, because a repo may cover a
  /// path through a broad pattern — this one ignores every dotfile with `.*` —
  /// or through a global excludes file this cannot see at all.
  ///
  /// No git means no, for two callers that both want that answer: nothing to
  /// protect `.flutterware/` from, and nothing hiding `.mcp.json`.
  Future<bool> _isIgnoredByGit(String path) async {
    try {
      var result = await _run('git', [
        'check-ignore',
        '-q',
        path,
      ], workingDirectory: root);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Makes sure `.flutterware/` is not committed. It holds an absolute SDK
  /// path and build output, so committing it breaks everyone else's checkout.
  ///
  /// Appending a redundant line to a tracked file is worse than doing nothing,
  /// hence the question first.
  Future<bool> _ensureIgnored() async {
    var gitignore = File(p.join(root, '.gitignore'));
    var existing = gitignore.existsSync() ? gitignore.readAsStringSync() : '';

    // Our own line may already be there while git still says otherwise — a
    // `!.flutterware/` later in the file, a global excludes file, or no git at
    // all. Appending a second copy every run is the one outcome to rule out.
    //
    // Asked before git, not after: this runs before every command, the answer
    // stays true once it is true, and reading a file beats spawning a process.
    if (const LineSplitter()
        .convert(existing)
        .any((line) => line.trim() == _ignoreEntry)) {
      return false;
    }

    if (await _isIgnoredByGit(p.join(directory.path, 'sdk'))) return false;
    gitignore.writeAsStringSync(
      '${existing.isEmpty || existing.endsWith('\n') ? existing : '$existing\n'}'
      '\n# flutterware: recorded SDK and build output, machine-specific.\n'
      '$_ignoreEntry\n',
    );
    return true;
  }

  /// Adds `flutterware` to the project's `.mcp.json`, so an agent opening this
  /// repo finds the tools without anyone having wired them up.
  ///
  /// Answers the question the other two surfaces never had: the GUI is a window
  /// you can see and `fw` is a command you can type, but an MCP server nobody
  /// has configured is indistinguishable from one that does not exist.
  ///
  /// **Merges; never rewrites.** This is the one file `init` touches that
  /// flutterware does not own — other servers live in it, it is normally
  /// committed, and an entry someone has edited is an entry they meant. So a
  /// `flutterware` key that is already there is left exactly as it is, and a
  /// file that does not parse is left alone entirely rather than replaced with
  /// a valid one that has lost whatever it said.
  bool _registerMcpServer() {
    var file = File(p.join(root, mcpConfigFileName));

    Map<String, Object?> config;
    if (file.existsSync()) {
      try {
        config = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      } on Object {
        return false;
      }
    } else {
      config = {};
    }

    var declared = config['mcpServers'];
    // Present but not an object: someone else's schema, or a typo. Either way
    // it is not ours to correct.
    if (declared != null && declared is! Map<String, Object?>) return false;
    var servers = (declared as Map<String, Object?>?) ?? <String, Object?>{};
    if (servers.containsKey('flutterware')) return false;

    servers['flutterware'] = {
      // `fw` rather than an absolute path: the path would name this machine's
      // pub cache, and this file is committed.
      'command': 'fw',
      'args': ['mcp'],
    };
    config['mcpServers'] = servers;

    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n',
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

// One Pkg per package you want a tool to work on; the default is the single
// package here. Hand each tool the ones it applies to.
const app = Pkg('.');

void main() => Flutterware.configure((fw) {
  fw.use(Dependencies(packages: [.new(app)]));

  // Renders the widgets you have annotated with `@Demo`.
  // `fw run ui_catalog entries` lists them.
  fw.use(UiCatalog(packages: [.new(app)]));
});
''');
    return true;
  }
}
