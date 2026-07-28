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
    if (Link('${dir.path}/$sdkLinkPath').existsSync()) return dir;
    var parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// What to print when there is nothing to walk up to.
///
/// The case this exists for is not exotic — `.flutterware/` holds a
/// machine-specific path, so it is ignored, so it is **absent after every
/// clone for every teammate, forever**. The walker cannot fix that without
/// acquiring logic that would make it unsafe to freeze. So the message is the
/// fix, and it has to teach the rule rather than name a command: `fw` cannot
/// know your SDK until something running under it writes it down.
const noProjectMessage =
    '''
fw: no $sdkLinkPath in this directory or any parent.

The first run has to go through your own Flutter SDK, so flutterware can
record which one to use:

    dart run flutterware          (or: fvm dart run flutterware)

After that, `fw` works here and in every subdirectory.''';
