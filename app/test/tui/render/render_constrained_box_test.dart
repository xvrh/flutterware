import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

class _FixedBox extends RenderBox {
  _FixedBox(this.natural);
  CellSize natural;

  @override
  void performLayout() {
    size = constraints.constrain(natural);
  }

  @override
  int computeMaxIntrinsicWidth(int height) => natural.cols;

  @override
  int computeMaxIntrinsicHeight(int width) => natural.rows;
}

void main() {
  group('RenderConstrainedBox', () {
    test('imposes a tight height on the child', () {
      var child = _FixedBox(CellSize(99, 8));
      var box = RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tightFor(height: 1),
        child: child,
      );
      box.layout(BoxConstraints(maxWidth: 40, maxHeight: 40));
      expect(child.size, CellSize(1, 8));
      expect(box.size, CellSize(1, 8));
    });

    test('additional constraints are clamped within incoming constraints', () {
      var child = _FixedBox(CellSize(5, 5));
      var box = RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tight(CellSize(100, 100)),
        child: child,
      );
      // Parent only allows up to 10x10, so the child cannot exceed that.
      box.layout(BoxConstraints(maxWidth: 10, maxHeight: 10));
      expect(child.size, CellSize(10, 10));
    });

    test('with no child, sizes from the enforced constraints', () {
      var box = RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tight(CellSize(3, 4)),
      );
      box.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(box.size, CellSize(3, 4));
    });
  });
}
