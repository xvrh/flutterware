import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every git flutterware spawns must be immune to an inherited `GIT_DIR`.
///
/// A git hook exports `GIT_DIR` to everything it runs, and `GIT_DIR` overrides
/// git's directory discovery — the working directory and `-C` both lose to it.
/// So a bare `Process.run('git', …)` inside flutterware started from a hook
/// operates on the *hook's* repository: a consumer hit exactly this, and the
/// command that landed in the wrong repository was one that writes. The only
/// sanctioned spawn is `runGit`/`runGitTool` in `app/lib/src/utils/run_git.dart`,
/// which rebuilds the environment without the redirecting variables.
///
/// `gh` and `glab` are held to the same rule because they find their
/// repository by running git themselves.
///
/// A structural test, like `ambient_sdk_test.dart` and for the same reason: no
/// lint spells this, and reading source text catches the literal spawn — the
/// mistake that keeps coming back, one convenient `Process.run` at a time.
void main() {
  var root = Directory.current.path;

  /// What ships or runs for a consumer. `tool/` is deliberately out:
  /// `tool/format_pre_commit.dart` *is* a git hook, and inside a hook the
  /// inherited `GIT_DIR` names precisely the repository it should act on.
  var scanned = ['lib', 'bin', p.join('app', 'lib'), p.join('app', 'bin')];

  /// The one file allowed to spawn git: the helper everything else calls.
  var helper = p.join('app', 'lib', 'src', 'utils', 'run_git.dart');

  List<File> sources() => [
    for (var relative in scanned)
      if (Directory(p.join(root, relative)) case var dir when dir.existsSync())
        ...dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => p.relative(f.path, from: root) != helper),
  ];

  test('the directories this guards are actually there', () {
    for (var relative in [...scanned, helper]) {
      expect(
        FileSystemEntity.typeSync(p.join(root, relative)),
        isNot(FileSystemEntityType.notFound),
        reason: '$relative is missing — run this from the repo root',
      );
    }
  });

  test('nothing spawns git, gh or glab directly', () {
    var spawn = RegExp(
      r'''Process\.(run|start|runSync)\(\s*['"](git|gh|glab)['"]''',
    );
    var offenders = [
      for (var file in sources())
        if (spawn.firstMatch(file.readAsStringSync()) case var match?)
          '${p.relative(file.path, from: root)}: ${match.group(0)}',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Spawn git through runGit/runGitTool (app/lib/src/utils/run_git.dart) '
          'so a GIT_DIR leaked by a surrounding git hook cannot point the '
          'command at the wrong repository.',
    );
  });

  test('no git-running seam defaults to Process.run', () {
    // The subtler regression: the spawn itself is behind an injectable
    // `_run('git', …)`, and the default quietly goes back to `Process.run`.
    // A file that passes git (or a forge CLI) as an executable name has no
    // business mentioning Process.run/start at all — the helper covers both
    // shapes.
    var runsGit = RegExp(r'''\(\s*['"](git|gh|glab)['"]\s*,''');
    var rawSpawn = RegExp(r'''Process\.(run|start|runSync)\b''');
    var offenders = [
      for (var file in sources())
        if (file.readAsStringSync() case var text
            when runsGit.hasMatch(text) && rawSpawn.hasMatch(text))
          p.relative(file.path, from: root),
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'This file hands git to a process runner and also reaches for '
          'Process.run — default the seam to runGitTool '
          '(app/lib/src/utils/run_git.dart) instead, so the spawn stays '
          'immune to an inherited GIT_DIR.',
    );
  });
}
