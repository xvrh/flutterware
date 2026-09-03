// The table and the repeater: columns that agree across rows, and one
// authored row drawn once per item of a list parameter.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

void main() {
  TextNode text(String name, String value) =>
      TextNode(name, value)..fontSize = 12;

  /// A two-row table with three cells each, in a root wide enough for it.
  (SceneDocument, FrameNode) table({List<double?> columns = const []}) {
    var head = FrameNode('head')
      ..children.addAll([
        text('h1', 'Item'),
        text('h2', 'Qty'),
        text('h3', 'Amount'),
      ]);
    var line = FrameNode('line')
      ..children.addAll([
        text('c1', 'Espresso beans, 1kg'),
        text('c2', '12'),
        text('c3', '£384.00'),
      ]);
    var grid = FrameNode('grid', layout: NodeLayout.table)
      ..width = 400
      ..columns = [...columns]
      ..children.addAll([head, line]);
    var root = FrameNode('root')
      ..width = 500
      ..height = 300
      ..children.add(grid);
    return (SceneDocument(root), grid);
  }

  Future<Map<String, SceneRect>> render(
    WidgetTester tester,
    SceneDocument doc,
  ) async {
    var rects = <String, SceneRect>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SceneView(doc, onMeasured: rects.addAll),
        ),
      ),
    );
    await tester.pump();
    return rects;
  }

  testWidgets('a column is as wide in one row as in the other', (tester) async {
    var (doc, _) = table();
    var rects = await render(tester, doc);

    // The whole point: the header's second cell and the line's second cell
    // are the same column, so they start and end together — which stacked
    // rows, each sizing its own children, could never promise.
    expect(rects['h2']!.left, rects['c2']!.left);
    expect(rects['h2']!.width, rects['c2']!.width);
    expect(rects['h3']!.left, rects['c3']!.left);
  });

  testWidgets('a fixed track is exactly that wide', (tester) async {
    var (doc, _) = table(columns: [double.infinity, 48, 96]);
    var rects = await render(tester, doc);

    expect(rects['h2']!.width, 48);
    expect(rects['h3']!.width, 96);
    // The filling column takes the rest of the 400.
    expect(rects['c1']!.width, 400 - 48 - 96);
  });

  testWidgets('a filling track hugs when the width is unbounded', (
    tester,
  ) async {
    var (doc, grid) = table(columns: [double.infinity, 48, 96]);
    grid.width = null;
    var rects = await render(tester, doc);

    // Nothing to take a share of, so the column is its content — the same
    // honest degradation `Expanded` gets under an unbounded main axis.
    expect(rects['c1']!.width, lessThan(400 - 48 - 96));
  });

  testWidgets('cell padding is the space inside every cell', (tester) async {
    var (doc, grid) = table(columns: [double.infinity, 48, 96]);
    grid.cellPadding = const SceneEdges.all(8);
    var rects = await render(tester, doc);

    expect(rects['h2']!.width, 48 - 16);
    expect(rects['h2']!.left - rects['grid']!.left, greaterThan(0));
  });

  testWidgets('a row is the rect its cells span', (tester) async {
    var (doc, _) = table(columns: [double.infinity, 48, 96]);
    var rects = await render(tester, doc);

    // A table lays the cells out itself, so the row draws no box — and the
    // editor still has to be able to select and drop on it.
    var row = rects['line']!;
    expect(row.left, rects['c1']!.left);
    expect(row.right, rects['c3']!.right);
  });

  // ---------------------------------------------------------------------
  // The repeater
  // ---------------------------------------------------------------------

  SceneDocument repeated({List<SceneItem>? items}) {
    var cell = text('cell', 'Espresso beans, 1kg')
      ..paramRefs['text'] = 'lines.item';
    var qty = text('qty', '12')..paramRefs['text'] = 'lines.qty';
    var row = FrameNode('row', layout: NodeLayout.row)
      ..repeat = 'lines'
      ..children.addAll([cell, qty]);
    var root = FrameNode('root', layout: NodeLayout.column)
      ..width = 400
      ..height = 300
      ..children.add(row);
    return SceneDocument(root)
      ..params.add(
        SceneParamDecl(
          'lines',
          SceneParamKind.list,
          items ??
              <SceneItem>[
                {'item': 'Espresso beans, 1kg', 'qty': '12'},
                {'item': 'Oat milk, 12 × 1L', 'qty': '8'},
                {'item': 'Takeaway cups, 500', 'qty': '4'},
              ],
        ),
      );
  }

  testWidgets('one authored row is drawn once per item', (tester) async {
    var doc = repeated();
    await render(tester, doc);

    expect(find.text('Espresso beans, 1kg'), findsOneWidget);
    expect(find.text('Oat milk, 12 × 1L'), findsOneWidget);
    expect(find.text('Takeaway cups, 500'), findsOneWidget);
    // Still one node: the tree, the file and the inspector see one row.
    expect(doc.root.children.length, 1);
  });

  testWidgets('an empty list draws nothing', (tester) async {
    var doc = repeated(items: const []);
    await render(tester, doc);

    expect(find.text('Espresso beans, 1kg'), findsNothing);
  });

  testWidgets('an argument replaces the items, first one included', (
    tester,
  ) async {
    var doc = repeated();
    doc.applyArgs({
      'lines': [
        {'item': 'Cocoa, 2kg', 'qty': '3'},
        {'item': 'Syrup, 6 × 750ml', 'qty': '1'},
      ],
    });
    await render(tester, doc);

    // The first item lands on the TEMPLATE — the node keeps its identity
    // and takes the data, exactly as a scalar argument does.
    expect(find.text('Cocoa, 2kg'), findsOneWidget);
    expect(find.text('Syrup, 6 × 750ml'), findsOneWidget);
    expect(find.text('Espresso beans, 1kg'), findsNothing);
  });

  test('the wire carries the rows, not the rule that made them', () {
    var doc = repeated();
    var wire = jsonDecode(jsonEncode(doc.toWire())) as Map<String, Object?>;
    var children = (wire['root']! as Map)['children']! as List;
    expect(children.length, 3);
    expect((children[0] as Map)['name'], 'row');
    expect((children[1] as Map)['name'], 'row#1');
    // The copy carries the item's values, already resolved.
    var cells = (children[1] as Map)['children'] as List;
    expect((cells[0] as Map)['text'], 'Oat milk, 12 × 1L');
  });

  test('the authored document keeps the rule instead', () {
    var doc = repeated();
    var back = sceneFromJson(
      jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>,
    );
    expect(back.root.children.length, 1);
    expect(back.root.children.single.repeat, 'lines');
    expect(back.itemsOf('lines').length, 3);
  });

  // ---------------------------------------------------------------------
  // The grammar
  // ---------------------------------------------------------------------

  const source =
      '''
$sceneFileMarker

class Ledger({
  final List<Map<String, Object>> lines = const [
    {'item': 'Espresso beans, 1kg', 'qty': 12},
    {'item': 'Oat milk, 12 × 1L', 'qty': 8},
  ],
}) {
  late final cell = Text(lines.item, fontSize: 12);
  late final qty = Text(lines.qty, fontSize: 12);
  late final row = Frame(repeat: lines, children: [cell, qty]);
  late final root = Frame(
    width: 400,
    layout: NodeLayout.table,
    columns: [double.infinity, 48],
    cellPadding: 8,
    children: [row],
  );
}
''';

  test('a list parameter, a repeat and a table survive a round trip', () {
    var parsed = parseSceneFile(source);
    expect(parsed.refusals, isEmpty);
    var doc = parsed.doc!;

    expect(doc.params.single.kind, SceneParamKind.list);
    expect(doc.itemsOf('lines').length, 2);
    expect(doc.nodeNamed('row')!.repeat, 'lines');
    // A number field filling a text slot reads as the text it becomes.
    expect((doc.nodeNamed('qty')! as TextNode).text, '12');
    expect(doc.root.columns, [double.infinity, 48]);
    expect(doc.root.cellPadding, const SceneEdges.all(8));

    var out = emitSceneFile(doc, className: parsed.className!);
    var again = parseSceneFile(out);
    expect(again.refusals, isEmpty);
    expect(
      emitSceneFile(again.doc!, className: again.className!),
      out,
      reason: 'emit ∘ parse is the identity on what emit wrote',
    );
    expect(out, contains('repeat: lines'));
    expect(out, contains('Text(lines.item'));
    expect(out, contains('columns: [double.infinity, 48]'));
  });

  test('an item reference outside its repeat is refused', () {
    var parsed = parseSceneFile('''
$sceneFileMarker

class Ledger({
  final List<Map<String, Object>> lines = const [
    {'item': 'Espresso beans, 1kg'},
  ],
}) {
  late final stray = Text(lines.item, fontSize: 12);
  late final root = Frame(width: 400, children: [stray]);
}
''');
    expect(parsed.ok, isFalse);
    expect(parsed.refusals.single.construct, 'item reference');
    expect(parsed.refusals.single.message, contains('repeat: lines'));
  });

  test('a repeat over something that is not a list is refused', () {
    var parsed = parseSceneFile('''
$sceneFileMarker

class Ledger({final String title = 'x'}) {
  late final root = Frame(width: 400, repeat: title);
}
''');
    expect(parsed.ok, isFalse);
    expect(parsed.refusals.single.construct, 'repeat');
  });

  test('a field the items do not carry is refused', () {
    var parsed = parseSceneFile('''
$sceneFileMarker

class Ledger({
  final List<Map<String, Object>> lines = const [
    {'item': 'Espresso beans, 1kg'},
  ],
}) {
  late final cell = Text(lines.price, fontSize: 12);
  late final row = Frame(repeat: lines, children: [cell]);
  late final root = Frame(width: 400, children: [row]);
}
''');
    expect(parsed.ok, isFalse);
    expect(parsed.refusals.first.construct, 'unknown field');
    expect(parsed.refusals.first.message, contains('"item"'));
  });

  test('an edited cell bakes in and drops its stale reference', () {
    var parsed = parseSceneFile(source);
    var doc = parsed.doc!;
    (doc.nodeNamed('cell')! as TextNode).text = 'Something else';

    var out = emitSceneFile(doc, className: parsed.className!);
    expect(out, contains("Text('Something else'"));
    expect(out, isNot(contains('Text(lines.item')));
    // The edit survives; the reference is what goes.
    expect(parseSceneFile(out).refusals, isEmpty);
  });
}
