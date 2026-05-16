/// Shared test harness for TUI widget-layer tests.
///
/// Provides a canonical [pump], [dump], [Host], [pumpHosted], and [rebuild]
/// that every test file in this directory can import instead of copy-pasting
/// local variants.
library;

import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/widgets/widgets.dart';

/// Reads [b] back as one string per row.
List<String> dump(CellBuffer b) => [
      for (var r = 0; r < b.rows; r++)
        String.fromCharCodes([
          for (var c = 0; c < b.cols; c++) b.get(r, c).rune,
        ]),
    ];

/// Mounts [widget] directly in a fresh binding sized [rows]×[cols], runs one
/// frame, and returns the painted buffer alongside the binding for further
/// frames.
({TuiBinding binding, CellBuffer buffer}) pump(Widget widget,
    {int rows = 6, int cols = 12}) {
  var binding = TuiBinding();
  binding.attachRootWidget(widget);
  binding.handleResize(CellSize(rows, cols));
  var buffer = CellBuffer(rows, cols);
  binding.drawFrame(Painter(buffer));
  return (binding: binding, buffer: buffer);
}

/// A stateful host that swaps its built subtree between frames.
///
/// Tests set [Host.body] before mounting and call [HostState.show] (via
/// [rebuild]) to swap it in subsequent frames.
class Host extends StatefulWidget {
  const Host({super.key});

  static Widget body = const Text('');
  static HostState? last;

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  @override
  void initState() {
    Host.last = this;
  }

  void show(Widget body) => setState(() => Host.body = body);

  @override
  Widget build(BuildContext context) => Host.body;
}

/// Mounts [body] inside a [Host] in a fresh binding sized [rows]×[cols], runs
/// one frame, and returns the binding for further frames.
TuiBinding pumpHosted(Widget body, {int rows = 8, int cols = 12}) {
  Host.body = body;
  var binding = TuiBinding();
  binding.attachRootWidget(const Host());
  binding.handleResize(CellSize(rows, cols));
  binding.drawFrame(Painter(CellBuffer(rows, cols)));
  return binding;
}

/// Swaps [Host]'s subtree to [body] and paints one more frame into a fresh
/// buffer of the given size.
void rebuild(TuiBinding binding, Widget body, {int rows = 8, int cols = 12}) {
  Host.last!.show(body);
  binding.drawFrame(Painter(CellBuffer(rows, cols)));
}
