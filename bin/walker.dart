import 'dart:io';

import 'package:flutterware/src/constants.dart';
import 'package:flutterware/src/walker.dart';

/// `fw` — installed globally by `dart install flutterware`, and nothing but a
/// redirect.
///
/// It finds the project, then runs **the command a user would have typed**:
///
///     fw status  ->  <sdk>/bin/dart run flutterware status
///
/// So `fw` and `dart run flutterware` are not two implementations kept in
/// agreement; they are one program, and `fw` only types it for you having
/// worked out which SDK to type it with.
///
/// **It is version-floating and carries no logic on purpose.** `dart install`
/// resolves whatever the installing SDK allows and nothing reinstalls it, so
/// this binary may be arbitrarily old. Everything version-sensitive lives on
/// the far side of the exec, in code JIT-compiled from the project's own
/// resolved sources moments earlier. Logic added here is logic that ages
/// independently of every project it is pointed at.
///
/// `--version` is the one thing it answers about itself, and it is the drift
/// above that makes the question worth asking: this binary and the package it
/// runs are two versions, and only this process knows the first one. It carries
/// its own number across the exec so the far side can print both, and answers
/// alone when there is no project to forward to.
///
/// Deliberately separate from `bin/flutterware.dart`, which is the launcher and
/// is only ever reached through `dart run`. An earlier draft made one file
/// serve both roles and told them apart by whether `Isolate.resolvePackageUri`
/// returned null — a real signal, but an implicit one, where two files need no
/// signal at all. `executables:` decides what `dart install` installs;
/// `dart run <package>` resolves `bin/<package>.dart`. The two never meet.
Future<void> main(List<String> arguments) async {
  // Carried across the exec so the far side can print both numbers. Only when
  // the line asks: nothing else has a use for it, and an environment variable
  // every child of every `fw` inherits is a wider contract than one question
  // needs.
  var environment = arguments.any(versionArguments.contains)
      ? {walkerVersionEnvironmentKey: flutterwareVersion}
      : const <String, String>{};

  // A committed wrapper outranks the recorded link: the repo that carries one
  // has pinned its whole toolchain, and the wrapper can resolve — and even
  // install — the SDK the link can only point at. The user's cwd is kept: the
  // wrapper's passthrough commands (`fw flutter test` inside `app/`) are
  // cwd-sensitive, and its fallthrough moves to the root by itself. Skipped
  // on Windows, where the wrapper is a shell script this process cannot exec.
  if (!Platform.isWindows) {
    var wrapper = findWrapper(Directory.current);
    if (wrapper != null) {
      var process = await Process.start(
        wrapper,
        arguments,
        environment: environment,
        mode: ProcessStartMode.inheritStdio,
      );
      exit(await process.exitCode);
    }
  }

  var root = findInitializedRoot(Directory.current);
  if (root == null) {
    // Help must not be gated on setup — it is how someone finds out what the
    // setup is. Anything else keeps the message: bare `fw` opens the GUI
    // inside a project, so outside one the setup steps are the honest answer.
    if (arguments.any(helpArguments.contains)) {
      stdout.writeln(noProjectHelp);
      exit(0);
    }
    // Neither is `--version`, and for a sharper reason: it is what somebody
    // types to find out whether `fw` is installed at all. Refusing it because
    // no project is set up withholds the diagnostic exactly where it is being
    // asked for.
    if (arguments.any(versionArguments.contains)) {
      stdout.writeln(noProjectVersion);
      exit(0);
    }
    stderr.writeln(noProjectMessage);
    exit(64);
  }

  var dart = '${root.path}/$sdkLinkPath/bin/dart';
  if (!File(dart).existsSync()) {
    stderr.writeln(brokenSdkMessage(root.path));
    exit(64);
  }

  // Run it from the project root, not from where the user is standing.
  //
  // `dart run <package>` has to be invoked from a package root: from a
  // subdirectory it resolves and runs the build hooks and only then fails with
  // `Could not find a file named "pubspec.yaml" in <cwd>`. Measured here from
  // `app/lib` and `examples/example/lib`; a package with no build hooks does
  // walk up, which is why this is easy to believe already works.
  //
  // Nothing is lost by moving: the session walks up to the repo root anyway —
  // one invocation per repo regardless of where it started — so the root is
  // where this was always going to end up.
  //
  // The child owns the terminal: a `flutter run` at the end of this chain
  // keeps its own interactive console, and output needs nothing to carry it.
  var process = await Process.start(
    dart,
    ['run', 'flutterware', ...arguments],
    workingDirectory: root.path,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await process.exitCode);
}
