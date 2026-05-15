import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

/// A minimal multi-child RenderObject for exercising the base class.
class _Node extends RenderObject {
  final List<_Node> children = [];

  void append(_Node child) {
    children.add(child);
    adoptChild(child);
  }

  void unappend(_Node child) {
    children.remove(child);
    dropChild(child);
  }

  @override
  void redepthChildren() {
    for (var c in children) {
      redepthChild(c);
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visitor) {
    for (var c in children) {
      visitor(c);
    }
  }

  @override
  void performLayout() {}
}

void main() {
  group('RenderObject tree', () {
    test('adoptChild sets parent and parentData', () {
      var root = _Node();
      var child = _Node();
      root.append(child);
      expect(child.parent, same(root));
      expect(child.parentData, isA<ParentData>());
    });

    test('dropChild clears parent and parentData', () {
      var root = _Node();
      var child = _Node();
      root.append(child);
      root.unappend(child);
      expect(child.parent, isNull);
      expect(child.parentData, isNull);
    });

    test('depth increases down the tree', () {
      var root = _Node();
      var mid = _Node();
      var leaf = _Node();
      mid.append(leaf);
      root.append(mid);
      expect(root.depth, 0);
      expect(mid.depth, greaterThan(root.depth));
      expect(leaf.depth, greaterThan(mid.depth));
    });
  });

  group('attachment', () {
    test('attach propagates to the whole subtree', () {
      var owner = PipelineOwner();
      var root = _Node();
      var child = _Node();
      root.append(child);
      expect(root.attached, isFalse);
      root.attach(owner);
      expect(root.attached, isTrue);
      expect(child.attached, isTrue);
      expect(child.owner, same(owner));
    });

    test('detach propagates to the whole subtree', () {
      var owner = PipelineOwner();
      var root = _Node();
      var child = _Node();
      root.append(child);
      root.attach(owner);
      root.detach();
      expect(root.attached, isFalse);
      expect(child.attached, isFalse);
    });

    test('a child adopted after attach is attached immediately', () {
      var owner = PipelineOwner();
      var root = _Node()..attach(owner);
      var child = _Node();
      root.append(child);
      expect(child.attached, isTrue);
    });
  });

  group('markNeedsPaint', () {
    test('sets the owner needsPaint flag', () {
      var owner = PipelineOwner();
      var root = _Node()..attach(owner);
      expect(owner.needsPaint, isFalse);
      root.markNeedsPaint();
      expect(owner.needsPaint, isTrue);
      owner.clearNeedsPaint();
      expect(owner.needsPaint, isFalse);
    });
  });
}
