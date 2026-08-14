import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// **The SDK is the one the invocation named, and nothing may reach past it.**
///
/// `dart run flutterware` arrives through the user's own `dart` — fvm, mise,
/// asdf, or a path they typed — and that choice is the whole answer. A spawn of
/// bare `dart` or `flutter` resolves through `PATH` instead, which is a
/// *different* SDK as often as not: measured on one machine, `PATH` dart was
/// 3.12.1 against a package floor of `^3.13.0-0`. The failure it produces is
/// not a clean one either — a build half-done by another engine, or a pub error
/// naming a version nobody chose.
///
/// A structural test rather than a lint because no lint spells this, and
/// because the rule is about *this* repo's contract rather than about style.
/// It reads source text, so it catches the literal spawn and not a name reached
/// some other way — the common mistake, and the one that keeps coming back
/// after a rebase.
void main() {
  var root = Directory.current.path;

  /// Everything that ships or runs as tooling. `test/` is deliberately out:
  /// a process test has to resolve a real `dart` for itself, because under
  /// `flutter test` `Platform.resolvedExecutable` is `flutter_tester`.
  var scanned = [
    'lib',
    'bin',
    'tool',
    p.join('app', 'lib'),
    p.join('app', 'bin'),
  ];

  List<File> sources() => [
    for (var relative in scanned)
      if (Directory(p.join(root, relative)) case var dir when dir.existsSync())
        ...dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
  ];

  test('the directories this guards are actually there', () {
    // Without this the whole file passes by scanning nothing, which is how a
    // guard dies silently when a path moves.
    for (var relative in scanned) {
      expect(
        Directory(p.join(root, relative)).existsSync(),
        isTrue,
        reason: '$relative is missing — run this from the repo root',
      );
    }
  });

  test('nothing spawns a dart or flutter off PATH', () {
    var spawn = RegExp(r'''Process\.(run|start)\(\s*['"](dart|flutter)['"]''');
    var offenders = [
      for (var file in sources())
        if (spawn.firstMatch(file.readAsStringSync()) case var match?)
          '${p.relative(file.path, from: root)}: ${match.group(0)}',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Spawn the SDK that started this process — `Platform.resolvedExecutable`, '
          'or a resolved `FlutterSdkPath` — rather than a name off PATH.',
    );
  });

  test('nothing reads FLUTTER_HOME', () {
    // It describes the machine, never the project, and it was the last rung of
    // a discovery ladder that no longer exists.
    var read = RegExp(r'''\[['"]FLUTTER_HOME['"]\]''');
    var offenders = [
      for (var file in sources())
        if (read.hasMatch(file.readAsStringSync()))
          p.relative(file.path, from: root),
    ];

    expect(offenders, isEmpty);
  });
}
