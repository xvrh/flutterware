// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
import 'package:flutterware_app/src/comparison/tree_diff.dart';
import 'package:test/test.dart';

/// Why the pixels differ, in words — the channel that turns a heatmap into a
/// sentence an agent can act on.
void main() {
  InspectNode node(
    String type, {
    String? description,
    double x = 0,
    double y = 0,
    double width = 10,
    double height = 10,
    bool laidOut = true,
    List<InspectNode> children = const [],
  }) => InspectNode(
    id: '',
    type: type,
    description: description,
    createdByLocalProject: true,
    layout: laidOut
        ? InspectLayout(
            x: x,
            y: y,
            width: width,
            height: height,
            isRepaintBoundary: false,
          )
        : null,
    children: children,
  );

  test('two identical trees have nothing to say', () {
    var tree = node(
      'Card',
      children: [node('Text', description: 'Text("Hi")')],
    );

    expect(TreeDiff.of(tree, tree).isEmpty, isTrue);
  });

  test('a resized node names both sizes', () {
    var deltas = TreeDiff.of(
      node('Card', width: 100, height: 40),
      node('Card', width: 100, height: 64),
    ).deltas;

    expect(deltas, hasLength(1));
    expect(deltas.single.property, 'size');
    expect(deltas.single.base, '100×40');
    expect(deltas.single.head, '100×64');
  });

  test('a re-worded label reads as its description changing', () {
    var deltas = TreeDiff.of(
      node('Text', description: 'Text("Save")'),
      node('Text', description: 'Text("Pay")'),
    ).deltas;

    expect(deltas.single.property, 'description');
    expect(deltas.single.head, 'Text("Pay")');
  });

  // The whole reason children are aligned rather than zipped: one inserted
  // widget renumbers every sibling after it.
  test('an inserted child is one addition, not a renumbered subtree', () {
    var base = node(
      'Column',
      children: [
        node('Text', description: 'Text("A")'),
        node('Text', description: 'Text("C")'),
      ],
    );
    var head = node(
      'Column',
      children: [
        node('Text', description: 'Text("A")'),
        node('Text', description: 'Text("B")'),
        node('Text', description: 'Text("C")'),
      ],
    );

    var deltas = TreeDiff.of(base, head).deltas;

    expect(deltas, hasLength(1));
    expect(deltas.single.kind, TreeDeltaKind.added);
    expect(deltas.single.path, contains('Text("B")'));
  });

  test('a removed child is one removal', () {
    var base = node(
      'Column',
      children: [
        node('Text', description: 'Text("A")'),
        node('Divider'),
      ],
    );
    var head = node(
      'Column',
      children: [node('Text', description: 'Text("A")')],
    );

    var deltas = TreeDiff.of(base, head).deltas;

    expect(deltas, hasLength(1));
    expect(deltas.single.kind, TreeDeltaKind.removed);
    expect(deltas.single.path, contains('Divider'));
  });

  // A node that moved because something above it grew did not itself change,
  // and reporting it as one buries the node that did.
  test('a child pushed down by a resized parent is demoted, not silenced', () {
    var base = node(
      'Column',
      height: 40,
      children: [node('Text', description: 'Text("A")', y: 20)],
    );
    var head = node(
      'Column',
      height: 64,
      children: [node('Text', description: 'Text("A")', y: 44)],
    );

    var deltas = TreeDiff.of(base, head).deltas;

    expect(deltas.first.property, 'size');
    expect(deltas.first.kind, TreeDeltaKind.changed);
    expect(deltas.last.property, 'offset');
    expect(deltas.last.kind, TreeDeltaKind.shifted);
  });

  test('a node that moved on its own is a change, not a shift', () {
    var base = node('Column', children: [node('Icon', x: 0)]);
    var head = node('Column', children: [node('Icon', x: 12)]);

    var deltas = TreeDiff.of(base, head).deltas;

    expect(deltas.single.property, 'offset');
    expect(deltas.single.kind, TreeDeltaKind.changed);
  });

  test('a whole tree appearing or disappearing is one delta', () {
    expect(
      TreeDiff.of(null, node('Card')).deltas.single.kind,
      TreeDeltaKind.added,
    );
    expect(
      TreeDiff.of(node('Card'), null).deltas.single.kind,
      TreeDeltaKind.removed,
    );
    expect(TreeDiff.of(null, null).isEmpty, isTrue);
  });

  // Most of a summary tree has no box of its own — a provider, a builder —
  // and "it has no box" must not read as "its box is empty".
  test('a node with no box contributes no layout delta', () {
    var deltas = TreeDiff.of(
      node('Provider', laidOut: false),
      node('Provider', laidOut: false),
    ).deltas;

    expect(deltas, isEmpty);
  });

  test('additions and removals outrank property changes', () {
    var base = node(
      'Column',
      children: [node('Text', description: 'Text("A")', width: 10)],
    );
    var head = node(
      'Column',
      children: [
        node('Text', description: 'Text("A")', width: 20),
        node('Badge'),
      ],
    );

    var deltas = TreeDiff.of(base, head).deltas;

    expect(deltas.first.kind, TreeDeltaKind.added);
    expect(deltas.last.property, 'size');
  });
}
