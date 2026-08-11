import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_config_cache.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/ranking.dart';

/// *Would this draw the same screen?* — asked once per live re-probe, so that
/// the answer an agent's `build/` output did not change costs nothing.
///
/// The interesting half is what it must **not** call equal. Every one of these
/// is a re-probe that looks identical in the patch and is a different screen.
void main() {
  FileChange file(String path, {int added = 4}) => FileChange(
    path: path,
    status: ChangeStatus.modified,
    added: added,
    removed: 0,
    hunks: const [],
    byteStart: 0,
    byteEnd: 0,
  );

  ChangeSet setOf({
    String patch = 'diff --git a/lib/a.dart b/lib/a.dart\n@@ -1 +1 @@\n',
    String? base = 'master',
    BaseSource source = BaseSource.inferred,
    String? head = 'abc123',
    Set<String> uncommitted = const {},
    List<UntrackedEntry> untracked = const [],
    Ranking? ranking,
    List<FileChange>? files,
    ChangesRefusal? refusal,
    ChangesConfigState config = ChangesConfigState.none,
  }) => ChangeSet(
    worktreePath: '/repo/feature',
    patch: PatchIndex(
      bytes: Uint8List.fromList(patch.codeUnits),
      files: const [],
    ),
    base: base,
    baseSource: source,
    head: head,
    uncommitted: uncommitted,
    untracked: untracked,
    ranking: ranking,
    files: files,
    refusal: refusal,
    configState: config,
  );

  test('the same read twice', () {
    expect(setOf().sameAnswerAs(setOf()), isTrue);
  });

  test('one byte of the patch', () {
    // The whole point of comparing the bytes rather than the counts: an edit
    // that swaps a line for another of the same length moves neither the file
    // count nor `+n −n`.
    expect(
      setOf().sameAnswerAs(setOf(patch: 'diff --git a/lib/b.dart\n')),
      isFalse,
    );
  });

  test('a commit, which moves no bytes at all', () {
    expect(
      setOf(uncommitted: {'lib/a.dart'}).sameAnswerAs(setOf()),
      isFalse,
      reason: 'the amber marks on screen just went away',
    );
  });

  test('HEAD moving under an identical delta', () {
    // `git commit --amend`, or a rebase that kept the content: the delta from
    // merge-base to disk is the same, and what it is measured from is not.
    expect(setOf().sameAnswerAs(setOf(head: 'def456')), isFalse);
  });

  test('a new untracked file', () {
    expect(
      setOf().sameAnswerAs(
        setOf(untracked: const [UntrackedEntry('scratch.txt')]),
      ),
      isFalse,
    );
  });

  test('an untracked file that just became pinned', () {
    // Only the reason changed — the rules were edited, not the checkout.
    expect(
      setOf(untracked: const [UntrackedEntry('db/1.sql')]).sameAnswerAs(
        setOf(
          untracked: const [
            UntrackedEntry('db/1.sql', reason: 'matches **/migrations/**'),
          ],
        ),
      ),
      isFalse,
    );
  });

  test('a ranking that moved without the patch moving', () {
    // The rules live in a config **outside** the checkout, so an identical
    // delta really can be ranked differently by the time it is read again.
    Ranking ranking(RankTier tier) =>
        Ranking([RankedFile(file: file('lib/a.dart'), tier: tier)]);

    expect(
      setOf(
        ranking: ranking(RankTier.ordinary),
      ).sameAnswerAs(setOf(ranking: ranking(RankTier.noise))),
      isFalse,
    );
  });

  test('the base, and where it was found', () {
    expect(setOf().sameAnswerAs(setOf(base: 'main')), isFalse);
    expect(
      setOf().sameAnswerAs(setOf(source: BaseSource.configured)),
      isFalse,
      reason: 'the header says which, and it is not decoration',
    );
  });

  test('rules that went stale under an unchanged checkout', () {
    expect(
      setOf().sameAnswerAs(setOf(config: ChangesConfigState.stale)),
      isFalse,
      reason: 'a banner appears',
    );
  });

  test(
    'a refused patch is compared by its file list, since it has no bytes',
    () {
      // Both sides carry an empty `PatchIndex`, so bytes say nothing here and
      // the `--numstat` list is the only evidence there is.
      var refusal = const ChangesRefusal(patchBytes: 99 * 1024 * 1024);
      var a = setOf(patch: '', refusal: refusal, files: [file('lib/a.dart')]);
      var b = setOf(patch: '', refusal: refusal, files: [file('lib/a.dart')]);
      var c = setOf(
        patch: '',
        refusal: refusal,
        files: [file('lib/a.dart', added: 5)],
      );

      expect(a.sameAnswerAs(b), isTrue);
      expect(a.sameAnswerAs(c), isFalse);
    },
  );

  test('refusing where it did not refuse before', () {
    expect(
      setOf(patch: '').sameAnswerAs(
        setOf(patch: '', refusal: const ChangesRefusal(patchBytes: 1)),
      ),
      isFalse,
    );
  });
}
