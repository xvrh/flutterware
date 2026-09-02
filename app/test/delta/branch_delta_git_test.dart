import 'dart:io';

import 'package:flutterware_app/src/delta/branch_delta.dart';
import 'package:flutterware_app/src/delta/branch_delta_probe.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Against **real git**, in a repository the test builds: the lines the
/// probe reads off the hunk bodies, and the reach it works out through the
/// import graph.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw-delta-test'));
  tearDown(() => root.deleteSync(recursive: true));

  void git(List<String> arguments) {
    var result = Process.runSync('git', [
      '-c',
      'user.email=test@example.com',
      '-c',
      'user.name=Test',
      '-c',
      'commit.gpgsign=false',
      ...arguments,
    ], workingDirectory: root.path);
    if (result.exitCode != 0) {
      fail('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
  }

  void write(String path, String contents) {
    var file = File(p.join(root.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  String lines(int count, [String prefix = 'line']) =>
      '${[for (var i = 1; i <= count; i++) '$prefix $i'].join('\n')}\n';

  setUp(() {
    git(['init', '-q', '-b', 'main', '.']);
    write('lib/card.dart', 'class Card {}\n');
    write('lib/tile.dart', 'class Tile {}\n');
    write('demo/cards.dart', "import '../lib/card.dart';\n${lines(20)}");
    write('demo/tiles.dart', "import '../lib/tile.dart';\n${lines(20)}");
    write('demo/moved.dart', lines(10));
    git(['add', '-A']);
    git(['commit', '-qm', 'init']);
    git(['checkout', '-q', '-b', 'feature']);
  });

  test(
    'a branch with nothing on it answers an empty delta with a base',
    () async {
      var delta = await BranchDeltaProbe().probe(
        root.path,
        files: {'demo/cards.dart'},
      );
      expect(delta.hasBase, isTrue);
      expect(delta.base, 'main');
      expect(delta.isEmpty, isTrue);
      expect(delta.reachOf('demo/cards.dart'), isEmpty);
    },
  );

  test(
    'added lines are read off the hunk bodies, not the hunk ranges',
    () async {
      // Lines 5..6 inserted and line 15 removed, committed; then line 19
      // rewritten in place, uncommitted. A hunk's own range includes three
      // lines of context either side, which must not count.
      var edited = lines(20).split('\n');
      edited.insertAll(4, ['new a', 'new b']);
      edited.removeAt(16); // "line 15" after the insertion shifted it
      write(
        'demo/cards.dart',
        "import '../lib/card.dart';\n${edited.join('\n')}",
      );
      git(['commit', '-qam', 'edit']);
      var again = File(p.join(root.path, 'demo/cards.dart')).readAsStringSync();
      write('demo/cards.dart', again.replaceFirst('line 19', 'LINE 19'));

      var delta = await BranchDeltaProbe().probe(root.path);
      var file = delta.files['demo/cards.dart']!;

      // File line numbers: the import is line 1, so "line N" sits at N+1
      // before the insertion. new a/new b land at 6..7; line 15 was at 16 and
      // is at 18 after the shift, removed; line 19 at 22 after the shift.
      expect(file.status, ChangeStatus.modified);
      expect(file.uncommitted, isTrue);
      expect(file.added.map((r) => '$r'), ['6–7', '21']);
      // 17: "line 15" gone. 20: "line 19" replaced, which is a removal and an
      // addition at the same place.
      expect(file.removedAt, [17, 20]);
      expect(file.touches(6, 6), isTrue);
      expect(
        file.touches(8, 16),
        isFalse,
        reason: 'context lines are not edits',
      );
      expect(file.touches(16, 18), isTrue, reason: 'a removal after line 17');
      expect(
        file.touches(17, 17),
        isFalse,
        reason: "edges are the neighbour's",
      );
      expect(file.wholly(6, 7), isTrue);
      expect(file.wholly(5, 7), isFalse);
      expect(file.wholly(21, 21), isFalse, reason: 'line 19 was rewritten');
    },
  );

  test('untracked, added, renamed and reached, in one delta', () async {
    write('demo/fresh.dart', lines(3));
    write('demo/staged.dart', lines(3));
    git(['add', 'demo/staged.dart']);
    git(['mv', 'demo/moved.dart', 'demo/elsewhere.dart']);
    write('lib/card.dart', 'class Card { int x = 1; }\n');
    write('demo/deep/one/two.dart', lines(2));

    var delta = await BranchDeltaProbe().probe(
      root.path,
      files: {'demo/cards.dart', 'demo/tiles.dart', 'demo/fresh.dart'},
    );

    expect(delta.untracked, {'demo/fresh.dart'});
    expect(delta.untrackedDirectories, {'demo/deep/'});
    expect(delta.isUntracked('demo/deep/one/two.dart'), isTrue);
    expect(delta.files['demo/staged.dart']?.status, ChangeStatus.added);
    expect(delta.files['demo/elsewhere.dart']?.status, ChangeStatus.renamed);
    expect(delta.files['demo/elsewhere.dart']?.oldPath, 'demo/moved.dart');
    expect(delta.files['lib/card.dart']?.status, ChangeStatus.modified);

    // cards reads card.dart, which changed; tiles reads tile.dart, which did
    // not. An entry file's own change is not reach.
    expect(delta.reachOf('demo/cards.dart'), ['lib/card.dart']);
    expect(delta.reachOf('demo/tiles.dart'), isEmpty);
    expect(delta.reachOf('demo/fresh.dart'), isEmpty);

    var changes = EntryChanges.of([
      const EntrySpan(
        id: 'cards',
        file: 'demo/cards.dart',
        line: 2,
        endLine: 5,
      ),
      const EntrySpan(
        id: 'tiles',
        file: 'demo/tiles.dart',
        line: 2,
        endLine: 5,
      ),
      const EntrySpan(
        id: 'fresh',
        file: 'demo/fresh.dart',
        line: 1,
        endLine: 3,
      ),
      const EntrySpan(
        id: 'staged',
        file: 'demo/staged.dart',
        line: 1,
        endLine: 3,
      ),
      const EntrySpan(
        id: 'moved',
        file: 'demo/elsewhere.dart',
        line: 1,
        endLine: 3,
      ),
      const EntrySpan(
        id: 'deep',
        file: 'demo/deep/one/two.dart',
        line: 1,
        endLine: 2,
      ),
    ], delta);
    expect(changes['cards']?.kind, EntryChangeKind.reached);
    expect(changes['tiles'], isNull);
    expect(changes['fresh']?.kind, EntryChangeKind.added);
    expect(changes['staged']?.kind, EntryChangeKind.added);
    expect(changes['deep']?.kind, EntryChangeKind.added);
    // A pure rename has no hunks: nothing in the declaration moved.
    expect(changes['moved'], isNull);
    expect(changes.delta.describeBase(), startsWith('main ('));
  });

  test(
    'an unchanged git half keeps the previous reach without the graph',
    () async {
      write('lib/card.dart', 'class Card { int x = 1; }\n');
      var first = await BranchDeltaProbe().probe(
        root.path,
        files: {'demo/cards.dart'},
      );
      expect(first.reachOf('demo/cards.dart'), ['lib/card.dart']);
      var second = await BranchDeltaProbe().probe(
        root.path,
        files: {'demo/cards.dart'},
        previous: first,
      );
      expect(second.sameAnswerAs(first), isTrue);
      expect(second.reachOf('demo/cards.dart'), ['lib/card.dart']);
      // A file asked about for the first time is not answered from memory.
      var third = await BranchDeltaProbe().probe(
        root.path,
        files: {'demo/cards.dart', 'demo/tiles.dart'},
        previous: first,
      );
      expect(
        third.reachedFiles,
        containsAll(['demo/cards.dart', 'demo/tiles.dart']),
      );
      expect(third.sameAnswerAs(first), isFalse);
    },
  );

  test('a regenerated file is an edit to its own entries, never reach', () async {
    write('lib/card.g.dart', 'part of card;\n');
    write(
      'demo/cards.dart',
      "import '../lib/card.dart';\nimport '../lib/card.g.dart';\n${lines(20)}",
    );
    git(['add', '-A']);
    git(['commit', '-qm', 'gen']);
    write('lib/card.g.dart', 'part of card; // regenerated\n');

    var delta = await BranchDeltaProbe().probe(
      root.path,
      files: {'demo/cards.dart'},
    );
    expect(delta.files.keys, contains('lib/card.g.dart'));
    expect(delta.reachOf('demo/cards.dart'), isEmpty);
  });

  test('the main branch itself measures from HEAD', () async {
    git(['checkout', '-q', 'main']);
    write('demo/cards.dart', "import '../lib/card.dart';\n${lines(21)}");
    var delta = await BranchDeltaProbe().probe(root.path);
    expect(delta.hasBase, isTrue);
    expect(delta.files.keys, ['demo/cards.dart']);
    expect(delta.files['demo/cards.dart']?.uncommitted, isTrue);
  });
}
