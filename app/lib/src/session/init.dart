import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../identity/face_guess.dart';
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
  ///
  /// Same question the walker asks: anything at the path counts, including a
  /// real directory copied in on a machine without symlinks.
  bool get isInitialized =>
      FileSystemEntity.typeSync(sdkLink.path, followLinks: false) !=
      FileSystemEntityType.notFound;

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
    // A real directory (or file) here is an SDK someone copied in on a machine
    // without symlinks. It is theirs to manage — replacing it with a link
    // would delete an SDK we did not write.
    var existing = FileSystemEntity.typeSync(sdkLink.path, followLinks: false);
    if (existing != FileSystemEntityType.link &&
        existing != FileSystemEntityType.notFound) {
      return p.relative(sdkLink.path, from: root);
    }

    var fvm = Link(p.join(root, '.fvm', 'flutter_sdk'));
    var target = fvm.existsSync() && _realPath(fvm.path) == _realPath(sdk.root)
        ? p.join('..', '.fvm', 'flutter_sdk')
        : sdk.root;

    // Leave an unchanged link alone. This runs before every command now, and
    // delete-then-create is a write where nothing has moved — briefly, a
    // window with no link at all.
    if (existing == FileSystemEntityType.link) {
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
  ///
  /// And the entry is *spliced in as text*, not re-encoded from the parsed map:
  /// see [_spliceServer].
  bool _registerMcpServer() {
    var file = File(p.join(root, mcpConfigFileName));

    // `fw` rather than an absolute path: the path would name this machine's
    // pub cache, and this file is committed.
    var entry = <String, Object?>{
      'command': 'fw',
      'args': ['mcp'],
    };

    if (!file.existsSync()) {
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'mcpServers': {'flutterware': entry},
        })}\n',
      );
      return true;
    }

    var source = file.readAsStringSync();
    Map<String, Object?> config;
    try {
      config = jsonDecode(source) as Map<String, Object?>;
    } on Object {
      return false;
    }

    var declared = config['mcpServers'];
    // Present but not an object: someone else's schema, or a typo. Either way
    // it is not ours to correct.
    if (declared != null && declared is! Map<String, Object?>) return false;
    var servers = declared as Map<String, Object?>?;
    if (servers != null && servers.containsKey('flutterware')) return false;

    var spliced = _spliceServer(source, entry);
    if (spliced != null) {
      file.writeAsStringSync(spliced);
      return true;
    }

    // The text was not the shape the parsed value promised — a comment, or
    // something else no scanner here knows about. Getting the entry in still
    // beats preserving the layout of a file we could not read closely.
    config['mcpServers'] = {...?servers, 'flutterware': entry};
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n',
    );
    return true;
  }

  /// Inserts `flutterware` into [source] as *text*, leaving every byte outside
  /// the insertion exactly where it was.
  ///
  /// Re-encoding the parsed map is one line shorter and rewrites the whole
  /// file: two spaces where the project used four, keys in a different order,
  /// a trailing newline appearing or leaving. The result is a diff touching
  /// every line of a file `init` does not own, to add one entry — and whoever
  /// reads that commit has to check by hand that nothing else moved.
  ///
  /// Returns null when the text is not the shape the parsed value promised, so
  /// the caller can fall back to re-encoding rather than skip the entry.
  static String? _spliceServer(String source, Map<String, Object?> entry) {
    var root = _skipWhitespace(source, 0);
    if (root >= source.length || source[root] != '{') return null;

    var servers = _memberValue(source, root + 1, 'mcpServers');
    if (servers == null) {
      return _insertMember(source, root, 'mcpServers', {'flutterware': entry});
    }
    if (source[servers] != '{') return null;
    return _insertMember(source, servers, 'flutterware', entry);
  }

  /// Splices `"name": value` into the object whose `{` is at [open], after the
  /// members already there — where every other tool that edits JSON in place
  /// puts a new key, and where anyone rereading the file looks for the thing
  /// that was added last.
  ///
  /// Laid out the way the file already lays itself out: the indent unit is read
  /// off the first member rather than assumed, because a project writing four
  /// spaces would otherwise get one two-space entry it did not ask for, and an
  /// object written on one line stays on one line.
  ///
  /// Returns null when the text does not walk the way valid JSON should.
  static String? _insertMember(
    String source,
    int open,
    String name,
    Object? value,
  ) {
    var close = _skipValue(source, open) - 1;
    var first = _skipWhitespace(source, open + 1);
    var isEmpty = first == close;
    // An empty object says nothing about how the file is written, so it
    // borrows the answer from whether anything else in the file has a line
    // break at all.
    var multiline = isEmpty
        ? source.contains('\n')
        : source.lastIndexOf('\n', close) > open;

    // Where the comma goes, and everything before it stays byte-identical.
    int? end;
    if (!isEmpty) {
      end = _lastMemberEnd(source, open + 1);
      if (end == null) return null;
    }

    if (!multiline) {
      var member = '${jsonEncode(name)}: ${jsonEncode(value)}';
      if (isEmpty) {
        return '${source.substring(0, open + 1)}$member'
            '${source.substring(close)}';
      }
      return '${source.substring(0, end!)}, $member${source.substring(end)}';
    }

    var parentIndent = _indentOfLineAt(source, open);
    var memberIndent = _indentOfLineAt(source, first);
    // Usable only if the first member actually starts its own line below the
    // brace, and sits further in than the object it belongs to.
    if (source.lastIndexOf('\n', first) <= open ||
        !memberIndent.startsWith(parentIndent) ||
        memberIndent.length <= parentIndent.length) {
      memberIndent = '$parentIndent  ';
    }

    var encoded = const LineSplitter().convert(
      JsonEncoder.withIndent(
        memberIndent.substring(parentIndent.length),
      ).convert({name: value}),
    );
    var member = encoded
        .sublist(1, encoded.length - 1)
        .map((line) => '$parentIndent$line')
        .join('\n');

    // An empty object has to grow lines around the entry; a populated one only
    // needs a comma on the line that used to be last.
    if (isEmpty) {
      return '${source.substring(0, open + 1)}\n$member\n$parentIndent'
          '${source.substring(close)}';
    }
    return '${source.substring(0, end!)},\n$member${source.substring(end)}';
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
${_identityLine(root)}
  fw.use(Dependencies(packages: [.new(app)]));

  // Renders the widgets you have annotated with `@Preview`, found anywhere in
  // the package — add `directory: 'demo'` to bound the scan.
  // `fw run previews new --name="Buttons"` writes your first one.
  fw.use(Previews(packages: [.new(app)]));

  // Widget tests that screenshot every step, found anywhere under `test/`.
  // `fw run scenarios new --name="Onboarding"` writes your first one.
  fw.use(Scenarios(packages: [.new(app)]));
});
''');
    return true;
  }
}

/// The `fw.identity(...)` the scaffold writes, with a guess already filled in.
///
/// **The guess belongs here and nowhere else.** Which package represents a
/// repository is a claim only its author can make — a monorepo holds several
/// real apps and no obvious answer — so inferring it at every launch would be a
/// rule nobody could see. Written into the config once, it is a starting point
/// somebody reads and corrects.
///
/// A repository where nothing has a real icon yet gets the line commented out:
/// there is nothing true to put in it, and an empty default teaches nobody that
/// the setting exists.
String _identityLine(String root) {
  const preamble =
      '  // Which package stands for this repository. Its launcher icon is what\n'
      '  // the window and the Dock show, so several checkouts open at once can\n'
      '  // be told apart.';
  var guessed = guessFacePackage(root);
  if (guessed == null) {
    return '$preamble Nothing here has a launcher icon of\n'
        '  // its own yet, so this is left for you to fill in.\n'
        "  // fw.identity(const ProjectIdentity(package: Pkg('.')));\n";
  }
  return '$preamble Guessed from the icons found\n'
      '  // here — change it if that is the wrong app.\n'
      "  fw.identity(const ProjectIdentity(package: Pkg('$guessed')));\n";
}

/// The leading whitespace of the line [offset] sits on.
String _indentOfLineAt(String source, int offset) {
  var start = source.lastIndexOf('\n', offset) + 1;
  var end = start;
  while (end < offset && (source[end] == ' ' || source[end] == '\t')) {
    end++;
  }
  return source.substring(start, end);
}

int _skipWhitespace(String source, int offset) {
  while (offset < source.length && ' \t\r\n'.contains(source[offset])) {
    offset++;
  }
  return offset;
}

/// Offset just past the string literal starting at [offset].
int _skipString(String source, int offset) {
  offset++;
  while (offset < source.length) {
    if (source[offset] == r'\') {
      offset += 2;
      continue;
    }
    if (source[offset] == '"') return offset + 1;
    offset++;
  }
  return offset;
}

/// Offset just past the value starting at [offset].
///
/// Only has to be right about already-valid JSON — whatever this walks has
/// been through [jsonDecode] — so it counts brackets rather than parsing, and
/// only strings need real handling because they can contain them.
int _skipValue(String source, int offset) {
  if (source[offset] == '"') return _skipString(source, offset);
  if (source[offset] != '{' && source[offset] != '[') {
    while (offset < source.length && !',}] \t\r\n'.contains(source[offset])) {
      offset++;
    }
    return offset;
  }

  var depth = 0;
  while (offset < source.length) {
    var char = source[offset];
    if (char == '"') {
      offset = _skipString(source, offset);
      continue;
    }
    if (char == '{' || char == '[') {
      depth++;
    } else if (char == '}' || char == ']') {
      depth--;
      if (depth == 0) return offset + 1;
    }
    offset++;
  }
  return offset;
}

/// Offset just past the value of the last member of the object whose body
/// starts at [body] — where a new member's comma goes.
///
/// Deliberately not the offset of the `}`: the whitespace between the two is
/// the file's own, and a new member belongs before it, not in place of it.
int? _lastMemberEnd(String source, int body) {
  int? end;
  var offset = _skipWhitespace(source, body);
  while (offset < source.length && source[offset] != '}') {
    if (source[offset] != '"') return null;
    offset = _skipWhitespace(source, _skipString(source, offset));
    if (offset >= source.length || source[offset] != ':') return null;

    end = _skipValue(source, _skipWhitespace(source, offset + 1));
    offset = _skipWhitespace(source, end);
    if (offset < source.length && source[offset] == ',') {
      offset = _skipWhitespace(source, offset + 1);
    }
  }
  return end;
}

/// Offset of the value of [key] in the object whose body starts at [body], or
/// null when the key is not there.
int? _memberValue(String source, int body, String key) {
  var offset = _skipWhitespace(source, body);
  while (offset < source.length && source[offset] != '}') {
    if (source[offset] != '"') return null;
    var nameEnd = _skipString(source, offset);
    var name = jsonDecode(source.substring(offset, nameEnd)) as String;

    offset = _skipWhitespace(source, nameEnd);
    if (offset >= source.length || source[offset] != ':') return null;
    offset = _skipWhitespace(source, offset + 1);
    if (name == key) return offset;

    offset = _skipWhitespace(source, _skipValue(source, offset));
    if (offset < source.length && source[offset] == ',') {
      offset = _skipWhitespace(source, offset + 1);
    }
  }
  return null;
}
