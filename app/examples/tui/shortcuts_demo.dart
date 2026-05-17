// Stage 4.5b shortcuts demo. Run in a real terminal:
//   cd app && dart run examples/tui/shortcuts_demo.dart
// Tab / Shift-Tab cycle focus, arrows move directionally. Enter increments the
// focused panel's counter; panel D also accepts '+'. Escape or q quits.

import 'dart:async';

import 'package:flutterware_app/src/tui/tui.dart';

/// An `Action<ActivateIntent>` that runs a callback.
class _CallbackActivate extends Action<ActivateIntent> {
  _CallbackActivate(this.onInvoke);
  final void Function() onInvoke;
  @override
  Object? invoke(ActivateIntent intent) {
    onInvoke();
    return null;
  }
}

/// An `Action<DismissIntent>` that runs a callback.
class _CallbackDismiss extends Action<DismissIntent> {
  _CallbackDismiss(this.onInvoke);
  final void Function() onInvoke;
  @override
  Object? invoke(DismissIntent intent) {
    onInvoke();
    return null;
  }
}

/// A focusable panel with a counter incremented via [ActivateIntent].
///
/// Wraps its [Focus] in an [Actions] so the focused-path lookup finds the
/// increment action. When [activateKey] is set, an extra [Shortcuts] maps that
/// key to [ActivateIntent] for this panel only.
class CounterPanel extends StatefulWidget {
  const CounterPanel({
    required this.label,
    this.autofocus = false,
    this.activateKey,
    super.key,
  });

  final String label;
  final bool autofocus;
  final KeyEvent? activateKey;

  @override
  State<CounterPanel> createState() => _CounterPanelState();
}

class _CounterPanelState extends State<CounterPanel> {
  int _count = 0;

  void _increment() => setState(() => _count++);

  @override
  Widget build(BuildContext context) {
    Widget panel = Actions(
      actions: {ActivateIntent: _CallbackActivate(_increment)},
      child: Focus(
        autofocus: widget.autofocus,
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
                  Text(widget.label, fg: accent, style: TextStyle.bold),
                  Text('count: $_count',
                      fg: focused ? Color.brightWhite : Color.brightBlack),
                ],
              ),
            ),
          );
        }),
      ),
    );
    var activateKey = widget.activateKey;
    if (activateKey != null) {
      panel = Shortcuts(
        shortcuts: {activateKey: const ActivateIntent()},
        child: panel,
      );
    }
    return panel;
  }
}

/// Root of the demo: a 2x2 grid wrapped in an Actions for Escape-to-quit.
class ShortcutsDemoApp extends StatefulWidget {
  const ShortcutsDemoApp({super.key});

  @override
  State<ShortcutsDemoApp> createState() => _ShortcutsDemoState();
}

class _ShortcutsDemoState extends State<ShortcutsDemoApp> {
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
    var exit = TerminalApp.of(context).exit;
    return Actions(
      actions: {DismissIntent: _CallbackDismiss(exit)},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'shortcuts demo - Tab/arrows - Enter activates - Esc/q quits',
            fg: Color.brightWhite,
            style: TextStyle.bold,
          ),
          SizedBox(height: 1),
          _row(const [
            CounterPanel(label: 'panel A', autofocus: true),
            CounterPanel(label: 'panel B'),
          ]),
          SizedBox(height: 1),
          _row(const [
            CounterPanel(label: 'panel C'),
            CounterPanel(
              label: 'panel D (+)',
              activateKey: CharKey(rune: 0x2b /* + */, modifiers: {}),
            ),
          ]),
        ],
      ),
    );
  }
}

Future<void> main() => runApp(const ShortcutsDemoApp());
