import 'dart:io';

/// Where a project records which Flutter SDK it uses, relative to its root.
///
/// **This path is the one permanently frozen thing in the whole design.** The
/// global `fw` is installed once and never refreshed, so it may be years older
/// than the project it is pointed at; it is safe to freeze precisely because
/// this name and `dart run flutterware` are the sum of what it knows. Anything
/// else — the artifact layout, the freshness check, what the launcher does
/// after it starts — lives on the far side of that exec and may move freely.
const sdkLinkPath = '.flutterware/sdk';

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
/// the two frozen facts: [sdkLinkPath] and `dart run flutterware`.
const noProjectHelp =
    '''
fw — runs flutterware commands in the nearest set-up project.

`fw <command>` walks up to the project that recorded a Flutter SDK in
$sdkLinkPath, then runs `dart run flutterware <command>` with that
SDK. The commands live in the project's own flutterware version, so
`fw help` inside a set-up project lists them.

No project is set up here yet.

$_setup''';

/// What to print when [sdkLinkPath] exists but no longer leads to an SDK.
String brokenSdkMessage(String rootPath) =>
    'fw: $rootPath/$sdkLinkPath does not lead to a Flutter SDK.\n'
    'It may point at an SDK that has been moved or removed. Re-record it '
    'with:\n'
    '\n'
    '    dart run flutterware init     (or: fvm dart run flutterware init)';
