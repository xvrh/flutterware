import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

import '_harness.dart' as harness;

/// Mounts [widget] in a binding and runs one frame; returns the binding.
TuiBinding pump(Widget widget, {int rows = 4, int cols = 10}) =>
    harness.pump(widget, rows: rows, cols: cols).binding;

/// A widget whose subtree is swapped between frames by mutating [App.body].
class App extends StatefulWidget {
  const App({super.key});

  static Widget body = const Text('');
  static AppState? last;

  @override
  State<App> createState() => AppState();
}

class AppState extends State<App> {
  @override
  void initState() {
    App.last = this;
  }

  void rebuildWith(Widget body) => setState(() => App.body = body);

  @override
  Widget build(BuildContext context) => App.body;
}

void main() {
  test('Column of Texts yields a RenderFlex with RenderText children in order',
      () {
    App.body = const Column(children: [Text('a'), Text('b')]);
    var binding = pump(const App());

    var flex = binding.renderView.child;
    expect(flex, isA<RenderFlex>());
    var children = (flex! as RenderFlex).children;
    expect(children.length, 2);
    expect(children.every((c) => c is RenderText), isTrue);
    expect((children[0] as RenderText).text, 'a');
    expect((children[1] as RenderText).text, 'b');
  });

  test('rebuild with a changed first child reuses the same RenderText', () {
    App.body = const Column(children: [Text('a'), Text('b')]);
    var binding = pump(const App());
    var first =
        (binding.renderView.child! as RenderFlex).children[0] as RenderText;
    expect(first.text, 'a');

    App.last!.rebuildWith(const Column(children: [Text('a2'), Text('b')]));
    binding.drawFrame(Painter(CellBuffer(4, 10)));

    var firstAfter =
        (binding.renderView.child! as RenderFlex).children[0] as RenderText;
    // Same widget type + keyless => the element and render object are reused.
    expect(identical(first, firstAfter), isTrue);
    expect(firstAfter.text, 'a2');
  });

  test('createRenderObject builds the configured render object type', () {
    var binding =
        pump(const Padding(padding: EdgeInsets.all(1), child: Text('hi')));
    expect(binding.renderView.child, isA<RenderPadding>());
    expect(
        (binding.renderView.child! as RenderPadding).child, isA<RenderText>());
  });

  test('replacing a single child with a different widget type re-splices', () {
    App.body = const Padding(padding: EdgeInsets.all(0), child: Text('x'));
    var binding = pump(const App());
    expect(
        (binding.renderView.child! as RenderPadding).child, isA<RenderText>());

    App.last!.rebuildWith(const Padding(
        padding: EdgeInsets.all(0),
        child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: 1), child: Text('y'))));
    binding.drawFrame(Painter(CellBuffer(4, 10)));

    expect((binding.renderView.child! as RenderPadding).child,
        isA<RenderConstrainedBox>());
  });
}
