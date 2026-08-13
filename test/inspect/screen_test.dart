// ignore_for_file: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
import 'package:flutterware/src/inspect/screen.dart';
import 'package:test/test.dart';

/// A node with a box, spelled short because these tests are mostly trees.
InspectNode node(
  String id,
  String type, {
  List<double>? box,
  String? description,
  String? label,
  bool? selected,
  Map<String, String> properties = const {},
  String? source,
  bool offstage = false,
  List<InspectNode> children = const [],
}) => InspectNode(
  id: id,
  type: type,
  description: description,
  label: label,
  selected: selected,
  offstage: offstage,
  properties: properties,
  source: source == null
      ? null
      : InspectSource(file: 'file:///app/$source', line: 12, column: 3),
  layout: box == null
      ? null
      : InspectLayout(x: box[0], y: box[1], width: box[2], height: box[3]),
  children: children,
);

InspectTree treeOf(InspectNode root) => InspectTree(entryId: 'e', root: root);

/// Every item, flat, so a test can talk about words without walking.
List<String?> wordsOf(Screen screen) => [for (var i in screen.items) i.words];

void main() {
  group('the screen projection', () {
    test('a control keeps the words of the texts inside it', () {
      // The Brewline case: an InkWell with no semantics label, holding the
      // texts that name it. Label-first left every card anonymous.
      var screen = Screen.of(
        treeOf(
          node(
            '',
            'Column',
            box: [0, 0, 400, 200],
            children: [
              node(
                '0',
                'InkWell',
                box: [0, 0, 400, 80],
                children: [
                  node(
                    '0/0',
                    'Text',
                    description: 'Text("Cappuccino")',
                    box: [10, 10, 100, 20],
                  ),
                  node(
                    '0/1',
                    'Text',
                    description: 'Text("4.20 €")',
                    box: [300, 10, 60, 20],
                  ),
                ],
              ),
              node(
                '1',
                'Text',
                description: 'Text("The menu")',
                box: [0, 100, 100, 20],
              ),
            ],
          ),
        ),
      );

      expect(wordsOf(screen), ['Cappuccino · 4.20 €', 'The menu']);
      expect(screen.items.first.role, 'button');
      expect(screen.items.last.role, 'text');
    });

    test('a semantics label beats the words inside', () {
      var screen = Screen.of(
        treeOf(
          node(
            '',
            'Row',
            box: [0, 0, 400, 40],
            children: [
              node(
                '0',
                'Tab',
                label: 'Tab A\nTab 1 of 2',
                box: [0, 0, 200, 40],
                children: [
                  node(
                    '0/0',
                    'Text',
                    description: 'Text("Tab A")',
                    box: [10, 10, 60, 20],
                  ),
                ],
              ),
              node(
                '1',
                'Tab',
                label: 'Tab B\nTab 2 of 2',
                selected: true,
                box: [200, 0, 200, 40],
                children: [
                  node(
                    '1/0',
                    'Text',
                    description: 'Text("Tab B")',
                    box: [210, 10, 60, 20],
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      expect(wordsOf(screen), ['Tab A\nTab 1 of 2', 'Tab B\nTab 2 of 2']);
      expect(screen.items.map((i) => i.selected), [null, true]);
    });

    test('a tooltip is the last resort, and what is left is reported', () {
      var screen = Screen.of(
        treeOf(
          node(
            '',
            'Row',
            box: [0, 0, 100, 40],
            children: [
              node(
                '0',
                'IconButton',
                properties: {'tooltip': '"Read this checkout again"'},
                box: [0, 0, 40, 40],
              ),
              node('1', 'IconButton', box: [50, 0, 40, 40]),
            ],
          ),
        ),
      );

      expect(wordsOf(screen), ['Read this checkout again', null]);
      // The one with nothing at all is counted rather than quietly listed:
      // it has no accessible name, which is a real finding about the app.
      expect(screen.anonymousControls, 1);
    });

    test('selection is a tri-state and false is not the same as unknown', () {
      var screen = Screen.of(
        treeOf(
          node(
            '',
            'Row',
            box: [0, 0, 300, 40],
            children: [
              node('0', 'FilterChip', selected: true, box: [0, 0, 100, 40]),
              node('1', 'FilterChip', selected: false, box: [100, 0, 100, 40]),
              node('2', 'InkWell', box: [200, 0, 100, 40]),
            ],
          ),
        ),
      );

      expect(screen.items.map((i) => i.selected), [true, false, null]);
      // On the wire, only the two that were answered say anything.
      var json = [for (var i in screen.items) i.toJson()];
      expect(json[0]['sel'], true);
      expect(json[1]['sel'], false);
      expect(json[2].containsKey('sel'), isFalse);
    });

    test('offstage content is not on the screen', () {
      var screen = Screen.of(
        treeOf(
          node(
            '',
            'Stack',
            box: [0, 0, 100, 100],
            children: [
              node(
                '0',
                'Text',
                description: 'Text("visible")',
                box: [0, 0, 100, 20],
              ),
              node(
                '1',
                'Offstage',
                offstage: true,
                box: [0, 0, 100, 20],
                children: [
                  node(
                    '1/0',
                    'Text',
                    description: 'Text("covered")',
                    box: [0, 0, 100, 20],
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      expect(wordsOf(screen), ['visible']);
    });
  });

  group('regions', () {
    /// Two panes of three items each — enough to fork, enough to survive.
    InspectNode twoPanes() => node(
      '',
      'Row',
      source: 'shell.dart',
      box: [0, 0, 400, 100],
      children: [
        node(
          '0',
          'Column',
          source: 'rail.dart',
          box: [0, 0, 100, 100],
          children: [
            for (var i = 0; i < 3; i++)
              node(
                '0/$i',
                'InkWell',
                label: 'Rail $i',
                box: [0, i * 20, 100, 20],
              ),
          ],
        ),
        node(
          '1',
          'Column',
          source: 'body.dart',
          box: [100, 0, 300, 100],
          children: [
            for (var i = 0; i < 3; i++)
              node(
                '1/$i',
                'Text',
                description: 'Text("Body $i")',
                box: [100, i * 20, 300, 20],
              ),
          ],
        ),
      ],
    );

    test('the layout forks where the items do', () {
      var screen = Screen.of(treeOf(twoPanes()));
      var root = screen.root!;

      expect(root.label, 'Row @ shell.dart:12');
      expect(root.children, hasLength(2));
      var rail = root.children.first as ScreenRegion;
      expect(rail.label, 'Column @ rail.dart:12');
      expect(rail.children.whereType<ScreenItem>(), hasLength(3));
    });

    test('a chain of one child collapses instead of nesting', () {
      var screen = Screen.of(
        treeOf(
          node(
            '',
            'Padding',
            source: 'a.dart',
            box: [0, 0, 400, 100],
            children: [
              node(
                '0',
                'Center',
                source: 'b.dart',
                box: [0, 0, 400, 100],
                children: [twoPanes()],
              ),
            ],
          ),
        ),
      );

      // Neither wrapper is a fork, so neither becomes a region: the reported
      // root is the Row where the screen actually divides.
      expect(screen.root!.label, 'Row @ shell.dart:12');
    });

    test('a region holding fewer than three things is spliced away', () {
      var pair = node(
        '',
        'Column',
        source: 'outer.dart',
        box: [0, 0, 100, 100],
        children: [
          node(
            '0',
            'Row',
            source: 'inner.dart',
            box: [0, 0, 100, 20],
            children: [
              node('0/0', 'InkWell', label: 'A', box: [0, 0, 50, 20]),
              node('0/1', 'InkWell', label: 'B', box: [50, 0, 50, 20]),
            ],
          ),
          node('1', 'InkWell', label: 'C', box: [0, 20, 100, 20]),
          node('2', 'InkWell', label: 'D', box: [0, 40, 100, 20]),
        ],
      );

      var thinned = Screen.of(treeOf(pair));
      expect(
        thinned.root!.children.whereType<ScreenRegion>(),
        isEmpty,
        reason: 'the inner Row holds two things, so it is not a level',
      );
      expect(thinned.root!.children, hasLength(4));

      var kept = Screen.of(treeOf(pair), minRegionItems: 1);
      expect(kept.root!.children.whereType<ScreenRegion>(), hasLength(1));
    });

    test('a scrollable survives thinning whatever it holds', () {
      // The measured regression: at a threshold of three the file list's own
      // ListView vanished because only two rows were on screen, taking the
      // answer to "what scrolls" with it.
      var screen = Screen.of(
        treeOf(
          node(
            '',
            'Column',
            source: 'outer.dart',
            box: [0, 0, 100, 100],
            children: [
              node(
                '0',
                'ListView',
                source: 'list.dart',
                box: [0, 0, 100, 40],
                children: [
                  node('0/0', 'InkWell', label: 'row A', box: [0, 0, 100, 20]),
                  node('0/1', 'InkWell', label: 'row B', box: [0, 20, 100, 20]),
                ],
              ),
              node('1', 'InkWell', label: 'C', box: [0, 40, 100, 20]),
              node('2', 'InkWell', label: 'D', box: [0, 60, 100, 20]),
            ],
          ),
        ),
      );

      var list = screen.root!.children.whereType<ScreenRegion>().single;
      expect(list.label, 'ListView @ list.dart:12');
      expect(list.scrolls, isTrue);
    });

    test('a control inside a control is reported, not swallowed', () {
      // The live regression: an item took over its whole subtree, so a close
      // button on a tab vanished and the numbering grew a hole.
      var screen = Screen.of(
        treeOf(
          node(
            '',
            'Row',
            source: 'bar.dart',
            box: [0, 0, 200, 40],
            children: [
              node(
                '0',
                'InkWell',
                label: 'a-branch',
                box: [0, 0, 100, 40],
                children: [
                  node(
                    '0/0',
                    'Text',
                    description: 'Text("a-branch")',
                    box: [4, 10, 60, 20],
                  ),
                  node(
                    '0/1',
                    'IconButton',
                    label: 'Close',
                    box: [80, 12, 16, 16],
                  ),
                ],
              ),
              node('1', 'InkWell', label: 'other', box: [100, 0, 100, 40]),
            ],
          ),
        ),
      );

      expect(screen.items.map((i) => i.words), ['a-branch', 'Close', 'other']);
      expect(screen.items.map((i) => i.n), [1, 2, 3]);
      var tab = screen.root!.children.first as ScreenItem;
      expect(tab.children.single.words, 'Close');
    });

    test('a screen survives the round trip', () {
      var before = Screen.of(treeOf(twoPanes()));
      var after = Screen.fromJson(before.toJson());
      expect(after.items.map((i) => i.words), before.items.map((i) => i.words));
      expect(after.root!.label, before.root!.label);
      expect(
        (after.root!.children.first as ScreenRegion).children,
        hasLength(3),
      );
    });
  });

  group('the queries', () {
    InspectTree screenTree() => treeOf(
      node(
        '',
        'Column',
        box: [0, 0, 100, 60],
        children: [
          node(
            '0',
            'Text',
            description: 'Text("Watching")',
            box: [0, 0, 50, 20],
            properties: {'size': '10.5', 'weight': '600', 'color': '#C4C7CD'},
          ),
          node(
            '1',
            'Text',
            description: 'Text("Important")',
            box: [0, 20, 50, 20],
            properties: {'size': '12.5', 'weight': '400', 'color': '#9AA1AC'},
          ),
          node(
            '2',
            'IconButton',
            label: 'Read this again',
            box: [0, 40, 40, 20],
          ),
        ],
      ),
    );

    test('find matches the type, the words and the label', () {
      expect(screenTree().matching('watch').map((n) => n.id), ['0']);
      expect(screenTree().matching('iconbutton').map((n) => n.id), ['2']);
      expect(
        screenTree().matching('read this').map((n) => n.id),
        ['2'],
        reason: 'the accessibility label is searched too',
      );
      expect(screenTree().matching('nothing here'), isEmpty);
    });

    test('at returns the chain, outermost first', () {
      var chain = screenTree().chainAt(10, 5);
      expect(chain.map((n) => n.id), ['', '0']);
    });

    test('at outside everything is empty rather than a guess', () {
      expect(screenTree().chainAt(999, 999), isEmpty);
    });

    test('styles aggregates and ranks', () {
      var tree = treeOf(
        node(
          '',
          'Column',
          box: [0, 0, 100, 100],
          children: [
            for (var i = 0; i < 3; i++)
              node(
                '$i',
                'Text',
                description: 'Text("row $i")',
                box: [0, i * 20, 100, 20],
                properties: {'size': '12.5', 'weight': '400'},
              ),
            node(
              '3',
              'Text',
              description: 'Text("Heading")',
              box: [0, 60, 100, 30],
              properties: {'size': '22.0', 'weight': '700'},
            ),
          ],
        ),
      );

      var styles = tree.styles();
      expect(styles.map((s) => s.key), ['12.5/400/?', '22.0/700/?']);
      expect(styles.first.count, 3);
      expect(styles.first.sample, 'row 0');
      expect(styles.last.sample, 'Heading');
    });

    test('styles ignores a size on something that draws no words', () {
      var tree = treeOf(
        node(
          '',
          'Column',
          box: [0, 0, 100, 100],
          children: [
            node('0', 'Icon', box: [0, 0, 20, 20], properties: {'size': '18'}),
          ],
        ),
      );
      expect(tree.styles(), isEmpty);
    });
  });

  group('label and selected on the wire', () {
    test('both spellings carry them, and absence stays absent', () {
      var tree = treeOf(
        node('', 'Tab', label: 'Tab A', selected: false, box: [0, 0, 10, 10]),
      );
      for (var compact in [false, true]) {
        var back = InspectTree.fromJson(tree.toJson(compact: compact));
        expect(back.root!.label, 'Tab A');
        expect(back.root!.selected, isFalse);
      }

      var quiet = treeOf(node('', 'InkWell', box: [0, 0, 10, 10]));
      var json = quiet.toJson();
      expect(json.toString(), isNot(contains('selected')));
      expect(InspectTree.fromJson(json).root!.selected, isNull);
    });
  });
}
