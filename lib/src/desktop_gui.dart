import 'dart:io';

import 'package:path/path.dart' as p;

import 'build_output.dart';

/// Where the built GUI is, and the one command that produces it.
///
/// In `package:flutterware` rather than beside `GuiLauncher` because two
/// processes need it. The launcher starts the build early, so it overlaps the
/// CLI's own build; `GuiLauncher` starts it every other time. Two copies of a
/// platform-specific path is how a 38-second build silently runs twice — which
/// is exactly what the overlap was added to avoid.
///
/// Pure Dart, like everything else the CLI links.
class DesktopGui {
  DesktopGui({required this.appPath, required this.flutterSdk});

  /// The `app/` directory the GUI is built from — the working copy under
  /// `~/.flutterware`, or the checkout itself when running in place.
  final String appPath;

  final String flutterSdk;

  String get flutter =>
      p.join(flutterSdk, 'bin', 'flutter${Platform.isWindows ? '.bat' : ''}');

  File get binary => File(p.join(appPath, _relativeBinaryPath()));

  /// Beside the artifact it explains rather than in the project: a failed build
  /// must not be the thing that creates `.flutterware/`.
  File get log => File(p.join(appPath, 'build', 'gui-build.log'));

  /// Runs `flutter build`, with its output in [log] rather than the terminal.
  ///
  /// Thirty-eight seconds of Xcode is identical on every successful run, so
  /// forwarding it spends the user's whole first impression on output nobody
  /// reads. What they need is that it started, roughly how long it takes, and —
  /// on the run that fails — the end of it.
  Future<ProcessLog> build({bool verbose = false}) => runLogged(
    flutter,
    ['build', Platform.operatingSystem, '--release'],
    workingDirectory: appPath,
    log: log,
    verbose: verbose,
  );

  String _relativeBinaryPath() {
    if (Platform.isWindows) {
      return p.join('build', 'windows', 'runner', 'Release', 'Flutterware.exe');
    } else if (Platform.isLinux) {
      return p.join(
        'build',
        'linux',
        _linuxHostPlatform(),
        'release',
        'bundle',
        'app',
      );
    }
    return p.join(
      'build',
      'macos',
      'Build',
      'Products',
      'Release',
      'app.app',
      'Contents',
      'MacOS',
      'app',
    );
  }

  static String _linuxHostPlatform() {
    var result = Process.runSync('uname', ['-m']);
    if (result.exitCode != 0) return 'x64';
    return result.stdout.toString().trim().endsWith('x86_64') ? 'x64' : 'arm64';
  }
}

/// The Flutter SDK containing [dartExecutable], or null.
///
/// The launcher's own case, and the reason this is not `FlutterSdkPath.tryFind`
/// from `flutterware_app`: the launcher cannot import that package, and it does
/// not need what that class does. It reached `main` through
/// `dart run flutterware`, so `Platform.resolvedExecutable` is
/// `<sdk>/bin/cache/dart-sdk/bin/dart` and the answer is three levels up.
String? findFlutterSdkRoot(String dartExecutable) {
  var directory = Directory(p.dirname(dartExecutable));
  while (true) {
    if (File(p.join(directory.path, 'bin', 'flutter')).existsSync() ||
        File(p.join(directory.path, 'bin', 'flutter.bat')).existsSync()) {
      return directory.path;
    }
    var parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

/// Set by the launcher when it built the GUI itself, to that build's exit code.
///
/// Absent means the launcher did not try, and `GuiLauncher` decides as it
/// always did. Present means the question is already answered, whichever way:
///
/// - **`0`** — do not build, even under `--force-compile`. The launcher has
///   just done it, and building again is the double build this key exists to
///   prevent.
/// - **anything else** — do not build either. Report it, from the log that is
///   already on disk. Reporting is what knows about `--json`, about the tail
///   and about which sink to use, and all of that lives in `GuiLauncher`; the
///   launcher would have to grow a second copy of it to say this itself.
const guiBuildResultEnvironmentKey = 'FW_GUI_BUILD_RESULT';
