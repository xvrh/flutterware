import 'package:flutterware_app/src/delta/branch_delta.dart';
import 'package:test/test.dart';

/// The classifier, with no git and no graph: a delta described by hand, and
/// the rows it should paint.
void main() {
  BranchDelta delta({
    Map<String, DeltaFile> files = const {},
    Set<String> untracked = const {},
    Set<String> untrackedDirectories = const {},
    Map<String, List<String>> reach = const {},
    bool base = true,
  }) => BranchDelta(
    worktreePath: '/w',
    base: base ? 'main' : null,
    mergeBase: base ? 'abcdef0123456789' : null,
    head: 'fedcba9876543210',
    readAt: DateTime(2026, 9, 2),
    files: files,
    untracked: untracked,
    untrackedDirectories: untrackedDirectories,
    reach: reach,
  );

  EntrySpan span(String id, String file, int line, int endLine) =>
      EntrySpan(id: id, file: file, line: line, endLine: endLine);

  group('a declaration is', () {
    test('added when its file is untracked', () {
      var changes = EntryChanges.of([
        span('a', 'demo/new.dart', 1, 5),
      ], delta(untracked: {'demo/new.dart'}));
      expect(changes['a']?.kind, EntryChangeKind.added);
      expect(changes['a']?.why, contains('not in git'));
    });

    test('added when its file is under an untracked directory', () {
      // git reports the topmost untracked directory and does not walk it.
      var changes = EntryChanges.of([
        span('a', 'demo/feature/new.dart', 1, 5),
      ], delta(untrackedDirectories: {'demo/feature/'}));
      expect(changes['a']?.kind, EntryChangeKind.added);
    });

    test('added when its file was added on the branch', () {
      var changes = EntryChanges.of(
        [span('a', 'demo/new.dart', 1, 5)],
        delta(
          files: {
            'demo/new.dart': const DeltaFile(
              path: 'demo/new.dart',
              status: ChangeStatus.added,
              added: [LineRange(1, 40)],
            ),
          },
        ),
      );
      expect(changes['a']?.kind, EntryChangeKind.added);
    });

    test('added when every one of its lines is new in an existing file', () {
      var file = const DeltaFile(
        path: 'demo/cards.dart',
        status: ChangeStatus.modified,
        added: [LineRange(30, 45)],
      );
      var changes = EntryChanges.of([
        span('new', 'demo/cards.dart', 32, 40),
        span('old', 'demo/cards.dart', 3, 12),
      ], delta(files: {'demo/cards.dart': file}));
      expect(changes['new']?.kind, EntryChangeKind.added);
      expect(changes['old'], isNull);
    });

    test('edited when an added line lands inside it, and says where', () {
      var file = const DeltaFile(
        path: 'demo/cards.dart',
        status: ChangeStatus.modified,
        added: [LineRange(10, 10)],
        uncommitted: true,
      );
      var changes = EntryChanges.of([
        span('a', 'demo/cards.dart', 5, 15),
        span('b', 'demo/cards.dart', 20, 30),
      ], delta(files: {'demo/cards.dart': file}));
      expect(changes['a']?.kind, EntryChangeKind.edited);
      expect(
        changes['a']?.why,
        'Edited on this branch, lines 5–15, not all committed',
      );
      expect(changes['b'], isNull);
    });

    test('edited when lines were removed from inside it', () {
      // Nothing survives changed, so no added run overlaps — the removal
      // position is what says the declaration moved.
      var file = const DeltaFile(
        path: 'demo/cards.dart',
        status: ChangeStatus.modified,
        removedAt: [12],
      );
      var changes = EntryChanges.of([
        span('a', 'demo/cards.dart', 5, 15),
        span('b', 'demo/cards.dart', 20, 30),
      ], delta(files: {'demo/cards.dart': file}));
      expect(changes['a']?.kind, EntryChangeKind.edited);
      expect(changes['b'], isNull);
    });

    test("a removal at the edge of a span is the neighbour's", () {
      // Two one-line declarations, the second rewritten: a removal after 4
      // and an addition at 5. The first must stay unmarked.
      var file = const DeltaFile(
        path: 'demo/cards.dart',
        status: ChangeStatus.modified,
        added: [LineRange(5, 5)],
        removedAt: [4],
      );
      var changes = EntryChanges.of([
        span('a', 'demo/cards.dart', 4, 4),
        span('b', 'demo/cards.dart', 5, 5),
      ], delta(files: {'demo/cards.dart': file}));
      expect(changes['a'], isNull);
      expect(changes['b']?.kind, EntryChangeKind.edited);
    });

    test('a rewritten declaration is edited, never added', () {
      // Its every line is in an added run, but the run replaced lines rather
      // than inserting them.
      var file = const DeltaFile(
        path: 'demo/cards.dart',
        status: ChangeStatus.modified,
        added: [LineRange(5, 9)],
        removedAt: [4],
      );
      var changes = EntryChanges.of([
        span('a', 'demo/cards.dart', 5, 9),
      ], delta(files: {'demo/cards.dart': file}));
      expect(changes['a']?.kind, EntryChangeKind.edited);
    });

    test('edited on any change to the file when its position is unknown', () {
      var file = const DeltaFile(
        path: 'demo/cards.dart',
        status: ChangeStatus.modified,
        added: [LineRange(100, 100)],
      );
      var changes = EntryChanges.of([
        span('a', 'demo/cards.dart', 0, 0),
      ], delta(files: {'demo/cards.dart': file}));
      expect(changes['a']?.kind, EntryChangeKind.edited);
      expect(changes['a']?.why, 'Edited on this branch');
    });

    test('a rename names where the file came from', () {
      var file = const DeltaFile(
        path: 'demo/cards.dart',
        oldPath: 'demo/card.dart',
        status: ChangeStatus.renamed,
        added: [LineRange(7, 7)],
      );
      var changes = EntryChanges.of([
        span('a', 'demo/cards.dart', 5, 15),
      ], delta(files: {'demo/cards.dart': file}));
      expect(changes['a']?.kind, EntryChangeKind.edited);
      expect(changes['a']?.why, endsWith('(moved from demo/card.dart)'));
    });

    test('reached when a file it imports changed', () {
      // Four entries, so one reached is under the quarter that would
      // withhold it.
      var changes = EntryChanges.of(
        [
          span('a', 'demo/cards.dart', 1, 9),
          span('b', 'demo/tiles.dart', 1, 9),
          span('c', 'demo/c.dart', 1, 9),
          span('d', 'demo/d.dart', 1, 9),
        ],
        delta(
          files: {
            'lib/card.dart': const DeltaFile(
              path: 'lib/card.dart',
              status: ChangeStatus.modified,
            ),
          },
          reach: {
            'demo/cards.dart': ['lib/card.dart'],
            'demo/tiles.dart': [],
          },
        ),
      );
      expect(changes['a']?.kind, EntryChangeKind.reached);
      expect(changes['a']?.why, 'Reads lib/card.dart this branch changed');
      expect(changes['a']?.files, ['lib/card.dart']);
      expect(changes['b'], isNull);
      expect(changes.suppressedReach, 0);
    });

    test('an edit to the declaration outranks reach', () {
      var file = const DeltaFile(
        path: 'demo/cards.dart',
        status: ChangeStatus.modified,
        added: [LineRange(3, 3)],
      );
      var changes = EntryChanges.of(
        [span('a', 'demo/cards.dart', 1, 9)],
        delta(
          files: {'demo/cards.dart': file},
          reach: {
            'demo/cards.dart': ['lib/card.dart'],
          },
        ),
      );
      expect(changes['a']?.kind, EntryChangeKind.edited);
    });
  });

  group('reach past a quarter of the tree', () {
    test('is withheld from the rows and counted for the header', () {
      // Four entries, two reached: half the tree, over the threshold. The
      // edited one keeps its mark; the reached two lose theirs.
      var edited = const DeltaFile(
        path: 'demo/d.dart',
        status: ChangeStatus.modified,
        added: [LineRange(2, 2)],
      );
      var changes = EntryChanges.of(
        [
          span('a', 'demo/a.dart', 1, 9),
          span('b', 'demo/b.dart', 1, 9),
          span('c', 'demo/c.dart', 1, 9),
          span('d', 'demo/d.dart', 1, 9),
        ],
        delta(
          files: {'demo/d.dart': edited},
          reach: {
            'demo/a.dart': ['lib/shared.dart'],
            'demo/b.dart': ['lib/shared.dart'],
          },
        ),
      );
      expect(changes['a'], isNull);
      expect(changes['b'], isNull);
      expect(changes['d']?.kind, EntryChangeKind.edited);
      expect(changes.suppressedReach, 2);
      expect(changes.total, 4);
      var summary = BranchChangeSummary.of(changes);
      expect(summary.toJson(), {
        'base': 'main (abcdef0)',
        'added': 0,
        'edited': 1,
        'reached': 0,
        'reachSuppressed': 2,
      });
    });

    test('exactly a quarter is still painted', () {
      var changes = EntryChanges.of(
        [
          span('a', 'demo/a.dart', 1, 9),
          span('b', 'demo/b.dart', 1, 9),
          span('c', 'demo/c.dart', 1, 9),
          span('d', 'demo/d.dart', 1, 9),
        ],
        delta(
          files: {
            'lib/shared.dart': const DeltaFile(
              path: 'lib/shared.dart',
              status: ChangeStatus.modified,
            ),
          },
          reach: {
            'demo/a.dart': ['lib/shared.dart'],
          },
        ),
      );
      expect(changes['a']?.kind, EntryChangeKind.reached);
      expect(changes.suppressedReach, 0);
    });
  });

  group('nothing is painted', () {
    test('without a base', () {
      var changes = EntryChanges.of([
        span('a', 'demo/a.dart', 1, 9),
      ], delta(untracked: {'demo/a.dart'}, base: false));
      expect(changes.isEmpty, isTrue);
      expect(changes.delta.describeBase(), 'no base');
    });

    test('for a branch that changed nothing', () {
      var changes = EntryChanges.of([span('a', 'demo/a.dart', 1, 9)], delta());
      expect(changes.isEmpty, isTrue);
    });
  });

  test('the cache answers once per delta and scan', () {
    var cache = EntryChangesCache();
    var first = delta(untracked: {'demo/a.dart'});
    var scan = Object();
    var calls = 0;
    List<EntrySpan> spans() {
      calls++;
      return [span('a', 'demo/a.dart', 1, 9)];
    }

    var one = cache.of('pkg', first, scan, spans);
    var two = cache.of('pkg', first, scan, spans);
    expect(identical(one, two), isTrue);
    expect(calls, 1);

    cache.of('pkg', delta(untracked: {'demo/a.dart'}), scan, spans);
    expect(calls, 2);
    cache.of('pkg', first, Object(), spans);
    expect(calls, 3);
    expect(cache.of('pkg', null, scan, spans), isNull);
  });

  test(
    'worktreeRelative joins a package path onto a package-relative file',
    () {
      expect(worktreeRelative('.', 'demo/a.dart'), 'demo/a.dart');
      // Declared with a leading `./`, which everything else accepts and git
      // never spells.
      expect(worktreeRelative('./app', 'demo/a.dart'), 'app/demo/a.dart');
      expect(worktreeRelative('app/', 'demo/a.dart'), 'app/demo/a.dart');
      expect(worktreeRelative('app', 'demo/a.dart'), 'app/demo/a.dart');
      expect(
        worktreeRelative('examples/example', 'test/s.dart'),
        'examples/example/test/s.dart',
      );
    },
  );
}
