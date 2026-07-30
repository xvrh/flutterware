import 'dart:io';

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
/// Deliberately separate from `bin/flutterware.dart`, which is the launcher and
/// is only ever reached through `dart run`. An earlier draft made one file
/// serve both roles and told them apart by whether `Isolate.resolvePackageUri`
/// returned null — a real signal, but an implicit one, where two files need no
/// signal at all. `executables:` decides what `dart install` installs;
/// `dart run <package>` resolves `bin/<package>.dart`. The two never meet.
Future<void> main(List<String> arguments) async {
  var root = findInitializedRoot(Directory.current);
  if (root == null) {
    stderr.writeln(noProjectMessage);
    exit(64);
  }

  var dart = '${root.path}/$sdkLinkPath/bin/dart';
  if (!File(dart).existsSync()) {
    stderr.writeln(
      'fw: $root/$sdkLinkPath does not lead to a Flutter SDK.\n'
      'It may point at an SDK that has been removed. Re-record it with:\n\n'
      '    dart run flutterware init',
    );
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
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await process.exitCode);
}
