/// Regenerates the screenshots `README.md` and the guides in `doc/` link to.
///
/// ```sh
/// fvm dart tool/screenshots.dart
/// ```
///
/// Named through fvm because the shots are taken with the `dart` that runs
/// this script: the one on PATH is older than the workspace floor.
///
/// Each shot is one `fw capture` against this checkout, at a fixed size,
/// density and theme so that re-running it produces byte-identical files and
/// an unchanged screenshot is an unchanged file. Measured: two runs with the
/// compiler daemon killed in between hash the same.
///
/// Everything is shot against the demo — see [brewline] — and the README's
/// hero and grid are drawn from those shots rather than taken: see [composed].
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the pictures go, relative to the repo root.
const outputDirectory = 'doc/screenshots';

/// Logical size and density every shot is taken at.
///
/// Not the window — `--size` forces the *layout*, so this is unaffected by
/// whatever display runs it, and 2x is what a README wants on a retina screen.
const defaultWidth = 1000;
const defaultHeight = 700;
const pixelRatio = 2;

/// The demo, **as a clone rather than as the directory it is developed in**.
///
/// `examples/brewline` cannot be photographed where it sits: the shell
/// addresses projects by *git worktree*, and the demo is a directory inside
/// this repository rather than a checkout of its own — so `fw` answers
/// `no worktree matches "brewline"`. The clone
/// `tool/publish_example.dart` maintains is a real repository, nested under
/// `build/` where git ignores it, and it opens as `~` like any main checkout.
///
/// That the pictures come from a clone of the published demo is the point
/// rather than a workaround: it is the project a reader gets, opened the way
/// they will open it.
///
/// Prepare it with:
///
/// ```sh
/// fvm dart tool/publish_example.dart --dry-run   # refresh the clone
/// cd build/flutterware_example && fvm flutter pub get
/// ```
///
/// The clone needs a `pubspec_overrides.yaml` pointing `flutterware` at this
/// checkout — its pubspec names the published version, which is not what these
/// pictures should show. [_ensureDemo] writes it.
const brewline = 'build/flutterware_example';
const brewlinePackage = '.';

class Shot {
  const Shot(
    this.name, {
    required this.path,
    required this.caption,
    this.project = brewline,
    this.height = defaultHeight,
    this.width = defaultWidth,
  });

  /// Which project the studio is opened on, relative to the repo root.
  ///
  /// **Almost everything is shot against the demo**, not against this
  /// repository. A reader meets flutterware through a project of their own, and
  /// a picture of *our* monorepo — sixteen plugins in the rail, three packages
  /// in every picker — is a picture of a case they do not have. The demo is one
  /// app with the tools an app declares, which is what the rail should look
  /// like the first time somebody sees it.
  ///
  /// It also settles the branch-name problem for free: flutterware names the
  /// worktree after the project directory, so these read `brewline` rather than
  /// whatever branch happened to take the picture.
  final String project;

  /// Wider than the default when the subject is wide.
  ///
  /// The scenario flow is the case: it fans out at every `split`, and the
  /// canvas opens at a fixed 0.5 with no fit-to-content, so the only way to
  /// show the shape of a run is to give it room.
  final int width;

  /// Taller than the default when the subject needs it.
  ///
  /// A catalog panel gives roughly half its height to the inspection pane, so
  /// a demo that is a tall column has much less room than the window suggests
  /// — and a demo that does not fit is drawn as Flutter's overflow banner,
  /// truthfully and unusably.
  final int height;

  /// File name under [outputDirectory], without the extension.
  final String name;

  /// Everything after `fw:///worktrees/<worktree>` — filled in per run, because
  /// only the checkout knows what its worktree is called.
  final String path;

  /// What the picture is of, for the README table.
  final String caption;

  String get file => '$outputDirectory/$name.png';
}

