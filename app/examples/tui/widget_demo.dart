// Stage 4 widget demo. Run in a real terminal:
//   cd app && dart run examples/tui/widget_demo.dart
// Press any key to update the left panel; press 'q' to quit.
//
// This rebuilds the render_tree_demo screen declaratively as StatefulWidgets:
// only LeftPanel rebuilds on each keypress; RightPanel is untouched.

import 'dart:async';

import 'package:flutterware_app/src/tui/tui.dart';

Future<void> main() => runApp(const Demo());

class Demo extends StatelessWidget {
  const Demo({super.key});

  @override
  Widget build(BuildContext context) {
    var header = ConstrainedBox(
      constraints: BoxConstraints.tightFor(height: 1),
      child: DecoratedBox(
        decoration: BoxDecoration(fill: Cell(rune: 0x20, bg: Color.blue)),
        child: Text(
          'flutterware — widget demo',
          fg: Color.brightWhite,
          bg: Color.blue,
          style: TextStyle.bold,
          hAlign: HorizontalAlign.center,
        ),
      ),
    );

    var bodyRow = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 1, child: LeftPanel()),
        Expanded(flex: 2, child: RightPanel()),
      ],
    );

    var footer = ConstrainedBox(
      constraints: BoxConstraints.tightFor(height: 1),
      child: Text(
        "Press any key to update the left panel · 'q' to quit",
        fg: Color.brightBlack,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(flex: 1, child: bodyRow),
        footer,
      ],
    );
  }
}

class LeftPanel extends StatefulWidget {
  const LeftPanel({super.key});

  @override
  State<LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends State<LeftPanel> {
  var _counter = 0;
  StreamSubscription<KeyEvent>? _keySub;
  var _subscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_subscribed) {
      _subscribed = true;
      _keySub = TerminalApp.of(context).keys.listen((event) {
        if (event is CharKey && event.rune == 0x71 /* 'q' */) {
          TerminalApp.of(context).exit();
        } else {
          setState(() => _counter++);
        }
      });
    }
  }

  @override
  void dispose() {
    _keySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var title = Text('Left panel', fg: Color.cyan, style: TextStyle.bold);
    var body = Text(
      _counter == 0
          ? 'The widget tree lays this panel out with BoxConstraints '
              'and a Column. Press a key to mutate this text.'
          : 'Updated $_counter time(s). Only the left panel '
              'subtree rebuilt — the right panel is untouched.',
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: BoxBorder(chars: BorderChars.rounded(), fg: Color.cyan),
      ),
      child: Padding(
        padding: EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [title, body],
        ),
      ),
    );
  }
}

class RightPanel extends StatelessWidget {
  const RightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: BoxBorder(chars: BorderChars.rounded(), fg: Color.magenta),
      ),
      child: Padding(
        padding: EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Right panel', fg: Color.magenta, style: TextStyle.bold),
            Text(
              'This panel is a relayout boundary: when the left panel '
              'updates, only its subtree rebuilds. Both panels share one '
              'Row, sized by flex factors (left 1, right 2).',
            ),
          ],
        ),
      ),
    );
  }
}
