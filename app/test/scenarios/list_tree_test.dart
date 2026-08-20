import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/discovery.dart';
import 'package:flutterware_app/src/scenarios/list_tree.dart';

ScenarioRef ref(String file, String name, [int line = 1]) =>
    ScenarioRef(name: name, file: file, line: line);

/// The tree flattened to indented labels, which is what the pane draws and
/// the easiest shape to assert on.
List<String> sketch(List<ScenarioListNode> nodes, [int depth = 0]) => [
  for (var node in nodes)
    switch (node) {
      ScenarioBranchNode() => [
        '${'  ' * depth}${node.label}/',
        ...sketch(node.children, depth + 1),
      ],
      ScenarioLeafNode() => ['${'  ' * depth}${node.ref.name}'],
    },
].expand((lines) => lines).toList();

void main() {
  test('folders from the directory part, the shared prefix dropped', () {
    var tree = buildScenarioTree([
      ref('test/scenarios/counter_test.dart', 'Counts'),
      ref('test/scenarios/desktop/window_test.dart', 'Resizes'),
      ref('test/scenarios/mobile/shop_test.dart', 'Browses'),
    ]);
    expect(sketch(tree), [
      'desktop/',
      '  window_test.dart/',
      '    Resizes',
      'mobile/',
      '  shop_test.dart/',
      '    Browses',
      'counter_test.dart/',
      '  Counts',
    ]);
  });

  test('a file level is always there, even for one scenario', () {
    // The file is part of the scenario's address, and the only thing telling
    // two same-named scenarios in sibling files apart.
    var tree = buildScenarioTree([
      ref('test/a_test.dart', 'Overview'),
      ref('test/b_test.dart', 'Overview'),
    ]);
    expect(sketch(tree), [
      'a_test.dart/',
      '  Overview',
      'b_test.dart/',
      '  Overview',
    ]);
  });

  test('scenarios keep declaration order while files sort', () {
    var tree = buildScenarioTree([
      ref('test/scenarios/zoo_test.dart', 'Walks in', 3),
      ref('test/scenarios/zoo_test.dart', 'Feeds the ape', 9),
      ref('test/scenarios/zoo_test.dart', 'Buys a postcard', 15),
      ref('test/scenarios/aquarium_test.dart', 'Watches the eel', 3),
    ]);
    expect(sketch(tree), [
      'aquarium_test.dart/',
      '  Watches the eel',
      'zoo_test.dart/',
      // Not alphabetical: the order the file's author put them in.
      '  Walks in',
      '  Feeds the ape',
      '  Buys a postcard',
    ]);
  });

  test('branch ids keep the dropped prefix', () {
    // Expansion state is keyed by id, and what the suite happens to share
    // changes as files come and go — the id must not.
    var tree = buildScenarioTree([
      ref('test/scenarios/desktop/window_test.dart', 'Resizes'),
      ref('test/scenarios/mobile/shop_test.dart', 'Browses'),
    ]);
    expect(allScenarioBranches(tree), {
      'test/scenarios/desktop',
      'test/scenarios/desktop/window_test.dart',
      'test/scenarios/mobile',
      'test/scenarios/mobile/shop_test.dart',
    });
  });

  test('branchesTo names the file and every directory above it', () {
    expect(scenarioBranchesTo('test/scenarios/desktop/window_test.dart'), {
      'test',
      'test/scenarios',
      'test/scenarios/desktop',
      'test/scenarios/desktop/window_test.dart',
    });
    expect(scenarioBranchesTo('a_test.dart'), {'a_test.dart'});
  });

  group('filter', () {
    var tree = buildScenarioTree([
      ref('test/scenarios/checkout_test.dart', 'Pays with a card'),
      ref('test/scenarios/checkout_test.dart', 'Abandons the basket'),
      ref('test/scenarios/desktop/login_test.dart', 'Signs in with email'),
    ]);

    test('a name keeps its row, marked, and drops the rest', () {
      var kept = filterScenarioTree(tree, 'card');
      expect(sketch(kept), ['checkout_test.dart/', '  Pays with a card']);
      var leaf =
          (kept.single as ScenarioBranchNode).children.single
              as ScenarioLeafNode;
      expect(leaf.marks, isNotEmpty);
    });

    test('a file label answers for every scenario in it', () {
      var kept = filterScenarioTree(tree, 'checkout');
      expect(sketch(kept), [
        'checkout_test.dart/',
        '  Pays with a card',
        '  Abandons the basket',
      ]);
      expect((kept.single as ScenarioBranchNode).marks, isNotEmpty);
    });

    test('a folder label keeps its whole subtree', () {
      var kept = filterScenarioTree(tree, 'desktop');
      expect(sketch(kept), [
        'desktop/',
        '  login_test.dart/',
        '    Signs in with email',
      ]);
    });

    test('fuzzy, not substring', () {
      expect(sketch(filterScenarioTree(tree, 'pwc')), [
        'checkout_test.dart/',
        '  Pays with a card',
      ]);
    });

    test('nothing answers, nothing stays', () {
      expect(filterScenarioTree(tree, 'zzz'), isEmpty);
    });

    test('empty query is the whole tree', () {
      expect(filterScenarioTree(tree, '  '), same(tree));
    });
  });
}
