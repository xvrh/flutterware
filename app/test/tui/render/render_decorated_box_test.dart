import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

List<String> dump(CellBuffer b) => [
      for (var r = 0; r < b.rows; r++)
        String.fromCharCodes([
          for (var c = 0; c < b.cols; c++) b.get(r, c).rune,
        ]),
    ];

class _FixedBox extends RenderBox {
  _FixedBox(this.natural);
  CellSize natural;

  @override
  void performLayout() {
    size = constraints.constrain(natural);
  }
}

void main() {
  group('RenderDecoratedBox', () {
    test('size delegates to the child', () {
      var child = _FixedBox(CellSize(4, 6));
      var box = RenderDecoratedBox(
        decoration: BoxDecoration(border: BoxBorder()),
        child: child,
      );
      box.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(box.size, CellSize(4, 6));
    });

    test('with no child, size is the smallest allowed', () {
      var box = RenderDecoratedBox(decoration: BoxDecoration());
      box.layout(BoxConstraints(minWidth: 2, minHeight: 3));
      expect(box.size, CellSize(3, 2));
    });

    test('paints the border around the box perimeter', () {
      var child = _FixedBox(CellSize(3, 5));
      var box = RenderDecoratedBox(
        decoration:
            BoxDecoration(border: BoxBorder(chars: BorderChars.ascii())),
        child: child,
      );
      box.layout(BoxConstraints.tight(CellSize(3, 5)));
      var buffer = CellBuffer(3, 5);
      box.paint(Painter(buffer));
      expect(dump(buffer), ['+---+', '|   |', '+---+']);
    });

    test('paints the fill behind the child', () {
      var child = _FixedBox(CellSize(2, 2));
      var box = RenderDecoratedBox(
        decoration: BoxDecoration(fill: Cell(rune: 0x2e)), // '.'
        child: child,
      );
      box.layout(BoxConstraints.tight(CellSize(2, 2)));
      var buffer = CellBuffer(2, 2);
      box.paint(Painter(buffer));
      expect(dump(buffer), ['..', '..']);
    });
  });
}
