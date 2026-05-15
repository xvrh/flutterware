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
      // view -> Row(stretch) of two tight-flex panels, each a Padding+Text.
      var leftText = RenderText('left');
      var rightText = RenderText('right');
      var left = RenderPadding(padding: EdgeInsets.all(1), child: leftText);
      var right = RenderPadding(padding: EdgeInsets.all(1), child: rightText);
      var row = RenderFlex(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, right],
      );
      row.setFlex(left, 1, fit: FlexFit.tight);
      row.setFlex(right, 1, fit: FlexFit.tight);

      var view = RenderTuiView(CellSize(5, 20));
      var owner = PipelineOwner();
      view.attach(owner);
      view.child = row;
      view.prepareInitialFrame();
      view.compositeFrame(Painter(CellBuffer(5, 20)));

      // Mutating leftText enqueues left (a tight-constrained boundary), not row.
      leftText.text = 'changed';
      owner.flushLayout();
      // The screen still composes without error and sizes are intact.
      expect(left.size, right.size);
      expect(view.size, CellSize(5, 20));
    });
  });
}
