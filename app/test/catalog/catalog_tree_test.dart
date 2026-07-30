import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/catalog_tree.dart';
import 'package:test/test.dart';

void main() {
  CatalogEntry entry(
    String path,
    String symbol, {
    String? name,
    String? group,
  }) => CatalogEntry(
    path: path,
    symbol: symbol,
    annotation: 'Demo()',
    name: name ?? symbol,
    group: group,
  );

  /// The shape of a tree, as `label` and `label/child` lines — enough to assert
  /// on without spelling out a nested constructor per test.
  List<String> outline(List<CatalogNode> nodes, [String prefix = '']) => [
    for (var node in nodes) ...[
      '$prefix${node.label}',
      if (node case CatalogBranch(:var children))
        ...outline(children, '$prefix${node.label}/'),
    ],
  ];

  test('directories become folders', () {
    var tree = buildCatalogTree([
      entry('demo/team/avatar.dart', 'avatar'),
      entry('demo/billing/invoice.dart', 'invoice'),
    ]);
    expect(outline(tree), [
      'billing',
      'billing/invoice',
      'team',
      'team/avatar',
    ]);
  });

  test('the directories every entry shares are dropped', () {
    // Every entry is under `demo/team`, so both segments say the same nothing
    // — a tree whose every path starts the same way starts one level too high.
    var tree = buildCatalogTree([
      entry('demo/team/avatar.dart', 'avatar'),
      entry('demo/team/tile.dart', 'tile'),
    ]);
    expect(outline(tree), ['avatar', 'tile']);
  });

  test('an entry at the scan root sits at the top level', () {
    var tree = buildCatalogTree([
      entry('demo/one.dart', 'one'),
      entry('demo/two.dart', 'two'),
    ]);
    expect(outline(tree), ['one', 'two']);
  });

  test('a group becomes a level of its own', () {
    var tree = buildCatalogTree([
      entry('demo/avatar.dart', 'members', name: 'Members', group: 'Avatar'),
      entry('demo/avatar.dart', 'empty', name: 'Empty', group: 'Avatar'),
      entry('demo/plain.dart', 'plain', name: 'Plain'),
    ]);
    expect(outline(tree), [
      'Avatar',
      'Avatar/Empty',
      'Avatar/Members',
      'Plain',
    ]);
  });

  test('folders come before entries, each alphabetical', () {
    var tree = buildCatalogTree([
      entry('demo/zebra.dart', 'zebra', name: 'Zebra'),
      entry('demo/alpha.dart', 'alpha', name: 'Alpha'),
      entry('demo/wombat/one.dart', 'one', name: 'One'),
    ]);
    expect(outline(tree), ['wombat', 'wombat/One', 'Alpha', 'Zebra']);
  });

  test('a branch counts every entry below it, at any depth', () {
    var tree = buildCatalogTree([
      entry('demo/team/a.dart', 'a', group: 'G'),
      entry('demo/team/a.dart', 'b', group: 'G'),
      entry('demo/team/c.dart', 'c'),
      entry('demo/other/d.dart', 'd'),
    ]);
    var team = tree.whereType<CatalogBranch>().firstWhere(
      (b) => b.label == 'team',
    );
    expect(team.entries.map((e) => e.symbol), ['a', 'b', 'c']);
  });

  test('an empty catalog is an empty tree', () {
    expect(buildCatalogTree([]), isEmpty);
  });

  group('filtering', () {
    var entries = [
      entry('demo/team/avatar.dart', 'avatarMembers', name: 'Members'),
      entry('demo/team/avatar.dart', 'avatarEmpty', name: 'Empty'),
      entry('demo/billing/invoice.dart', 'invoiceOverdue', name: 'Overdue'),
    ];

    test('keeps the folders leading to a match', () {
      var tree = filterCatalogTree(buildCatalogTree(entries), 'overdue');
      expect(outline(tree), ['billing', 'billing/Overdue']);
    });

    test('a folder name keeps everything under it', () {
      var tree = filterCatalogTree(buildCatalogTree(entries), 'team');
      expect(outline(tree), ['team', 'team/Empty', 'team/Members']);
    });

    test('matches the file and the symbol, not only the name', () {
      // What you remember an entry by is often neither its display name — and
      // an agent is given its symbol.
      expect(
        outline(filterCatalogTree(buildCatalogTree(entries), 'invoice.dart')),
        ['billing', 'billing/Overdue'],
      );
      expect(
        outline(filterCatalogTree(buildCatalogTree(entries), 'avatarempty')),
        ['team', 'team/Empty'],
      );
    });

    test('ignores case and surrounding space', () {
      expect(
        outline(filterCatalogTree(buildCatalogTree(entries), '  MEMBERS ')),
        ['team', 'team/Members'],
      );
    });

    test('an empty query is not a filter', () {
      var tree = buildCatalogTree(entries);
      expect(filterCatalogTree(tree, '   '), same(tree));
    });

    test('nothing matching is an empty tree, not everything', () {
      expect(filterCatalogTree(buildCatalogTree(entries), 'zzz'), isEmpty);
    });
  });

  group('revealing a selection', () {
    var tree = buildCatalogTree([
      entry(
        'demo/team/avatar.dart',
        'members',
        name: 'Members',
        group: 'Avatar',
      ),
      entry('demo/billing/invoice.dart', 'invoice', name: 'Invoice'),
    ]);

    test('names every branch between the root and the entry', () {
      var path = branchesTo(tree, 'demo/team/avatar.dart#members');
      expect(path, {'/team', '/team/Avatar'});
    });

    test('an entry at the top level needs nothing opened', () {
      var flat = buildCatalogTree([
        entry('demo/one.dart', 'one'),
        entry('demo/two.dart', 'two'),
      ]);
      expect(branchesTo(flat, 'demo/one.dart#one'), isEmpty);
    });

    test('an id that is not in the tree opens nothing', () {
      expect(branchesTo(tree, 'demo/gone.dart#gone'), isEmpty);
      expect(branchesTo(tree, null), isEmpty);
    });
  });

  test('every branch can be named at once, at any depth', () {
    var tree = buildCatalogTree([
      entry('demo/team/avatar.dart', 'a', group: 'Avatar'),
      entry('demo/billing/invoice.dart', 'b'),
    ]);
    expect(allBranches(tree), {'/billing', '/team', '/team/Avatar'});
  });
}
