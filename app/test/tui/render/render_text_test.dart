import 'package:flutterware_app/src/tui/buffer.dart';
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

void main() {
  group('RenderText layout', () {
    test('a single short line sizes to its length', () {
      var t = RenderText('hello');
      t.layout(BoxConstraints(maxWidth: 20, maxHeight: 5));
      expect(t.size, CellSize(1, 5));
    });

    test('wraps to the width constraint', () {
      var t = RenderText('one two three four');
      t.layout(BoxConstraints(maxWidth: 8, maxHeight: 10));
      // 'one two' (7), 'three' (5), 'four' (4) -> 3 rows, widest 7.
      expect(t.size.rows, 3);
      expect(t.size.cols, 7);
    });

    test('with wrap off, splits only on newlines', () {
      var t = RenderText('a very long single line here', wrap: false);
      t.layout(BoxConstraints(maxWidth: 6, maxHeight: 4));
      // One logical line; size width clamps to the constraint.
      expect(t.size.rows, 1);
      expect(t.size.cols, 6);
    });

    test('size is clamped to the constraints', () {
      var t = RenderText('abcdefghij');
      t.layout(BoxConstraints.tight(CellSize(2, 4)));
      expect(t.size, CellSize(2, 4));
    });
  });

  group('RenderText intrinsics', () {
    test('max intrinsic width is the longest unwrapped line', () {
      var t = RenderText('short\na much longer line');
      expect(t.getMaxIntrinsicWidth(100), 'a much longer line'.length);
    });

    test('min intrinsic width is the longest word', () {
      var t = RenderText('hi enormously-long-word ok');
      expect(t.getMinIntrinsicWidth(100), 'enormously-long-word'.length);
    });

    test('intrinsic height is the wrapped line count', () {
      var t = RenderText('one two three four');
      expect(t.getMinIntrinsicHeight(8), 3);
    });
  });

  group('RenderText paint', () {
    test('draws the text into the buffer at the origin', () {
      var t = RenderText('hi');
      t.layout(BoxConstraints(maxWidth: 10, maxHeight: 3));
      var buffer = CellBuffer(3, 10);
      t.paint(Painter(buffer));
      expect(dump(buffer)[0].trimRight(), 'hi');
    });
  });

  group('RenderText dirty-tracking', () {
    test('setting text marks needs-layout', () {
      var t = RenderText('a');
      t.layout(BoxConstraints(maxWidth: 10, maxHeight: 3));
      t.text = 'bbbbb';
      // _needsLayout is private; observe it via a fresh layout changing size.
      t.layout(BoxConstraints(maxWidth: 10, maxHeight: 3));
      expect(t.size.cols, 5);
    });
  });
}
