// Stage 4.5a focus-system demo. Run in a real terminal:
//   cd app && dart run examples/tui/focus_demo.dart
// Tab / Shift-Tab cycle focus, arrows move directionally, q quits.

import 'dart:async';

import 'package:flutterware_app/src/tui/tui.dart';

/// One focusable panel. Its border brightens when it holds focus.
class FocusPanel extends StatelessWidget {
  const FocusPanel({required this.label, this.autofocus = false, super.key});

  final String label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      child: Builder(builder: (context) {
        var focused = Focus.of(context).hasFocus;
        var accent = focused ? Color.brightCyan : Color.brightBlack;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: BoxBorder(
              chars: focused ? BorderChars.double() : BorderChars.rounded(),
              fg: accent,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, fg: accent, style: TextStyle.bold),
                Text('hasFocus: $focused',
                    fg: focused ? Color.brightWhite : Color.brightBlack),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Root of the demo: a 2x2 grid and a key handler for q.
class FocusDemoApp extends StatefulWidget {
  const FocusDemoApp({super.key});

  @override
  State<FocusDemoApp> createState() => _FocusDemoState();
}

class _FocusDemoState extends State<FocusDemoApp> {
  StreamSubscription<KeyEvent>? _keySub;
  bool _subscribed = false;

  @override
  void didChangeDependencies() {
    if (_subscribed) return;
    _subscribed = true;
    var app = TerminalApp.of(context);
    _keySub = app.keys.listen((event) {
      if (event is CharKey && event.rune == 0x71 /* q */) {
        app.exit();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_keySub?.cancel());
  }

  Widget _row(List<Widget> panels) => Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < panels.length; i++) ...[
              if (i > 0) SizedBox(width: 1),
              Expanded(child: panels[i]),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'focus demo - Tab / Shift-Tab - arrows - q to quit',
          fg: Color.brightWhite,
          style: TextStyle.bold,
        ),
        SizedBox(height: 1),
        _row(const [
          FocusPanel(label: 'panel A', autofocus: true),
          FocusPanel(label: 'panel B'),
        ]),
        SizedBox(height: 1),
        // The bottom pair sits in its own FocusScope.
        Expanded(
          child: FocusScope(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Expanded(child: FocusPanel(label: 'panel C')),
                SizedBox(width: 1),
                Expanded(child: FocusPanel(label: 'panel D')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> main() => runApp(const FocusDemoApp());