const shots = [
  Shot(
    'ui_catalog',
    path: '/flutterware.previews/$brewlinePackage/demo/shop.dart%23shopMenu',
    caption: 'Previews: a preview rendered in a live embedded engine.',
    height: 900,
  ),
  Shot(
    'ui_catalog_device',
    path: '/flutterware.previews/$brewlinePackage/demo/shop.dart%23shopDrink',
    caption: 'The same panel, on another screen of the same app.',
    // 3:2, the shape of its neighbour in the README's grid.
    width: 1050,
  ),
  // **Needs a run on disk**, because the panel draws the last one — and the
  // run has to be in *the clone*, which has its own build output. The
  // prerequisites, from `build/flutterware_example`, **in this order**:
  //
  // ```sh
  // dart run flutterware run scenarios run
  // dart run flutterware run translations export
  // dart run flutterware run store export
  // ```
  //
  // The translations export re-runs the scenarios, and a newer run leaves an
  // older store export drawn as dashed placeholders. Store last.
  //
  // Wide and tall, because the flow
  // fans out at the `split` and the canvas has no fit-to-content — a default
  // window shows two phones and a lot of nothing.
  Shot(
    'scenarios',
    path:
        '/flutterware.scenarios/$brewlinePackage/test/scenarios/'
        'shop_test.dart/Around%20the%20shop?zoom=0.22',
    caption: 'Scenarios: the flow a test drew, every path through the shop.',
    width: 1500,
    height: 1000,
  ),
  // The listing, drawn from what the export wrote — see the note above. An
  // unexported listing is a grid of dashed placeholders, which is what this
  // picture showed for a long time.
  Shot(
    'store_listing',
    path: '/flutterware.store',
    caption: "Store screenshots: the listing, from the app's own scenarios.",
    width: 1400,
    height: 900,
  ),
  // Also reads the scenario run above: which screen each string was asked for
  // on is recorded by the run, not found by searching the source.
  Shot(
    'translations',
    path: '/flutterware.translations',
    caption: 'Translations: every key, every language, and where it appears.',
    width: 1400,
    height: 900,
  ),
  // The three below illustrate the guides in `doc/`, not the README.
  Shot(
    'dependencies',
    path: '/flutterware.dependencies/$brewlinePackage',
    caption: 'Dependencies: every package, its version and where it came from.',
  ),
  Shot(
    'assets',
    path: '/flutterware.assets/$brewlinePackage',
    caption: 'Assets: every declared asset, with its densities and sizes.',
  ),
  Shot(
    'launcher_icon',
    path: '/flutterware.launcher_icon/$brewlinePackage',
    caption: 'Launcher icon: every icon, as each platform shows it.',
    height: 900,
  ),
];

Future<void> main(List<String> arguments) async {
  var only = arguments.where((a) => !a.startsWith('-')).toSet();
  var root = _repoRoot();
  _ensureDemo(root);

  // **The first shot rebuilds the GUI, always.** `fw capture` runs the built
  // binary and does not rebuild one that already exists, so without this a run
  // after any change to `app/` silently photographs the previous build — which
  // it did, and the pictures looked entirely plausible. Only the first: the
  // rest of the run wants the binary this one just produced.
  var rebuild = true;

  var failed = <String>[];
  for (var shot in shots) {
    if (only.isNotEmpty && !only.contains(shot.name)) continue;
    stdout.write('  ${shot.name.padRight(20)}');
    var cwd = p.join(root, shot.project);
    var result = await _capture(
      'fw:///worktrees/${await _worktreeName(cwd)}${shot.path}',
      p.join(root, shot.file),
      cwd: cwd,
      width: shot.width,
      height: shot.height,
      rebuild: rebuild,
    );
    rebuild = false;
    if (result case {'ok': true, 'width': var w, 'height': var h}) {
      stdout.writeln('${shot.file}  ${w}x$h');
    } else {
      stdout.writeln('FAILED  ${result['error'] ?? result}');
      failed.add(shot.name);
    }
  }

  // Last, because they are made of the shots above: preview entries in the
  // studio's own catalog that crop them.
  for (var picture in composed) {
    if (only.isNotEmpty && !only.contains(picture.name)) continue;
    stdout.write('  ${picture.name.padRight(20)}');
    var ok = await _render(root, picture);
    stdout.writeln(ok ? picture.file : 'FAILED');
    if (!ok) failed.add(picture.name);
  }

  if (failed.isNotEmpty) {
    stderr.writeln('\n${failed.length} failed: ${failed.join(', ')}');
    exit(1);
  }
  stdout.writeln('\nDone. Check `git status $outputDirectory`.');
}

/// The README's pictures that are not captures.
///
/// `app/tool/catalog/readme/hero.dart` draws them from the shots above — the
/// hero lays three of them out on one board, and each card crops one — so they
/// are only as current as those. Retake the shots first; a plain run does.
class Composed {
  const Composed(
    this.name,
    this.symbol, {
    required this.width,
    required this.height,
  });

  final String name;
  final String symbol;
  final int width;
  final int height;

  String get entry => 'tool/catalog/readme/hero.dart#$symbol';
  String get file => '$outputDirectory/$name.png';
}

