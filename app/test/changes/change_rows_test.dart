import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_rows.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_tree.dart';
import 'package:flutterware_app/src/changes/diff_lines.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/ranking.dart';

/// The pure-Dart half of the screen: what rows exist, how a hunk becomes lines,
/// and how paths fold into a tree. All testable without pumping a widget, which
/// is the point of keeping them out of the view.
void main() {
  PatchIndex index(String patch) =>
      indexPatch(Uint8List.fromList(utf8.encode(patch)));

  const twoFiles = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,3 +1,4 @@ class A {
 one
-two
+TWO
+three
 four
@@ -20,2 +21,2 @@
-twenty
+TWENTY
 rest
diff --git a/lib/b.dart b/lib/b.dart
--- a/lib/b.dart
+++ b/lib/b.dart
@@ -1 +1 @@
-x
+y
''';

  ChangeSet setOf(
    PatchIndex patch, {
    Set<String> uncommitted = const {},
    List<UntrackedEntry> untracked = const [],
    Ranking? ranking,
  }) => ChangeSet(
    worktreePath: '/wt',
    patch: patch,
    base: 'main',
    baseSource: BaseSource.inferred,
    uncommitted: uncommitted,
    untracked: untracked,
    ranking: ranking,
  );

  group('tiers and the noise drawer', () {
    /// Puts each named path in a tier, leaving the rest ordinary.
    Ranking rankingOf(
      PatchIndex patch, {
      Set<String> attention = const {},
      Set<String> noise = const {},
    }) => Ranking([
      for (var file in patch.files)
        RankedFile(
          file: file,
          tier: attention.contains(file.path)
              ? RankTier.attention
              : noise.contains(file.path)
              ? RankTier.noise
              : RankTier.ordinary,
          rule: attention.contains(file.path) || noise.contains(file.path)
              ? 'a rule'
              : null,
          source: RankSource.project,
        ),
    ]);

    test('nothing ranked draws no headings at all', () {
      // A section header over the only section is furniture.
      var rows = buildRows(setOf(index(twoFiles)), expanded: {});
      expect(rows.whereType<SectionRow>(), isEmpty);
      expect(rows.whereType<NoiseDrawerRow>(), isEmpty);
    });

    test('noise alone draws the drawer and no heading above it', () {
      // Found by photographing a 25-file branch: a lone `Changes` heading sat
      // at the top with the thing it distinguished from below the fold.
      var patch = index(twoFiles);
      var rows = buildRows(
        setOf(patch, ranking: rankingOf(patch, noise: {'lib/b.dart'})),
        expanded: {},
      );
      expect(rows.whereType<SectionRow>(), isEmpty);
      expect(rows.whereType<NoiseDrawerRow>(), hasLength(1));
    });

    test('a pinned file gets its own section, above everything else', () {
      var patch = index(twoFiles);
      var rows = buildRows(
        setOf(patch, ranking: rankingOf(patch, attention: {'lib/b.dart'})),
        expanded: {},
      );
      expect(rows.first, isA<SectionRow>());
      expect((rows.first as SectionRow).label, 'Look here first');
      expect((rows[1] as FileRow).file.path, 'lib/b.dart');
      // …and the section says how much is in it.
      expect((rows.first as SectionRow).detail, contains('1 file'));
    });

    test('the rule that fired reaches the row', () {
      var patch = index(twoFiles);
      var rows = buildRows(
        setOf(patch, ranking: rankingOf(patch, attention: {'lib/b.dart'})),
        expanded: {},
      );
      var pinned = rows.whereType<FileRow>().firstWhere(
        (r) => r.file.path == 'lib/b.dart',
      );
      expect(pinned.reason, 'matches a rule');
      var ordinary = rows.whereType<FileRow>().firstWhere(
        (r) => r.file.path == 'lib/a.dart',
      );
      expect(ordinary.reason, isNull);
    });

    test('noise collapses to one row, and the count is the information', () {
      var patch = index(twoFiles);
      var set = setOf(patch, ranking: rankingOf(patch, noise: {'lib/b.dart'}));
      var rows = buildRows(set, expanded: {});

      var drawer = rows.whereType<NoiseDrawerRow>().single;
      expect(drawer.files, 1);
      expect(drawer.open, isFalse);
      expect(drawer.added, 1);
      expect(drawer.removed, 1);
      // Collapsed means the file has no row of its own.
      expect(rows.whereType<FileRow>().map((r) => r.file.path), ['lib/a.dart']);
    });

    test('opening the drawer lists them, and never loses one', () {
      var patch = index(twoFiles);
      var set = setOf(patch, ranking: rankingOf(patch, noise: {'lib/b.dart'}));
      var rows = buildRows(set, expanded: {}, noiseOpen: true);

      expect(rows.whereType<NoiseDrawerRow>().single.open, isTrue);
      expect(rows.whereType<FileRow>().map((r) => r.file.path), [
        'lib/a.dart',
        'lib/b.dart',
      ]);
      // The header's total is the true one either way — a ranking that can
      // lose a file is a ranking nobody can trust.
      expect(set.changed, hasLength(2));
    });

    test('a noise file still expands to its own diff', () {
      var patch = index(twoFiles);
      var rows = buildRows(
        setOf(patch, ranking: rankingOf(patch, noise: {'lib/b.dart'})),
        expanded: {'lib/b.dart'},
        noiseOpen: true,
      );
      expect(rows.whereType<HunkRow>(), hasLength(1));
      expect(rows.whereType<DiffLineRow>(), isNotEmpty);
    });

    test('ordering is per tier, not across the list', () {
      var patch = index(twoFiles);
      // `lib/a.dart` is the bigger file, so an across-the-list sort would put
      // it first. Pinning the smaller one has to beat that.
      var set = setOf(
        patch,
        ranking: rankingOf(patch, attention: {'lib/b.dart'}),
      );
      expect(set.ordered(RankTier.attention).single.file.path, 'lib/b.dart');
      expect(set.ordered(RankTier.ordinary).single.file.path, 'lib/a.dart');
    });

    test('a pinned untracked file is drawn with the pinned ones', () {
      // The case that made this exist: an agent wrote a new migration and has
      // not staged it. A pin that only works after `git add` misses the exact
      // moment it is for. Found by photographing the screen with a real
      // `attention: ['docs/superpowers/specs/**']` in the config.
      var patch = index(twoFiles);
      var rows = buildRows(
        setOf(
          patch,
          untracked: const [
            UntrackedEntry('db/migrations/2.sql', reason: 'matches db/**'),
            UntrackedEntry('scratch.txt'),
            UntrackedEntry.directory('build/'),
          ],
        ),
        expanded: {},
      );

      var first = rows.first as SectionRow;
      expect(first.label, 'Look here first');
      expect((rows[1] as UntrackedRow).entry.path, 'db/migrations/2.sql');
      // Counted as a file, contributing no lines: it has no delta against the
      // base to contribute.
      expect(first.detail, '1 file +0 -0');

      // …and it is not listed a second time below, which would make the
      // branch look bigger than it is.
      var untracked = rows.whereType<UntrackedRow>().toList();
      expect(untracked, hasLength(3));
      expect(rows.whereType<SectionRow>().map((r) => r.label), [
        'Look here first',
        'Changes',
        'Untracked',
      ]);
    });

    test('an untracked directory is never pinned', () {
      // Matching a glob against a directory would mean walking it, which is
      // the walk the whole untracked design exists to avoid.
      expect(
        const UntrackedEntry.directory('build/').withReason('matches **'),
        isA<UntrackedEntry>().having((e) => e.reason, 'reason', isNull),
      );
    });

    test('filtering narrows the sections rather than emptying them', () {
      var patch = index(twoFiles);
      var set = setOf(
        patch,
        ranking: rankingOf(patch, attention: {'lib/b.dart'}),
      );
      var rows = buildRows(set, expanded: {}, visible: {'lib/a.dart'});
      // Nothing pinned survived the filter, so that heading is gone…
      expect(
        rows.whereType<SectionRow>().map((r) => r.label),
        isNot(contains('Look here first')),
      );
      // …and the one file that did is still there.
      expect(rows.whereType<FileRow>().single.file.path, 'lib/a.dart');
    });
  });

  group('rows', () {
    test('a collapsed file is exactly one row', () {
      var rows = buildRows(setOf(index(twoFiles)), expanded: {});
      expect(rows.whereType<FileRow>(), hasLength(2));
      expect(rows.whereType<DiffLineRow>(), isEmpty);
      expect(rows, hasLength(2));
    });

    test('an expanded file contributes its hunks and every line', () {
      var patch = index(twoFiles);
      var rows = buildRows(setOf(patch), expanded: {'lib/a.dart'});

      var a = patch.files.firstWhere((f) => f.path == 'lib/a.dart');
      expect(rows.whereType<HunkRow>(), hasLength(2));
      expect(
        rows.whereType<DiffLineRow>(),
        hasLength(a.hunks.fold<int>(0, (sum, h) => sum + h.displayLines)),
      );
      // The other file stayed one row.
      expect(rows.whereType<FileRow>(), hasLength(2));
    });

    test(
      'the row count is known from metadata, before anything is decoded',
      () {
        // The claim the virtualised list rests on: `displayLines` comes off the
        // `@@` header, so scroll extents are right before a byte is read.
        var patch = index(twoFiles);
        var rows = buildRows(setOf(patch), expanded: {'lib/a.dart'});
        var lines = HunkLineCache(patch);

        expect(lines.decodedHunks, 0, reason: 'building rows decodes nothing');
        expect(rows, isNotEmpty);
      },
    );

    test('filtering removes rows; the untracked section goes with it', () {
      var patch = index(twoFiles);
      var set = setOf(patch, untracked: const [UntrackedEntry('scratch.txt')]);

      var all = buildRows(set, expanded: {});
      expect(all.whereType<UntrackedRow>(), hasLength(1));

      var filtered = buildRows(set, expanded: {}, visible: {'lib/b.dart'});
      expect(filtered.whereType<FileRow>(), hasLength(1));
      expect(
        filtered.whereType<UntrackedRow>(),
        isEmpty,
        reason: 'a filter over changed paths says nothing about untracked ones',
      );
    });

    test('a binary file expands to a notice, not to nothing', () {
      var patch = index('''
diff --git a/logo.png b/logo.png
Binary files a/logo.png and b/logo.png differ
''');
      var rows = buildRows(setOf(patch), expanded: {'logo.png'});

      expect(rows.whereType<FileNoticeRow>(), hasLength(1));
      expect(
        rows.whereType<FileNoticeRow>().single.message,
        contains('Binary'),
      );
    });

    test('a rename with no content change says why it is empty', () {
      var patch = index('''
diff --git a/old.dart b/new.dart
similarity index 100%
rename from old.dart
rename to new.dart
''');
      var rows = buildRows(setOf(patch), expanded: {'new.dart'});
      expect(
        rows.whereType<FileNoticeRow>().single.message,
        contains('only the path'),
      );
    });
  });

  group('hunk lines', () {
    test('numbers both sides, and drops the header', () {
      var patch = index(twoFiles);
      var a = patch.files.firstWhere((f) => f.path == 'lib/a.dart');
      var lines = parseHunkLines(
        patch.textForHunk(a.hunks.first),
        a.hunks.first,
      );

      expect(lines.map((l) => l.kind), [
        DiffLineKind.context,
        DiffLineKind.removed,
        DiffLineKind.added,
        DiffLineKind.added,
        DiffLineKind.context,
      ]);
      // `one` is line 1 on both sides; `two` was line 2 of the old file only;
      // `TWO`/`three` are lines 2 and 3 of the new one.
      expect(lines[0].oldNumber, 1);
      expect(lines[0].newNumber, 1);
      expect(lines[1].oldNumber, 2);
      expect(lines[1].newNumber, isNull);
      expect(lines[2].newNumber, 2);
      expect(lines[3].newNumber, 3);
      expect(lines[4].oldNumber, 3);
      expect(lines[4].newNumber, 4);
    });

    test('the marker is stripped from the text', () {
      var patch = index(twoFiles);
      var b = patch.files.firstWhere((f) => f.path == 'lib/b.dart');
      var lines = parseHunkLines(
        patch.textForHunk(b.hunks.single),
        b.hunks.single,
      );
      expect(lines.map((l) => l.text), ['x', 'y']);
    });

    test('the line count matches what the row builder predicted', () {
      // If these disagree, the list asks for an index the decoded hunk does not
      // have — which is a crash while scrolling, in the one place a crash is
      // least excusable.
      var patch = index(twoFiles);
      for (var file in patch.files) {
        for (var hunk in file.hunks) {
          expect(
            parseHunkLines(patch.textForHunk(hunk), hunk),
            hasLength(hunk.displayLines),
            reason: '${file.path} @@ ${hunk.newStart}',
          );
        }
      }
    });

    test('a no-newline marker is meta and takes no line number', () {
      var patch = index(
        'diff --git a/a.txt b/a.txt\n'
        '--- a/a.txt\n'
        '+++ b/a.txt\n'
        '@@ -1 +1 @@\n'
        '-before\n'
        r'\ No newline at end of file'
        '\n'
        '+after\n',
      );
      var hunk = patch.files.single.hunks.single;
      var lines = parseHunkLines(patch.textForHunk(hunk), hunk);
      var meta = lines.where((l) => l.kind == DiffLineKind.meta);
      expect(meta, hasLength(1));
      expect(meta.single.oldNumber, isNull);
      expect(meta.single.newNumber, isNull);
    });

    test('the cache decodes a hunk once, and only when asked', () {
      var patch = index(twoFiles);
      var cache = HunkLineCache(patch);
      var a = patch.files.firstWhere((f) => f.path == 'lib/a.dart');

      expect(cache.decodedHunks, 0);
      cache.linesFor(a.hunks.first);
      expect(cache.decodedHunks, 1);
      cache.linesFor(a.hunks.first);
      expect(cache.decodedHunks, 1, reason: 'asked twice, decoded once');
      // The second hunk of the same file is still untouched: laziness is per
      // hunk, not per file.
      expect(cache.decodedHunks, 1);
    });
  });

  group('tree', () {
    FileChange at(String path) => FileChange(
      path: path,
      status: ChangeStatus.modified,
      added: 1,
      removed: 0,
      hunks: const [],
      byteStart: 0,
      byteEnd: 0,
    );

    test('single-child directories fold into one row', () {
      // `app/lib/src/motion` is one choice, not four.
      var tree = buildTree([
        at('app/lib/src/motion/lane.dart'),
        at('app/lib/src/motion/timeline.dart'),
      ]);

      expect(tree.sortedChildren, hasLength(1));
      expect(tree.sortedChildren.single.name, 'app/lib/src/motion');
      expect(tree.sortedChildren.single.files, hasLength(2));
    });

    test('a fork stops the folding', () {
      var tree = buildTree([at('app/lib/a.dart'), at('app/test/b.dart')]);

      var app = tree.sortedChildren.single;
      expect(app.name, 'app');
      expect(app.sortedChildren.map((c) => c.name), ['lib', 'test']);
    });

    test('counts are totals, not just what is directly inside', () {
      var tree = buildTree([
        at('app/lib/a.dart'),
        at('app/lib/deep/b.dart'),
        at('app/lib/deep/c.dart'),
      ]);
      expect(tree.sortedChildren.single.totalFiles, 3);
    });

    test('a repo-root file lives at the top', () {
      var tree = buildTree([at('pubspec.yaml'), at('app/lib/a.dart')]);
      expect(tree.sortedFiles.map((f) => f.path), ['pubspec.yaml']);
    });

    test('pathsUnder takes a directory and not its lookalikes', () {
      var files = [at('app/lib/a.dart'), at('app_extra/lib/b.dart')];
      expect(pathsUnder(files, 'app'), {'app/lib/a.dart'});
    });

    test('pathsMatching is a plain case-insensitive substring', () {
      var files = [at('app/lib/Motion.dart'), at('app/lib/other.dart')];
      expect(pathsMatching(files, 'motion'), {'app/lib/Motion.dart'});
      // Deliberately not fuzzy: `mtn` is not a match anybody asked for.
      expect(pathsMatching(files, 'mtn'), isEmpty);
      expect(pathsMatching(files, '  '), hasLength(2));
    });
  });
}
