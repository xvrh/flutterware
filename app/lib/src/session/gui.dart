import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:flutterware/src/build_output.dart';
import 'package:path/path.dart' as p;

import '../constants.dart';

/// Builds the desktop GUI and runs it.
///
/// Lifted out of the old `app/bin/flutterware.dart`, which was a second
/// `CommandRunner` living beside [FwCli] and reachable only through the
/// launcher. Two entry points meant `dart run flutterware` could start the GUI
/// and could not reach `status` — so the GUI became a command like any other,
/// and that file went away.
///
/// Pure Dart on purpose: this is linked into `bin/fw.dart`, which
/// `entry_point_purity_test.dart` fails if it ever reaches `package:flutter`.
/// Starting the GUI is `Process.start`; nothing here needs a widget.
class GuiLauncher {
  GuiLauncher({
    required this.appToolPath,
    required this.flutterSdk,
    required this.projectDirectory,
    required this.out,
    required this.err,
    this.editableSources = false,
    this.json = false,
    bool? interactive,
  }) : interactive = interactive ?? outputIsInteractive;

  /// The `app/` directory the GUI is built from — the working copy under
  /// `~/.flutterware`, or the checkout itself when running in place.
  final String appToolPath;

  /// The Flutter SDK to build with. Passed in rather than discovered: this
  /// process is an AOT binary, so `Platform.resolvedExecutable` is *us* and
  /// walking up from it finds nothing.
  final String flutterSdk;

  final Directory projectDirectory;
  final StringSink out;
  final StringSink err;

  /// True when `app/` is the checkout being edited rather than a copy.
  final bool editableSources;

  /// Report a failed build as JSON on [out] instead of prose on [err].
  ///
  /// A build failure is the one thing here an agent cannot act on from a tail
  /// of Xcode output, and `--json` is already how every other command answers.
  final bool json;

  /// Whether the terminal is being watched. See [outputIsInteractive].
  final bool interactive;

  String get _flutter =>
      p.join(flutterSdk, 'bin', 'flutter${Platform.isWindows ? '.bat' : ''}');

  File get _binary => File(p.join(appToolPath, _exePathForPlatform()));

  /// Runs the GUI, hot either way it can be.
  ///
  /// Two modes, and the difference is not cosmetic:
  ///
  /// - **Editable sources** — `flutter run`, so a change is a keypress rather
  ///   than a 23-second rebuild. It also means nothing here has to decide
  ///   whether the binary is stale: `flutter run` owns that, and it is right.
  /// - **A copy** — build once and spawn the binary. There is nothing to
  ///   reload, and a user should get a release build.
  Future<int> run({bool forceBuild = false, bool release = false}) async {
    if (editableSources && !release) return _runHot();

    if (!_binary.existsSync() || forceBuild) {
      var code = await _build();
      if (code != 0) return code;
    }

    // The GUI inherits this terminal, so what it prints arrives without a
    // websocket to carry it. See the launcher for why that replaced
    // RemoteLogServer.
    var process = await Process.start(
      _binary.path,
      const [],
      environment: _guiEnvironment,
      workingDirectory: appToolPath,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }

  /// Hands the terminal to `flutter run`.
  ///
  /// [ProcessStartMode.inheritStdio] is the whole implementation of hot reload
  /// here: `flutter run` already has an interactive console — `r`, `R`, `q`,
  /// the DevTools URL — and giving it the terminal means every key works at
  /// full fidelity with nothing forwarding them. The launcher deliberately
  /// does not hold stdin, because two processes cannot both own it and the one
  /// that swallowed the `r` would make reload silently do nothing.
  ///
  /// Nothing is built on top of this. When we need reload to be *requested*
  /// rather than typed — an agent asking "apply my edit, tell me when the
  /// frame is ready" — this becomes `--machine` and a daemon client, and the
  /// only thing thrown away is the mode argument.
  Future<int> _runHot() async {
    out.writeln(
      'Starting the GUI with hot reload. Press r to reload, q to '
      'quit.',
    );
    var process = await Process.start(
      _flutter,
      ['run', '-d', Platform.operatingSystem],
      environment: _guiEnvironment,
      workingDirectory: appToolPath,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }

  Map<String, String> get _guiEnvironment => {
    projectDefineKey: projectDirectory.absolute.path,
    appToolPathKey: appToolPath,
    flutterSdkDefineKey: flutterSdk,
  };

  /// Builds the GUI, with the build's own output in a file rather than in the
  /// terminal.
  ///
  /// Twenty-three seconds of Xcode is identical on every successful run, so
  /// forwarding it spends the user's whole first impression on output nobody
  /// reads. What they need is that it started, roughly how long it takes, and —
  /// on the run that fails — the end of it.
  Future<int> _build() async {
    var log = File(p.join(appToolPath, 'build', 'gui-build.log'));
    var result =
        await Step(
          'Building the flutterware GUI',
          out: out,
          interactive: interactive,
          budget: const Duration(seconds: 25),
          note: 'first run only',
        ).run(
          () => runLogged(
            _flutter,
            ['build', Platform.operatingSystem, '--release'],
            workingDirectory: appToolPath,
            log: log,
          ),
          ok: (result) => result.ok,
        );

    if (result.ok) return 0;

    if (json) {
      out.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'error': 'gui_build_failed',
          'exitCode': result.exitCode,
          'log': log.path,
          'tail': result.tail(),
        }),
      );
    } else {
      describeFailure(err, 'the GUI build failed.', result);
    }
    return result.exitCode;
  }

  String _exePathForPlatform() {
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
    } else {
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
  }

  String _linuxHostPlatform() {
    var result = Process.runSync('uname', ['-m']);
    if (result.exitCode != 0) {
      err.writeln('fw: `uname -m` failed; assuming x64.');
      return 'x64';
    }
    return result.stdout.toString().trim().endsWith('x86_64') ? 'x64' : 'arm64';
  }
}
