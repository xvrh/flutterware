import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_range.dart';

/// The arithmetic behind the picker, which is the whole feature: every state it
/// can reach has to be two trees git can name, and the one selection git cannot
/// answer must be unreachable rather than warned about.
void main() {
  CommitEntry commit(String sha) =>
      CommitEntry(sha: sha, shortSha: sha, subject: 'about $sha', author: 'me');

  // Newest first, as git log hands them over.
  var commits = [commit('c4'), commit('c3'), commit('c2'), commit('c1')];

  group('the arguments', () {
    test('everything is the merge base and nothing else', () {
      expect(ChangeRange.everything.argumentsFrom('base'), ['base']);
    });

    test('a range that ends at a commit names both trees', () {
      expect(const ChangeRange(from: 'c1', to: 'c3').argumentsFrom('base'), [
        'c1',
        'c3',
      ]);
    });

    test('a range that ends at the working tree names one', () {
      // One argument is `git diff <tree>`, which compares it to the files on
      // disk. Two would compare two commits and lose the uncommitted work.
      expect(const ChangeRange(from: 'c2').argumentsFrom('base'), ['c2']);
    });

    test('nothing to diff against at all is null, not an empty list', () {
      expect(ChangeRange.everything.argumentsFrom(null), isNull);
    });
  });

  group('picking one commit', () {
    test('the left side is the row below it', () {
      expect(
        rangeOf(commit('c3'), commits),
        const ChangeRange(from: 'c2', to: 'c3'),
      );
    });

    test('the oldest commit falls back to the merge base', () {
      // `from: null` rather than a sha this branch does not have — the merge
      // base is the left edge, and the probe fills it in.
      expect(rangeOf(commit('c1'), commits), const ChangeRange(to: 'c1'));
    });

    test('a commit this branch no longer has widens to everything', () {
      // A pasted address, or a rebase under a screen left open. Everything is
      // the honest answer; a half-resolved range would be a diff nobody asked
      // for.
      expect(rangeOf(commit('gone'), commits), ChangeRange.everything);
    });
  });

  group('shift-clicking a second row', () {
    test('spans the two, whichever way round they were clicked', () {
      var forwards = rangeBetween(commit('c3'), commit('c1'), commits);
      var backwards = rangeBetween(commit('c1'), commit('c3'), commits);
      expect(forwards, const ChangeRange(to: 'c3'));
      expect(backwards, forwards);
    });

    test('a run in the middle names both ends', () {
      expect(
        rangeBetween(commit('c3'), commit('c2'), commits),
        const ChangeRange(from: 'c1', to: 'c3'),
      );
    });

    test('onto the working tree is *since this commit*', () {
      // The single most useful selection after "everything", and it is a
      // shift-click rather than a control of its own precisely because the
      // working tree is row n+1 of the same list.
      expect(
        rangeBetween(commit('c2'), null, commits),
        const ChangeRange(from: 'c1'),
      );
    });

    test('the working tree alone is the uncommitted work', () {
      expect(rangeBetween(null, null, commits), const ChangeRange(from: 'c4'));
    });

    test('spanning the whole branch is everything', () {
      // Not a third state that happens to show the same files: the oldest
      // commit has no row below it, so both ends come out null, which *is*
      // `everything` — and the picker lights its top row again.
      expect(rangeBetween(null, commit('c1'), commits), ChangeRange.everything);
    });
  });

  group('what a range covers', () {
    test('everything covers the branch', () {
      expect(commitsIn(ChangeRange.everything, commits), hasLength(4));
    });

    test('a single commit covers itself', () {
      var covered = commitsIn(const ChangeRange(from: 'c2', to: 'c3'), commits);
      expect([for (var c in covered) c.sha], ['c3']);
    });

    test(
      'a range to the working tree covers everything after its left edge',
      () {
        var covered = commitsIn(const ChangeRange(from: 'c2'), commits);
        expect([for (var c in covered) c.sha], ['c4', 'c3']);
      },
    );

    test('the uncommitted work alone covers no commit', () {
      expect(commitsIn(const ChangeRange(from: 'c4'), commits), isEmpty);
    });

    test(
      'a `to` this branch no longer has covers nothing, never everything',
      () {
        // Silently widening a range somebody wrote down narrower is the one
        // direction that misleads: the counts would be the branch's, under a
        // label naming one commit.
        expect(commitsIn(const ChangeRange(to: 'gone'), commits), isEmpty);
      },
    );
  });

  group('the address', () {
    test('everything writes nothing', () {
      expect(ChangeRange.everything.toParams(), isEmpty);
    });

    test('round-trips', () {
      for (var range in [
        ChangeRange.everything,
        const ChangeRange(from: 'c2'),
        const ChangeRange(to: 'c3'),
        const ChangeRange(from: 'c1', to: 'c3'),
      ]) {
        expect(ChangeRange.fromParams(range.toParams()), range);
      }
    });
  });
}
