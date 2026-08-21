/// Regenerates the screenshots `README.md` links to.
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
/// Run it from the branch the images will be committed on. The window
/// shows the worktree's branch in its tab and address bar, so a shot taken on
/// a feature branch says so, in the README, forever.
///
/// The subjects are deliberately the sample project rather than flutterware's
/// own packages: `examples/example` is what a user with a single Flutter app
/// sees, and that is what the README is describing.
///
/// One shot per feature, and none of the shell on its own: the tabs, the rail
/// and the address bar are in every picture below, and the overview screen by
/// itself is a worktree name and two chips. `doc/screenshots/shell.png` is
/// still the hand-taken one — and so is `server.png`: it needs a live
/// instrumented server with traffic, and its pids, timestamps and timings
/// make byte-identical output impossible, which is this script's contract.
/// To retake it: run `examples/example/bin/example_server.dart`, curl
/// `/users` and `/slow`, then `fw capture` the request-detail address.
library;

import 'dart:convert';
import 'dart:io';

/// Where the pictures go, relative to the repo root.
const outputDirectory = 'doc/screenshots';

/// Logical size and density every shot is taken at.
///
/// Not the window — `--size` forces the *layout*, so this is unaffected by
/// whatever display runs it, and 2x is what a README wants on a retina screen.
const width = 1000;
const defaultHeight = 700;
const pixelRatio = 2;

/// The sample package, as one address segment. The `/` is escaped because a
/// package path is a single segment; see `catalogSegments`.
const examplePackage = 'examples%2Fexample';

class Shot {
  const Shot(
    this.name, {
    required this.path,
    required this.caption,
    this.height = defaultHeight,
  });

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
  // Taller than the rest on purpose: nine buttons in a column overflow the
  // default panel once the inspection pane has taken the lower half, and the
  // picture becomes Flutter's yellow overflow banner. The alternative was a
  // shorter demo, but the example app's home page is a test fixture — marker
  // text and all — and looks broken in a README.
  Shot(
    'ui_catalog',
    path: '/flutterware.previews/$examplePackage/demo/buttons.dart%23buttons',
    caption: 'Previews: a preview rendered in a live embedded engine.',
    height: 900,
  ),
  Shot(
    'ui_catalog_device',
    path:
        '/flutterware.previews/$examplePackage/demo/'
        'home_page.dart%23homePageMobile',
    caption: 'The same panel, with a preview that pins its own phone canvas.',
  ),
  Shot(
    'dependencies',
    path: '/flutterware.dependencies/$examplePackage',
    caption: "Dependencies: what the project depends on, and what's outdated.",
  ),
  Shot(
    'assets',
    path: '/flutterware.assets/$examplePackage',
    caption: 'Assets: every declared asset, with its densities and sizes.',
  ),
  // Tall, because the point of this panel is *how many* surfaces one config
  // turns into. At the default height the grid is three across and the second
  // row is sliced in half, which shows a splash screen rather than the reason
  // the plugin exists.
  Shot(
    'splash',
    path: '/flutterware.splash/$examplePackage',
    caption: 'Splash screen: what flutter_native_splash actually produces.',
    height: 1200,
  ),
];

Future<void> main(List<String> arguments) async {
  var only = arguments.where((a) => !a.startsWith('-')).toSet();
  var worktree = await _worktreeName();
  stdout.writeln('Capturing from worktree "$worktree".');

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
    var result = await _capture(
      'fw:///worktrees/$worktree${shot.path}',
      shot.file,
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

  if (failed.isNotEmpty) {
    stderr.writeln('\n${failed.length} failed: ${failed.join(', ')}');
    exit(1);
  }
  stdout.writeln('\nDone. Check `git status $outputDirectory`.');
}

/// The name this checkout is known by in an address — the branch for a linked
/// worktree, `~` for the main one.
///
/// Read from git rather than passed in, so the script works in any checkout
/// without an argument nobody would remember.
Future<String> _worktreeName() async {
  var main = await Process.run('git', [
    'rev-parse',
    '--git-dir',
  ], runInShell: true);
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
  required int height,
  bool rebuild = false,
}) async {
  // The dart running this script, never the one on PATH: the SDK is whichever
  // one the invocation named, and a shot rendered by a different engine is a
  // diff nobody asked for.
  var result = await Process.run(Platform.resolvedExecutable, [
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
  ], runInShell: true);

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
