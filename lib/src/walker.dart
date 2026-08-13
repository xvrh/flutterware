import 'dart:io';

import 'constants.dart';

/// Where a project records which Flutter SDK it uses, relative to its root.
///
/// **This path is one of the three permanently frozen facts in the whole
/// design** — the others being [wrapperMarker] and `dart run flutterware`.
/// The global `fw` is installed once and never refreshed, so it may be years
/// older than the project it is pointed at; it is safe to freeze precisely
/// because those three names are the sum of what it knows. Anything else —
/// the artifact layout, the freshness check, what the launcher or the wrapper
/// does after it starts — lives on the far side of an exec and may move
/// freely.
const sdkLinkPath = '.flutterware/sdk';

/// The marker line a committed `fw` wrapper script carries — what lets the
/// walker tell flutterware's wrapper from any other executable that happens
/// to be named `fw`.
///
/// A prefix, not a full line: the wrapper's own line ends in a version
/// (`# flutterware wrapper v1`), and the version belongs to the script, not
/// to this contract.
const wrapperMarker = '# flutterware wrapper';

/// Walks up from [start] for a committed `fw` wrapper script.
///
/// Returns its absolute path, or null. Checked before [findInitializedRoot]:
/// a repo that commits the wrapper has pinned its whole toolchain, and the
/// wrapper resolves the SDK better than the recorded link does — it can even
/// install it. A file named `fw` without [wrapperMarker] is someone else's
/// and is skipped, ancestors included.
String? findWrapper(Directory start) {
  var dir = start.absolute;
  while (true) {
    var candidate = File('${dir.path}/fw');
    if (_isWrapper(candidate)) return candidate.path;
    var parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

bool _isWrapper(File file) {
  if (file.statSync().type != FileSystemEntityType.file) return false;
  try {
    var handle = file.openSync();
    try {
      // The marker sits on line 2; 256 bytes reaches it in any wrapper
      // version without reading a whole file that turns out to be a binary.
      return String.fromCharCodes(handle.readSync(256)).contains(wrapperMarker);
    } finally {
      handle.closeSync();
    }
  } on FileSystemException {
    return false;
  }
}

/// Walks up from [start] for a project that has been initialized.
///
/// Returns the directory holding [sdkLinkPath], or null. Deliberately not
/// "find a pubspec" or "find a .git": the question is not *is this a project*
/// but *has this project recorded an SDK*, and only the second one can be
/// answered without guessing.
Directory? findInitializedRoot(Directory start) {
  var dir = start.absolute;
  while (true) {
    // Anything at the path counts — normally a symlink, but a real directory
    // happens too (an SDK copied in on a machine that couldn't symlink), and a
    // dangling link still means "recorded"; the bin reports that separately.
    var type = FileSystemEntity.typeSync(
      '${dir.path}/$sdkLinkPath',
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound) return dir;
    var parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// The spellings that ask for help.
///
/// Checked against every argument, not just the first: the CLI takes its
/// global flags anywhere in the line (`fw -v help` works inside a project),
/// and the walker cannot strip flags it does not know without acquiring
/// logic that ages.
const helpArguments = {'help', '--help', '-h'};

/// The spellings that ask which flutterware this is.
///
/// No `-v`: that is `--verbose`, which every command already takes.
const versionArguments = {'version', '--version'};

/// What the global `fw` says about itself when there is no project to forward
/// to.
///
/// The one version-sensitive thing the walker is allowed to carry, and it does
/// not violate the rule the library doc states: [flutterwareVersion] compiled
/// in here describes *this binary*, which cannot go stale the way a copy of
/// somebody else's behaviour would. It is also the reason the question is worth
/// asking — this binary is installed once and never refreshed, while the code
/// it runs comes from the project, so the two drift apart by design and
/// "which flutterware am I talking to" has two answers.
const noProjectVersion =
    '''
fw $flutterwareVersion — the global walker.

Commands run the flutterware the *project* resolved, which is a different
version from this one as often as not. No project is set up here, so there is
nothing to report but this binary.

$_setup''';

/// The setup steps, shared by every message that has to teach them.
const _setup = '''
The first run has to go through your own Flutter SDK, so flutterware can
record which one to use. From the project root:

    dart pub add flutterware      (skip if pubspec.yaml already has it)
    dart run flutterware          (or: fvm dart run flutterware)

After that, `fw` works here and in every subdirectory.''';

/// What to print when there is nothing to walk up to.
///
/// The case this exists for is not exotic — `.flutterware/` holds a
/// machine-specific path, so it is ignored, so it is **absent after every
/// clone for every teammate, forever**. The walker cannot fix that without
/// acquiring logic that would make it unsafe to freeze. So the message is the
/// fix, and it has to teach the rule rather than name a command: `fw` cannot
/// know your SDK until something running under it writes it down.
const noProjectMessage = '''
fw: no project set up for fw in this directory or any parent.

$_setup''';

/// What `fw help` prints when there is no project to forward it to.
///
/// Everything version-sensitive — including the command list — lives on the
/// far side of the exec, so this can only describe the redirect itself and
/// the frozen facts: the committed wrapper, [sdkLinkPath], and
/// `dart run flutterware`.
const noProjectHelp =
    '''
fw — runs flutterware commands in the nearest set-up project.

`fw <command>` runs the project's committed `fw` wrapper when one
exists; otherwise it walks up to the project that recorded a Flutter
SDK in $sdkLinkPath, then runs `dart run flutterware <command>` with
that SDK. The commands live in the project's own flutterware version,
so `fw help` inside a set-up project lists them.

No project is set up here yet.

$_setup''';

/// What to print when [sdkLinkPath] exists but no longer leads to an SDK.
String brokenSdkMessage(String rootPath) =>
    'fw: $rootPath/$sdkLinkPath does not lead to a Flutter SDK.\n'
    'It may point at an SDK that has been moved or removed. Re-record it '
    'with:\n'
    '\n'
    '    dart run flutterware init     (or: fvm dart run flutterware init)';
