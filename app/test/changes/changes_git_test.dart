import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_probe.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/ranking.dart';
import 'package:path/path.dart' as p;

/// Against **real git**, in real repositories built by the test.
///
/// The parsers get their own suite that needs no git. What needs a repository
/// is the pair of claims a fixture cannot make: that a file's byte slice really
/// is that file's patch, and that a stray `build/` really does stay one row.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw-changes-test'));
  tearDown(() => root.deleteSync(recursive: true));

  void git(List<String> arguments, {String? at}) {
    var result = Process.runSync('git', [
      '-c',
      'user.email=test@example.com',
      '-c',
      'user.name=Test',
      '-c',
      'commit.gpgsign=false',
      ...arguments,
    ], workingDirectory: at ?? root.path);
    if (result.exitCode != 0) {
      fail('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
  }

  void write(String path, String contents) {
    var file = File(p.join(root.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  group('a branch with committed and uncommitted work', () {
    setUp(() {
      git(['init', '-q', '-b', 'main', '.']);
      write('lib/kept.dart', 'one\ntwo\nthree\n');
      write('lib/gone.dart', 'delete me\n');
      write('lib/moved.dart', 'move me\nplease\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'init']);

      git(['checkout', '-q', '-b', 'feature']);
      write('lib/kept.dart', 'one\nTWO\nthree\n');
      write('lib/added.dart', 'brand new\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'committed work']);

      // …and then work the agent has not committed.
      File(p.join(root.path, 'lib/gone.dart')).deleteSync();
      git(['mv', 'lib/moved.dart', 'lib/elsewhere.dart']);
      write('lib/kept.dart', 'one\nTWO\nthree\nfour\n');
      write('scratch.txt', 'untracked\n');
    });

    test('the delta is committed and uncommitted together', () async {
      var set = await ChangesProbe().probe(root.path);

      expect(set.base, 'main');
      expect(set.baseSource, BaseSource.inferred);

      var byPath = {for (var f in set.changed) f.path: f};
      expect(
        byPath.keys,
        containsAll(['lib/kept.dart', 'lib/added.dart', 'lib/gone.dart']),
      );

      // Committed in the branch, and edited again since.
      expect(byPath['lib/kept.dart']!.status, ChangeStatus.modified);
      expect(set.uncommitted, contains('lib/kept.dart'));

      // Committed only — not in the uncommitted set.
      expect(byPath['lib/added.dart']!.status, ChangeStatus.added);
      expect(set.uncommitted, isNot(contains('lib/added.dart')));

      // Uncommitted only. A view keyed on commits would show none of this.
      expect(byPath['lib/gone.dart']!.status, ChangeStatus.deleted);
      expect(set.uncommitted, contains('lib/gone.dart'));

      expect(set.untracked.map((e) => e.path), ['scratch.txt']);
    });

    test('a rename survives to the model with both ends', () async {
      var set = await ChangesProbe().probe(root.path);
      var renamed = set.changed
          .where((f) => f.status == ChangeStatus.renamed)
          .toList();
      expect(renamed, hasLength(1));
      expect(renamed.single.path, 'lib/elsewhere.dart');
      expect(renamed.single.oldPath, 'lib/moved.dart');
    });

    test('deletions rank above bigger edits', () async {
      var set = await ChangesProbe().probe(root.path);
      expect(
        set.ranked.first.status,
        ChangeStatus.deleted,
        reason: 'a plain churn sort buries the line most worth seeing',
      );
    });

    /// The assertion that makes the whole lazy-slice architecture safe.
    /// If a byte offset is wrong, the screen renders one file's code under
    /// another file's name, and nothing else in the suite would notice.
    test("every file's slice is that file's patch", () async {
      var probe = ChangesProbe();
      var set = await probe.probe(root.path);
      expect(set.changed, isNotEmpty);

      for (var file in set.changed) {
        var sliced = set.patch.textFor(file).trim();
        var asked = (await probe.patchFor(
          root.path,
          file.path,
          range: set.mergeBase,
        ))!.trim();

        expect(
          sliced,
          asked,
          reason: 'the slice for ${file.path} is not what git says it is',
        );
      }
    });

    test('hunk positions and counts match the patch text', () async {
      var set = await ChangesProbe().probe(root.path);
      var kept = set.changed.firstWhere((f) => f.path == 'lib/kept.dart');

      for (var hunk in kept.hunks) {
        var text = set.patch.textForHunk(hunk);
        expect(text, startsWith('@@ -'));
        expect(
          text.split('\n').where((l) => l.startsWith('+')).length,
          hunk.added,
        );
        expect(
          text.split('\n').where((l) => l.startsWith('-')).length,
          hunk.removed,
        );
      }
    });
  });

  group('the branch-switch trap', () {
    /// The regression that matters most, because it is invisible on every
    /// developer's machine until it isn't: `.gitignore` is versioned. Build a
    /// package on one branch, switch to a branch without it, and the ignore
    /// rule leaves with the branch — the build output is now untracked *and*
    /// un-ignored.
    setUp(() {
      git(['init', '-q', '-b', 'main', '.']);
      write('README.md', 'root\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'init']);

      git(['checkout', '-q', '-b', 'feature']);
      write('packages/newpkg/pubspec.yaml', 'name: newpkg\n');
      write('packages/newpkg/.gitignore', 'build/\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'a new package']);

      // Build it. On this branch the package's own .gitignore covers this.
      for (var i = 0; i < 300; i++) {
        write('packages/newpkg/build/out/f$i.o', 'x');
      }

      // Now go back. The .gitignore was part of the package, on that branch.
      git(['checkout', '-q', 'main']);
    });

    test('a stray build directory is one row, and is never walked', () async {
      var set = await ChangesProbe().probe(root.path);

      expect(
        set.untracked,
        hasLength(1),
        reason: '300 files must not become 300 rows',
      );
      expect(set.untracked.single.isDirectory, isTrue);
      expect(set.untracked.single.path, startsWith('packages/'));
    });

    test(
      'and it stays one row when the package exists on both branches',
      () async {
        // The near-variant: the package is on main too, but its .gitignore is
        // not, so only `build/` is untracked.
        write('packages/newpkg/pubspec.yaml', 'name: newpkg\n');
        git(['add', 'packages/newpkg/pubspec.yaml']);
        git(['commit', '-qm', 'package on main, without its gitignore']);

        var set = await ChangesProbe().probe(root.path);
        expect(set.untracked, hasLength(1));
        expect(set.untracked.single.path, 'packages/newpkg/build/');
        expect(set.untracked.single.isDirectory, isTrue);
      },
    );
  });

  group('degenerate repositories', () {
    test('a repository with no commit lists what is there', () async {
      git(['init', '-q', '-b', 'main', '.']);
      write('first.dart', 'hello\n');

      var set = await ChangesProbe().probe(root.path);
      expect(set.head, isNull);
      expect(set.changed, isEmpty);
      expect(set.untracked.map((e) => e.path), ['first.dart']);
    });

    test(
      'no inferrable base says so and still shows the uncommitted work',
      () async {
        git(['init', '-q', '-b', 'topic', '.']);
        write('a.dart', 'one\n');
        git(['add', '-A']);
        git(['commit', '-qm', 'init']);
        write('a.dart', 'two\n');

        var set = await ChangesProbe().probe(root.path);
        expect(set.base, isNull);
        expect(set.baseSource, BaseSource.none);
        expect(set.changed.single.path, 'a.dart');
      },
    );

    test('a clean checkout of the base is empty, not an error', () async {
      git(['init', '-q', '-b', 'main', '.']);
      write('a.dart', 'one\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'init']);

      var set = await ChangesProbe().probe(root.path);
      expect(set.isEmpty, isTrue);
      expect(set.baseSource, BaseSource.inferred);
    });

    test('a project glob pins a real file in a real repository', () async {
      // The claim this suite exists for: not that `PathGlobSet` matches a
      // string, but that the paths git reports are the ones the rules see —
      // including one with a space in it, which every `-z` in the probe is for.
      git(['init', '-q', '-b', 'main', '.']);
      write('lib/api/client.dart', 'one\n');
      write('lib/my file.dart', 'one\n');
      write('lib/real.dart', 'one\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'init']);

      git(['checkout', '-q', '-b', 'feature']);
      write('lib/api/client.dart', 'one\ntwo\n');
      write('lib/my file.dart', 'one\ntwo\n');
      write('lib/real.dart', 'one\ntwo\n');

      var set = await ChangesProbe().probe(
        root.path,
        config: const ChangesConfig(attention: ['lib/api/**', '*file.dart']),
      );
      var byPath = {for (var it in set.ranking.files) it.file.path: it};
      expect(byPath['lib/api/client.dart']?.tier, RankTier.attention);
      expect(byPath['lib/api/client.dart']?.reason, 'matches lib/api/**');
      expect(byPath['lib/my file.dart']?.tier, RankTier.attention);
      // The one file no rule names is left alone, with nothing to explain.
      expect(byPath['lib/real.dart']?.tier, RankTier.ordinary);
      expect(byPath['lib/real.dart']?.reason, isNull);
    });

    test('the configured base overrides inference, and is reported', () async {
      git(['init', '-q', '-b', 'main', '.']);
      write('a.dart', 'one\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'init']);
      git(['checkout', '-q', '-b', 'develop']);
      write('a.dart', 'one\ntwo\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'on develop']);
      git(['checkout', '-q', '-b', 'feature']);
      write('b.dart', 'new\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'on feature']);

      // Against main, both files changed; against develop, only the new one.
      var inferred = await ChangesProbe().probe(root.path);
      expect(inferred.baseSource, BaseSource.inferred);
      expect(
        inferred.changed.map((f) => f.path),
        containsAll(['a.dart', 'b.dart']),
      );

      var configured = await ChangesProbe().probe(
        root.path,
        config: const ChangesConfig(base: 'develop'),
      );
      expect(configured.baseSource, BaseSource.configured);
      expect(configured.base, 'develop');
      expect(configured.changed.map((f) => f.path), ['b.dart']);
    });

    test('a path with a space round-trips through the scanner', () async {
      git(['init', '-q', '-b', 'main', '.']);
      write('with space.txt', 'a\n');
      write('café.txt', 'x\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'init']);
      write('with space.txt', 'a\nb\n');
      write('café.txt', 'x\ny\n');

      var set = await ChangesProbe().probe(root.path);
      expect(set.changed.map((f) => f.path).toSet(), {
        'with space.txt',
        'café.txt',
      });
    });
  });
}