const composed = [
  // 16:9 at the width of a README column on a 2x screen. The entry lays
  // itself out on a 1280-wide board and scales to this, so the size is free.
  Composed('hero', 'readmeHero', width: 2000, height: 1125),
  // 4:3, shown at half a column: 1200 is 2x of the widest that ever gets.
  Composed('card_previews', 'readmePreviewsCard', width: 1200, height: 900),
  Composed('card_scenarios', 'readmeScenariosCard', width: 1200, height: 900),
  Composed('card_store', 'readmeStoreCard', width: 1200, height: 900),
  Composed(
    'card_translations',
    'readmeTranslationsCard',
    width: 1200,
    height: 900,
  ),
  // Four exported App Store images side by side, for `doc/store_screenshots.md`.
  // Read from the clone's export rather than from a window shot.
  Composed('store_strip', 'readmeStoreStrip', width: 1600, height: 858),
];

Future<bool> _render(String root, Composed picture) async {
  var result = await Process.run(Platform.resolvedExecutable, [
    'run',
    'flutterware',
    'run',
    'previews',
    'screenshot',
    '--entry=${picture.entry}',
    '--width=${picture.width}',
    '--height=${picture.height}',
    '--output=${p.join(root, picture.file)}',
  ], workingDirectory: root);
  return result.exitCode == 0;
}

/// The name this checkout is known by in an address — the branch for a linked
/// worktree, `~` for the main one.
///
/// Read from git rather than passed in, so the script works in any checkout
/// without an argument nobody would remember.
Future<String> _worktreeName(String projectRoot) async {
  var main = await Process.run(
    'git',
    ['rev-parse', '--git-dir'],
    runInShell: true,
    workingDirectory: projectRoot,
  );
  // A linked worktree's git dir is `.git/worktrees/<name>`; the main
  // checkout's is plain `.git`, which addresses call `~`.
  var gitDir = (main.stdout as String).trim();
  var name = gitDir.contains('worktrees/')
      ? gitDir.split('worktrees/').last.trim()
      : '~';
  return name;
}

Future<Map<String, Object?>> _capture(
  String address,
  String output, {
  required String cwd,
  required int width,
  required int height,
  bool rebuild = false,
}) async {
  // The dart running this script, never the one on PATH: the SDK is whichever
  // one the invocation named, and a shot rendered by a different engine is a
  // diff nobody asked for.
  var result = await Process.run(
    Platform.resolvedExecutable,
    [
      'run',
      'flutterware',
      'capture',
      address,
      if (rebuild) '--force-compile',
      '--size=${width}x$height',
      '--pixel-ratio=$pixelRatio',
      '--theme=light',
      '--timeout=300',
      '-o',
      output,
    ],
    runInShell: true,
    workingDirectory: cwd,
  );

  // The GUI's report is the last JSON line; everything before it is whatever
  // the launcher and the engine had to say.
  for (var line in LineSplitter.split(
    result.stdout as String,
  ).toList().reversed) {
    if (!line.startsWith('{')) continue;
    try {
      return jsonDecode(line) as Map<String, Object?>;
    } on FormatException {
      continue;
    }
  }
  return {
    'ok': false,
    'error': 'no report from the GUI (exit ${result.exitCode})',
    'stderr': result.stderr,
  };
}

/// The repo root, anchored on this script rather than on cwd — every shot is
/// captured from a different working directory, so cwd says nothing.
String _repoRoot() {
  var dir = File.fromUri(Platform.script).parent;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    var parent = dir.parent;
    if (parent.path == dir.path) throw StateError('no pubspec.yaml above');
    dir = parent;
  }
}

/// The demo clone has to exist and has to resolve `flutterware` from here.
///
/// Checked rather than built: refreshing the clone is `publish_example`'s job
/// and `pub get` needs a Flutter SDK this script does not spawn. Failing with
/// the two commands is more use than failing inside `fw` with an address that
/// matches no worktree, which is what happened before this check existed.
void _ensureDemo(String root) {
  var dir = Directory(p.join(root, brewline));
  var resolved = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
  if (!dir.existsSync() || !resolved.existsSync()) {
    stderr.writeln(
      'The demo clone is not ready. Every shot is taken against it: a real\n'
      'checkout of the published demo, which is the\n'
      'only way the shell will address it.\n\n'
      '  fvm dart tool/publish_example.dart --dry-run\n'
      '  cd $brewline && fvm flutter pub get\n',
    );
    exit(1);
  }
  var override = File(p.join(dir.path, 'pubspec_overrides.yaml'));
  if (!override.existsSync()) {
    override.writeAsStringSync(
      '# Written by tool/screenshots.dart. The clone is the demo as a stranger\n'
      '# gets it, except that `flutterware` comes from the checkout taking the\n'
      '# pictures rather than from pub — so the shots show the code under\n'
      '# review. Re-run `flutter pub get` in the clone after this appears.\n'
      'dependency_overrides:\n'
      '  flutterware:\n'
      '    path: ../..\n',
    );
  }
}
