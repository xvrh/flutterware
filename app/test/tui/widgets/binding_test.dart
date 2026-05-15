import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

import '_harness.dart';

/// Paints one more frame into a fresh buffer sized [rows]x[cols].
CellBuffer reframe(TuiBinding binding, int rows, int cols) {
  var buffer = CellBuffer(rows, cols);
  binding.handleResize(CellSize(rows, cols));
  binding.drawFrame(Painter(buffer));
  return buffer;
}

/// A counter widget whose [State] is reachable for tests via [Counter.last].
class Counter extends StatefulWidget {
  const Counter({super.key});

  static CounterState? last;

  @override
  State<Counter> createState() => CounterState();
}

class CounterState extends State<Counter> {
  int value = 0;

  @override
  void initState() {
    Counter.last = this;
  }

  void bump() => setState(() => value += 1);

  @override
  Widget build(BuildContext context) => Text('$value');
}

void main() {
  test('drawFrame runs build -> layout -> paint end to end', () {
    var r = pump(const Text('hello'), rows: 1, cols: 8);
    expect(dump(r.buffer)[0], 'hello   ');
    // The render tree was spliced and laid out.
    expect(r.binding.renderView.child, isA<RenderText>());
    expect((r.binding.renderView.child! as RenderText).size, CellSize(1, 8));
  });

  test('a setState-driven counter shows the new value after a second frame',
      () {
    var r = pump(const Counter(), rows: 1, cols: 4);
    expect(dump(r.buffer)[0], '0   ');

    Counter.last!.bump();
    var second = reframe(r.binding, 1, 4);
    expect(dump(second)[0], '1   ');

    Counter.last!.bump();
    Counter.last!.bump();
    var third = reframe(r.binding, 1, 4);
    expect(dump(third)[0], '3   ');
  });

  test('handleResize changes configuration and the next frame re-lays out', () {
    var r = pump(const Text('x'), rows: 1, cols: 1);
    expect(r.binding.renderView.configuration, CellSize(1, 1));
    expect((r.binding.renderView.child! as RenderText).size, CellSize(1, 1));

    var bigger = reframe(r.binding, 3, 10);
    expect(r.binding.renderView.configuration, CellSize(3, 10));
    expect((r.binding.renderView.child! as RenderText).size, CellSize(3, 10));
    expect(dump(bigger)[0], 'x         ');
  });

  test('attachRootWidget mounts the root and prepares the view', () {
    var binding = TuiBinding();
    binding.attachRootWidget(const Text('a'));
    expect(binding.rootElement, isNotNull);
    expect(binding.rootElement!.mounted, isTrue);
    // The render view exists and is attached even before the first frame.
    expect(binding.renderView, isNotNull);
  });

  test('onFrameNeeded fires when a mounted setState schedules a build', () {
    var r = pump(const Counter(), rows: 1, cols: 4);
    var frames = 0;
    r.binding.onFrameNeeded = () => frames += 1;

    Counter.last!.bump();
    expect(frames, 1, reason: 'first dirty element of an idle owner');

    // A second setState before the frame is drained must not re-fire.
    Counter.last!.bump();
    expect(frames, 1);
  });
}
