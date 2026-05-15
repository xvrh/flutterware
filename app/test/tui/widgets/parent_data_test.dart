import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

import '_harness.dart';

/// The parent data of the [RenderFlex]'s single child.
FlexParentData onlyChildParentData(TuiBinding binding) {
  var flex = binding.renderView.child! as RenderFlex;
  return flex.children.single.parentData! as FlexParentData;
}

void main() {
  test('Expanded writes flex and a tight fit into the child FlexParentData',
      () {
    var binding =
        pumpHosted(const Row(children: [Expanded(flex: 2, child: Text('x'))]));
    var pd = onlyChildParentData(binding);
    expect(pd.flex, 2);
    expect(pd.fit, FlexFit.tight);
  });

  test('Flexible writes flex and a loose fit', () {
    var binding =
        pumpHosted(const Row(children: [Flexible(flex: 3, child: Text('x'))]));
    var pd = onlyChildParentData(binding);
    expect(pd.flex, 3);
    expect(pd.fit, FlexFit.loose);
  });

  test('rebuilding with a new flex updates the FlexParentData', () {
    var binding =
        pumpHosted(const Row(children: [Expanded(flex: 2, child: Text('x'))]));
    expect(onlyChildParentData(binding).flex, 2);

    rebuild(
        binding, const Row(children: [Expanded(flex: 5, child: Text('x'))]));
    expect(onlyChildParentData(binding).flex, 5);
    expect(onlyChildParentData(binding).fit, FlexFit.tight);
  });

  test('switching Expanded to Flexible changes the fit', () {
    var binding =
        pumpHosted(const Row(children: [Expanded(flex: 1, child: Text('x'))]));
    expect(onlyChildParentData(binding).fit, FlexFit.tight);

    rebuild(
        binding, const Row(children: [Flexible(flex: 1, child: Text('x'))]));
    expect(onlyChildParentData(binding).fit, FlexFit.loose);
  });

  test('Expanded flex actually drives layout', () {
    // Two Expanded children, flex 1 and 3, in a 16-wide row => 4 and 12 cols.
    var binding = pumpHosted(const Row(children: [
      Expanded(flex: 1, child: Text('a')),
      Expanded(flex: 3, child: Text('b')),
    ]));
    binding.handleResize(CellSize(1, 16));
    binding.drawFrame(Painter(CellBuffer(1, 16)));

    var children =
        (binding.renderView.child! as RenderFlex).children.cast<RenderText>();
    expect(children[0].size.cols, 4);
    expect(children[1].size.cols, 12);
  });
}
