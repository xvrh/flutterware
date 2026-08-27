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

  File get binary => File(p.join(productDirectory.path, _relativeProduct().$2));

  /// What `flutter build` produces and what has to survive to run it: the
  /// `.app` bundle, the `Release` directory beside its DLLs, the Linux
  /// `bundle`. [binary] lives inside it.
  ///
  /// Named separately from [binary] because that is the difference between
  /// what runs and what is *kept*: `trimWorkingCopy` deletes everything beside
  /// this within `build/<platform>`, and on macOS the executable is four levels
  /// down inside the bundle it must not delete.
  Directory get productDirectory =>
      Directory(p.join(appPath, _relativeProduct().$1));

  /// Beside the artifact it explains rather than in the project: a failed build
  /// must not be the thing that creates `.flutterware/`.
  File get log => File(p.join(appPath, 'build', 'gui-build.log'));

  /// Runs `flutter build`, with its output in [log] rather than the terminal.
  ///
  /// Thirty-eight seconds of Xcode is identical on every successful run, so
  /// forwarding it spends the user's whole first impression on output they
  /// will not read. What they need is that it started, roughly how long it
  /// takes, and — on the run that fails — the end of it.
  Future<ProcessLog> build({bool verbose = false}) => runLogged(
    flutter,
    ['build', Platform.operatingSystem, '--release'],
    workingDirectory: appPath,
    log: log,
    verbose: verbose,
  );

  (String, String) _relativeProduct() =>
      relativeProduct(Platform.operatingSystem, linuxArch: _linuxHostPlatform);

  static String _linuxHostPlatform() {
    var result = Process.runSync('uname', ['-m']);
    if (result.exitCode != 0) return 'x64';
    return result.stdout.toString().trim().endsWith('x86_64') ? 'x64' : 'arm64';
  }
}

/// The product directory relative to an `app/`, and the executable relative to
/// *it*. One switch rather than two, so the two answers cannot drift.
///
/// Top-level and taking [operatingSystem] so all three answers are reachable
/// from one machine. Development happens on macOS and CI's only Linux job runs
/// a previews audit rather than this suite, so the Windows and Linux literals
/// are otherwise unexecuted anywhere — and `trimWorkingCopy` now decides what
/// to keep from the first half of this pair.
///
/// [linuxArch] is a callback because it shells out to `uname`, which the other
/// two platforms must not pay for and a test cannot answer for.
(String, String) relativeProduct(
  String operatingSystem, {
  required String Function() linuxArch,
}) => switch (operatingSystem) {
  'windows' => (
    p.join('build', 'windows', 'runner', 'Release'),
    'Flutterware.exe',
  ),
  // BINARY_NAME, set in linux/CMakeLists.txt. Lowercase where the other two
  // are capitalised, because that is what a Linux executable looks like.
  'linux' => (
    p.join('build', 'linux', linuxArch(), 'release', 'bundle'),
    'flutterware',
  ),
  // Both spellings are PRODUCT_NAME, set in macos/Runner/Configs/AppInfo.xcconfig.
  _ => (
    p.join('build', 'macos', 'Build', 'Products', 'Release', 'Flutterware.app'),
    p.join('Contents', 'MacOS', 'Flutterware'),
  ),
};

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
