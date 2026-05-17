import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/tui/tui.dart';

/// A FocusNode with a fixed rect, for testing traversal without a widget tree.
class _FixedNode extends FocusNode {
  _FixedNode(this.fixedRect);
  final CellRect fixedRect;
  @override
  CellRect? get rect => fixedRect;
}

void main() {
  test('reading order sorts by row then column', () {
    var policy = ReadingOrderTraversalPolicy();
    var topLeft = _FixedNode(CellRect.fromTLWH(0, 0, 4, 1));
    var topRight = _FixedNode(CellRect.fromTLWH(0, 10, 4, 1));
    var bottom = _FixedNode(CellRect.fromTLWH(5, 0, 4, 1));
    var sorted = policy.sortDescendants([bottom, topRight, topLeft]).toList();
    expect(sorted, [topLeft, topRight, bottom]);
  });

  test('next moves to the following node and wraps at the end', () {
    var manager = FocusManager();
    var policy = ReadingOrderTraversalPolicy();
    var a = _FixedNode(CellRect.fromTLWH(0, 0, 4, 1));
    var b = _FixedNode(CellRect.fromTLWH(0, 10, 4, 1));
    manager.rootScope.debugAttachChild(a);
    manager.rootScope.debugAttachChild(b);
    a.requestFocus();
    manager.applyFocusChangesIfNeeded();

    expect(policy.next(a), isTrue);
    manager.applyFocusChangesIfNeeded();
    expect(manager.primaryFocus, b);

    expect(policy.next(b), isTrue); // wraps
    manager.applyFocusChangesIfNeeded();
    expect(manager.primaryFocus, a);
  });

  test('previous wraps to the last node', () {
    var manager = FocusManager();
    var policy = ReadingOrderTraversalPolicy();
    var a = _FixedNode(CellRect.fromTLWH(0, 0, 4, 1));
    var b = _FixedNode(CellRect.fromTLWH(0, 10, 4, 1));
    manager.rootScope.debugAttachChild(a);
    manager.rootScope.debugAttachChild(b);
    a.requestFocus();
    manager.applyFocusChangesIfNeeded();

    expect(policy.previous(a), isTrue);
    manager.applyFocusChangesIfNeeded();
    expect(manager.primaryFocus, b);
  });

  test('skipTraversal nodes are excluded', () {
    var policy = ReadingOrderTraversalPolicy();
    var a = _FixedNode(CellRect.fromTLWH(0, 0, 4, 1));
    var skipped = _FixedNode(CellRect.fromTLWH(0, 10, 4, 1))
      ..skipTraversal = true;
    var manager = FocusManager();
    manager.rootScope.debugAttachChild(a);
    manager.rootScope.debugAttachChild(skipped);
    expect(policy.next(a), isFalse); // only one traversable node
  });

  test('directional traversal moves to the nearest node in a direction', () {
    var manager = FocusManager();
    var policy = DirectionalFocusTraversalPolicy();
    var topLeft = _FixedNode(CellRect.fromTLWH(0, 0, 6, 3));
    var topRight = _FixedNode(CellRect.fromTLWH(0, 20, 6, 3));
    var bottomLeft = _FixedNode(CellRect.fromTLWH(10, 0, 6, 3));
    for (var n in [topLeft, topRight, bottomLeft]) {
      manager.rootScope.debugAttachChild(n);
    }
    topLeft.requestFocus();
    manager.applyFocusChangesIfNeeded();

    expect(policy.inDirection(topLeft, TraversalDirection.right), isTrue);
    manager.applyFocusChangesIfNeeded();
    expect(manager.primaryFocus, topRight);

    expect(policy.inDirection(topLeft, TraversalDirection.down), isTrue);
    manager.applyFocusChangesIfNeeded();
    expect(manager.primaryFocus, bottomLeft);
  });

  test('directional traversal returns false when nothing lies that way', () {
    var manager = FocusManager();
    var policy = DirectionalFocusTraversalPolicy();
    var only = _FixedNode(CellRect.fromTLWH(0, 0, 6, 3));
    manager.rootScope.debugAttachChild(only);
    expect(policy.inDirection(only, TraversalDirection.up), isFalse);
  });
}
