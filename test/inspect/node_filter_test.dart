import 'dart:convert';

import 'package:flutterware/src/inspect/node.dart';
import 'package:test/test.dart';

/// What a caller gets to ask for, and what it costs.
///
/// The tree was measured unusable before any of this existed: one observation
/// of the flutterware GUI's own Changes screen came back as 482 nodes and
/// 234 KB, blew a 50,000-token reply budget, and was cut off half way down the
/// left pane — so half the screen was never reported at all. These tests pin
/// the three answers to that: scope it, drop what is saying nothing, and spell
/// what is left in fewer bytes.
void main() {
  /// A box, spelled once so two nodes can be given the same one.
  InspectLayout box({
    double x = 0,
    double y = 0,
    double width = 100,
    double height = 20,
    InspectFlex? flex,
  }) => InspectLayout(x: x, y: y, width: width, height: height, flex: flex);

  InspectNode node(
    String id,
    String type, {
    String? description,
    InspectLayout? layout,
    Map<String, String> properties = const {},
    List<InspectNode> children = const [],
    InspectSource? source,
  }) => InspectNode(
    id: id,
    type: type,
    description: description,
    layout: layout,
    properties: properties,
    children: children,
    source: source,
  );

  List<String> typesOf(InspectTree tree) => [
    for (var node in tree.nodes) node.type,
  ];

  // The guest filters before it serialises, so anything the collapse forgets
  // to carry over never leaves the process — and the survivor of a single-box
  // chain is exactly the node that was carrying the words.
  test('a collapsed chain keeps everything the survivor was carrying', () {
    var tree = InspectTree(
      entryId: null,
      root: InspectNode(
        id: '',
        type: 'Padding',
        layout: box(),
        children: [
          InspectNode(
            id: '0',
            type: 'Text',
            description: 'Text("Save")',
            widgetKey: "[<'save'>]",
            layout: box(),
            keys: const [InspectKey(catalog: 'app', key: 'action.save')],
            unkeyedText: const ['Save'],
            textOverflowed: true,
          ),
        ],
      ),
    );

    var survivor = tree.filtered(const InspectFilter()).nodes.last;

    expect(survivor.type, 'Text');
    expect(survivor.widgetKey, "[<'save'>]");
    expect(survivor.keys.single.key, 'action.save');
    expect(survivor.unkeyedText, ['Save']);
    expect(survivor.textOverflowed, isTrue);
  });

  group('the noise filter', () {
    test("drops the wrapper that shares its only child's box", () {
      // What every list row on the measured screen looked like: a tap handler
      // and a hover region wrapping the thing that is actually drawn.
      var tree = InspectTree(
        entryId: null,
        root: node(
          '',
          'InkWell',
          layout: box(),
          children: [
            node(
              '0',
              'MouseRegion',
              layout: box(),
              properties: {'cursor': 'click'},
              children: [
                node(
                  '0/0',
                  'Text',
                  description: 'Text("Save")',
                  layout: box(),
                  properties: {'data': '"Save"'},
                ),
              ],
            ),
          ],
        ),
      );

      expect(typesOf(tree.filtered(const InspectFilter())), ['Text']);
    });

    test('keeps a wrapper whose box is its own', () {
      var tree = InspectTree(
        entryId: null,
        root: node(
          '',
          'Padding',
          layout: box(width: 116, height: 36),
          children: [node('0', 'Text', layout: box())],
        ),
      );

      expect(typesOf(tree.filtered(const InspectFilter())), [
        'Padding',
        'Text',
      ]);
    });

    /// The `Gap`/`SizedBox` pair the measurement called out: two nodes, one
    /// box, and only one of them says how wide the gap is.
    test('keeps whichever of a pair carries the measurement', () {
      var tree = InspectTree(
        entryId: null,
        root: node(
          '',
          'Gap',
          layout: box(width: 8, height: 8),
          children: [
            node(
              '0',
              'SizedBox',
              layout: box(width: 8, height: 8),
              properties: {'width': '8.0', 'height': '8.0'},
            ),
          ],
        ),
      );

      var filtered = tree.filtered(const InspectFilter());
      expect(typesOf(filtered), ['SizedBox']);
      expect(filtered.root!.properties['width'], '8.0');
    });

    /// The one a reader would miss most: `crossAxisAlignment` is why the
    /// header's button sits 12.5pt off the label's centreline, and no other
    /// node in the chain has it.
    ///
    /// The two share a box because they share a *render object*: a `Builder`
    /// has none of its own, so the walk reports the nearest one below it —
    /// the `RenderFlex` — flex and all.
    test('never drops the node that carries the flex', () {
      var flex = box(flex: const InspectFlex(direction: 'horizontal'));
      var tree = InspectTree(
        entryId: null,
        root: node(
          '',
          'Builder',
          layout: flex,
          children: [node('0', 'Row', layout: flex)],
        ),
      );

      expect(typesOf(tree.filtered(const InspectFilter())), ['Row']);
    });

    test('ties go to the outer node, whose source is the call site', () {
      var tree = InspectTree(
        entryId: null,
        root: node(
          '',
          'IndexFileRow',
          layout: box(),
          properties: {'path': 'lib/main.dart'},
          source: const InspectSource(
            file: 'file:///repo/list.dart',
            line: 40,
            column: 3,
          ),
          children: [
            node(
              '0',
              'DecoratedBox',
              layout: box(),
              properties: {'decoration': 'BoxDecoration()'},
            ),
          ],
        ),
      );

      var root = tree.filtered(const InspectFilter()).root!;
      expect(root.type, 'IndexFileRow');
      expect(root.source!.line, 40);
    });

    test('a dropped node takes its level, not its subtree', () {
      var row = box(flex: const InspectFlex(direction: 'horizontal'));
      var tree = InspectTree(
        entryId: null,
        root: node(
          '',
          'Column',
          layout: box(height: 200, flex: const InspectFlex(direction: 'v')),
          children: [
            node(
              '0',
              'MouseRegion',
              layout: row,
              children: [
                node(
                  '0/0',
                  'Row',
                  layout: row,
                  children: [
                    node(
                      '0/0/0',
                      'Text',
                      description: 'Text("a")',
                      layout: box(),
                    ),
                    node(
                      '0/0/1',
                      'Text',
                      description: 'Text("b")',
                      layout: box(x: 40),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      var root = tree.filtered(const InspectFilter()).root!;
      // The Row is hoisted a level, and keeps the id that says where it is in
      // the whole tree — so a child of the Column is `0/0`, not `0`.
      expect([for (var child in root.children) child.id], ['0/0']);
      expect(
        [for (var child in root.children.single.children) child.id],
        ['0/0/0', '0/0/1'],
      );
    });

    test('noise: false keeps every level', () {
      var tree = InspectTree(
        entryId: null,
        root: node(
          '',
          'InkWell',
          layout: box(),
          children: [
            node(
              '0',
              'MouseRegion',
              layout: box(),
              children: [
                node('0/0', 'Text', description: 'Text("Save")', layout: box()),
              ],
            ),
          ],
        ),
      );

      expect(typesOf(tree.filtered(InspectFilter.none)), [
        'InkWell',
        'MouseRegion',
        'Text',
      ]);
    });
  });

  group('bounding', () {
    InspectTree deepTree() => InspectTree(
      entryId: null,
      root: node(
        '',
        'Column',
        layout: box(height: 300, flex: const InspectFlex(direction: 'v')),
        children: [
          node(
            '0',
            'Padding',
            layout: box(height: 100),
            children: [
              node('0/0', 'Text', description: 'Text("a")', layout: box()),
              node('0/1', 'Text', description: 'Text("b")', layout: box()),
            ],
          ),
          node('1', 'Divider', layout: box(height: 1)),
        ],
      ),
    );

    test('a depth cut says how many children it removed', () {
      var root = deepTree().filtered(const InspectFilter(maxDepth: 1)).root!;

      expect(typesOf(InspectTree(entryId: null, root: root)), [
        'Column',
        'Padding',
        'Divider',
      ]);
      var padding = root.children.first;
      expect(padding.children, isEmpty);
      expect(
        padding.elidedChildren,
        2,
        reason: 'a bounded read must not read as a complete one',
      );
      expect(root.children.last.elidedChildren, 0);
    });

    test('the count survives the wire', () {
      var cut = deepTree().filtered(const InspectFilter(maxDepth: 1));
      for (var compact in [false, true]) {
        var back = InspectTree.fromJson(cut.toJson(compact: compact));
        expect(back.root!.children.first.elidedChildren, 2);
      }
    });

    test('a root id reports that subtree and nothing above it', () {
      var scoped = deepTree().filtered(const InspectFilter(root: '0'));

      expect(typesOf(scoped), ['Padding', 'Text', 'Text']);
      expect(scoped.root!.id, '0');
    });

    test('an id that names nothing is refused, not approximated', () {
      expect(
        () => deepTree().filtered(const InspectFilter(root: '9/9')),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains('9/9'), contains('Observe again')),
          ),
        ),
      );
    });
  });

  group('the compact spelling', () {
    InspectTree twoFiles() => InspectTree(
      entryId: 'demo',
      root: node(
        '',
        'Column',
        layout: box(height: 300, flex: const InspectFlex(direction: 'v')),
        source: const InspectSource(
          file: 'file:///repo/app/lib/screen.dart',
          line: 402,
          column: 11,
        ),
        children: [
          node(
            '0',
            'Text',
            description: 'Text("a")',
            layout: box(width: 7.261507987976074),
            properties: {'data': '"a"'},
            source: const InspectSource(
              file: 'file:///repo/app/lib/screen.dart',
              line: 404,
              column: 13,
            ),
          ),
          node(
            '1',
            'Icon',
            layout: box(width: 16, height: 16),
            source: const InspectSource(
              file: 'file:///repo/app/lib/row.dart',
              line: 9,
              column: 4,
            ),
          ),
        ],
      ),
    );

    test('round trips to the very same tree', () {
      var before = twoFiles();
      var after = InspectTree.fromJson(before.toJson(compact: true));

      expect(after.entryId, 'demo');
      expect([for (var node in after.nodes) node.id], ['', '0', '1']);
      expect(
        after.nodes.elementAt(1).source!.file,
        'file:///repo/app/lib/screen.dart',
      );
      expect(after.nodes.elementAt(2).source!.line, 9);
      expect(after.nodes.elementAt(1).properties['data'], '"a"');
    });

    test('names each file once and spells an id against its parent', () {
      var json = twoFiles().toJson(compact: true);

      expect(json['files'], hasLength(2));
      var root = (json['root']! as Map).cast<String, Object?>();
      expect(root['source'], '0:402:11');
      var children = (root['children']! as List).cast<Map>();
      expect(children.first['source'], '0:404:13');
      expect(children.last['source'], '1:9:4');
    });

    test('rounds sub-pixel geometry, and only here', () {
      var compact = twoFiles().toJson(compact: true);
      var child = ((compact['root']! as Map)['children']! as List).first as Map;
      expect((child['layout']! as Map)['width'], 7.26);

      var verbose = twoFiles().toJson();
      var same = ((verbose['root']! as Map)['children']! as List).first as Map;
      expect(
        (same['layout']! as Map)['width'],
        7.261507987976074,
        reason: 'the comparison caches diff trees field by field',
      );
    });

    test('is smaller than the spelling it replaces', () {
      var tree = twoFiles();
      expect(
        jsonEncode(tree.toJson(compact: true)).length,
        lessThan(jsonEncode(tree.toJson()).length),
      );
    });

    /// The skew that is actually possible: a guest compiled from older
    /// sources answering a newer host. It writes the long spelling, with no
    /// `compact` flag on it, and the reader has to go on reading that.
    test("an older guest's tree still reads", () {
      var before = twoFiles();
      var after = InspectTree.fromJson(before.toJson());

      expect([for (var node in after.nodes) node.id], ['', '0', '1']);
      expect(after.nodes.last.source!.line, 9);
    });
  });

  group('property values', () {
    test('a colour is its hex', () {
      expect(
        shortenPropertyValue(
          'Color(alpha: 1.0000, red: 0.4196, green: 0.4471, blue: 0.5020, '
          'colorSpace: ColorSpace.sRGB)',
        ),
        '#6B7280',
      );
    });

    test('a translucent colour keeps its alpha', () {
      expect(
        shortenPropertyValue(
          'Color(alpha: 0.5000, red: 0.0000, green: 0.0000, blue: 0.0000, '
          'colorSpace: ColorSpace.sRGB)',
        ),
        '#00000080',
      );
    });

    test('a colour outside sRGB says so', () {
      expect(
        shortenPropertyValue(
          'Color(alpha: 1.0000, red: 1.0000, green: 0.0000, blue: 0.0000, '
          'colorSpace: ColorSpace.displayP3)',
        ),
        '#FF0000 displayP3',
      );
    });

    /// The exact value the measurement complained about: the old elision took
    /// the middle, so the colour — the one thing being asked about — is what
    /// went, and `topRight: Radius.circular(7.0)))` is what stayed.
    test('an overlong value keeps its head', () {
      var shortened = shortenPropertyValue(
        'BoxDecoration(color: Color(alpha: 1.0000, red: 0.4196, green: '
        '0.4471, blue: 0.5020, colorSpace: ColorSpace.sRGB), borderRadius: '
        'BorderRadius.only(topLeft: Radius.circular(7.0), topRight: '
        'Radius.circular(7.0)))',
      );

      expect(shortened, startsWith('BoxDecoration(color: #6B7280'));
      expect(shortened.length, lessThanOrEqualTo(96));
      expect(shortened, endsWith('…'));
    });

    test('a value that fits is left alone', () {
      expect(
        shortenPropertyValue('EdgeInsets.all(8.0)'),
        'EdgeInsets.all(8.0)',
      );
    });
  });
}
