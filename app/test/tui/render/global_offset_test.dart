import 'package:flutterware_app/src/tui/tui.dart';
import 'package:test/test.dart';

void main() {
  test('globalOffset sums offsets down through a Padding', () {
    var binding = TuiBinding();
    binding.attachRootWidget(
      Padding(
        padding: EdgeInsets.all(2),
        child: SizedBox(width: 3, height: 1),
      ),
    );
    binding.handleResize(CellSize(10, 10));
    binding.drawFrame(Painter(CellBuffer(10, 10)));

    var padding = binding.renderView.child!; // RenderPadding
    var children = <RenderObject>[];
    padding.visitChildren(children.add);

    expect(padding.globalOffset, CellOffset.zero);
    expect(children.single.globalOffset, CellOffset(2, 2));
  });

  test('globalOffset of the render-tree root is zero', () {
    var binding = TuiBinding();
    binding.attachRootWidget(SizedBox());
    binding.handleResize(CellSize(5, 5));
    binding.drawFrame(Painter(CellBuffer(5, 5)));
    expect(binding.renderView.globalOffset, CellOffset.zero);
  });
}
