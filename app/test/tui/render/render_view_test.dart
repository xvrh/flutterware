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

/// A leaf box that sizes itself to a fixed natural size, clamped to its
/// constraints, and counts how many times it was laid out.
class _CountingBox extends RenderBox {
  _CountingBox(this.natural);

  CellSize natural;
  int layoutCount = 0;

  @override
  void performLayout() {
    layoutCount++;
    size = constraints.constrain(natural);
  }
}

void main() {
  group('RenderTuiView', () {
    test('lays the child out tight to the configuration', () {
      var text = RenderText('hi');
      var view = RenderTuiView(CellSize(3, 6));
      var owner = PipelineOwner();
      view.attach(owner);
      view.child = text;
      view.prepareInitialFrame();

      var buffer = CellBuffer(3, 6);
      view.compositeFrame(Painter(buffer));
      expect(text.size, CellSize(3, 6));
    });

    test('compositeFrame paints the tree into the buffer', () {
      var text = RenderText('ab');
      var view = RenderTuiView(CellSize(1, 4));
      var owner = PipelineOwner();
      view.attach(owner);
      view.child = text;
      view.prepareInitialFrame();

      var buffer = CellBuffer(1, 4);
      view.compositeFrame(Painter(buffer));
      expect(dump(buffer)[0], 'ab  ');
    });

    test('changing the configuration triggers re-layout', () {
      var text = RenderText('x');
      var view = RenderTuiView(CellSize(1, 1));
      var owner = PipelineOwner();
      view.attach(owner);
      view.child = text;
      view.prepareInitialFrame();
      view.compositeFrame(Painter(CellBuffer(1, 1)));

      view.configuration = CellSize(2, 8);
      view.compositeFrame(Painter(CellBuffer(2, 8)));
      expect(text.size, CellSize(2, 8));
    });

    test('mutating a deep RenderText re-lays only its relayout boundary', () {
      // view -> Row(stretch) of two tight-flex panels, each a Padding+leaf.
      // The right leaf is a counting box so we can prove it is NOT re-laid
      // out when the left subtree is dirtied.
      var leftText = RenderText('left');
      var rightCountingBox = _CountingBox(CellSize(1, 5));
      var left = RenderPadding(padding: EdgeInsets.all(1), child: leftText);
      var right =
          RenderPadding(padding: EdgeInsets.all(1), child: rightCountingBox);
      var row = RenderFlex(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, right],
      );
      row.setFlex(left, 1, fit: FlexFit.tight);
      row.setFlex(right, 2, fit: FlexFit.tight);

      var view = RenderTuiView(CellSize(5, 20));
      var owner = PipelineOwner();
      view.attach(owner);
      view.child = row;
      view.prepareInitialFrame();
      view.compositeFrame(Painter(CellBuffer(5, 20)));

      // The tight flex makes each panel its own relayout boundary, so the
      // initial frame lays the right leaf out exactly once.
      expect(rightCountingBox.layoutCount, 1);

      // Mutating leftText enqueues left (a tight-constrained boundary), not row
      // and not the right panel.
      leftText.text = 'changed';
      owner.flushLayout();

      // Localization proof: dirtying the left subtree did not re-lay the right
      // panel's leaf.
      expect(rightCountingBox.layoutCount, 1);
      // The view size is unchanged and the tree still composes.
      expect(view.size, CellSize(5, 20));
      view.compositeFrame(Painter(CellBuffer(5, 20)));
    });
  });
}
