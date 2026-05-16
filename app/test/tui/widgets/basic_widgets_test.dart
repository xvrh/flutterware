import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  test('Text produces a RenderText carrying its fields', () {
    var r = pump(const Text('hi',
        fg: Color.brightWhite,
        style: TextStyle.bold,
        hAlign: HorizontalAlign.center));
    var ro = r.binding.renderView.child! as RenderText;
    expect(ro.text, 'hi');
    expect(ro.fg, Color.brightWhite);
    expect(ro.style, TextStyle.bold);
    expect(ro.hAlign, HorizontalAlign.center);
  });

  test('Padding produces a RenderPadding and offsets its child', () {
    var r = pump(const Padding(padding: EdgeInsets.all(1), child: Text('hi')));
    var ro = r.binding.renderView.child! as RenderPadding;
    expect(ro.padding, EdgeInsets.all(1));
    // EdgeInsets.all(1) puts 'h' at row 1, col 1.
    expect(dump(r.buffer)[1][1], 'h');
  });

  test('ConstrainedBox produces a RenderConstrainedBox with its constraints',
      () {
    var r = pump(const ConstrainedBox(
        constraints: BoxConstraints.tightFor(width: 3, height: 2),
        child: Text('x')));
    var ro = r.binding.renderView.child! as RenderConstrainedBox;
    expect(
        ro.additionalConstraints, BoxConstraints.tightFor(width: 3, height: 2));
  });

  test('SizedBox builds a ConstrainedBox with tight constraints', () {
    var r = pump(const SizedBox(width: 4, height: 2, child: Text('x')));
    // SizedBox is a StatelessWidget wrapping a ConstrainedBox.
    expect(r.binding.renderView.child, isA<RenderConstrainedBox>());
    var child = (r.binding.renderView.child! as RenderConstrainedBox).child;
    expect(child, isA<RenderText>());
  });

  test('DecoratedBox produces a RenderDecoratedBox with its decoration', () {
    var decoration = BoxDecoration(fill: Cell(rune: 0x20, bg: Color.blue));
    var r = pump(DecoratedBox(decoration: decoration, child: const Text('x')));
    var ro = r.binding.renderView.child! as RenderDecoratedBox;
    expect(ro.decoration, decoration);
  });

  test('Row produces a horizontal RenderFlex', () {
    var r = pump(const Row(children: [Text('a'), Text('b')]));
    var ro = r.binding.renderView.child! as RenderFlex;
    expect(ro.direction, Axis.horizontal);
    expect(ro.children.length, 2);
  });

  test('Column produces a vertical RenderFlex and lays children in rows', () {
    var r = pump(const Column(children: [Text('a'), Text('b')]));
    var ro = r.binding.renderView.child! as RenderFlex;
    expect(ro.direction, Axis.vertical);
    expect(dump(r.buffer)[0][0], 'a');
    expect(dump(r.buffer)[1][0], 'b');
  });

  test('Flex field changes propagate to the render object on rebuild', () {
    // Drive a rebuild that changes mainAxisAlignment via a stateful host.
    var r = pump(const _AlignHost());
    var ro = r.binding.renderView.child! as RenderFlex;
    expect(ro.mainAxisAlignment, MainAxisAlignment.start);

    _AlignHost.last!.flip();
    r.binding.drawFrame(Painter(CellBuffer(6, 12)));
    expect(ro.mainAxisAlignment, MainAxisAlignment.center);
  });

  test('a small painted tree reads back the expected cells', () {
    var r = pump(const Padding(padding: EdgeInsets.all(1), child: Text('hi')),
        rows: 3, cols: 6);
    var rowsOut = dump(r.buffer);
    expect(rowsOut[0], '      ');
    expect(rowsOut[1].startsWith(' hi'), isTrue);
  });
}

/// A stateful host that flips its Flex's mainAxisAlignment on demand.
class _AlignHost extends StatefulWidget {
  const _AlignHost();

  static _AlignHostState? last;

  @override
  State<_AlignHost> createState() => _AlignHostState();
}

class _AlignHostState extends State<_AlignHost> {
  var alignment = MainAxisAlignment.start;

  @override
  void initState() {
    _AlignHost.last = this;
  }

  void flip() => setState(() => alignment = MainAxisAlignment.center);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: alignment, children: const [Text('a')]);
}
