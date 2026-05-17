// Stage 4.5a focus-system playground. Run in a real terminal:
//   cd app && dart run examples/tui/focus_playground.dart
//
// A 2x3 grid of focusable counter cards. It exercises every part of the
// focus system at once:
//   - Tab / Shift-Tab          cycle focus in reading order
//   - arrow keys               move focus directionally across the grid
//   - + / - / space            handled by the *focused* card's onKeyEvent
//   - q                        bubbles past every card to the root handler
//
// The focused card glows (double border, lit header). +/- adjust that card's
// counter, space resets it. Arrow/Tab keys are returned `ignored` by the card,
// so they bubble up and the FocusManager's built-in traversal moves focus.

import 'package:flutterware_app/src/tui/tui.dart';

/// The six card accent colors.
const _palette = [
  Color.rgb(0xff, 0x6b, 0x6b),
  Color.rgb(0xfe, 0xca, 0x57),
  Color.rgb(0x1d, 0xd1, 0xa1),
  Color.rgb(0x54, 0xa0, 0xff),
  Color.rgb(0xc4, 0x8d, 0xff),
  Color.rgb(0xff, 0x9f, 0x43),
];

const _labels = ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot'];

/// One focusable counter card.
///
/// The card owns no state — the app holds the counts. It contributes a
/// [Focus] whose `onKeyEvent` consumes `+`/`-`/`space` (returning `handled`)
/// and ignores everything else, so arrows and Tab bubble up to the
/// FocusManager's traversal fallback.
class FocusCard extends StatelessWidget {
  const FocusCard({
    required this.label,
    required this.color,
    required this.count,
    required this.onDelta,
    required this.onReset,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final Color color;
  final int count;
  final void Function(int delta) onDelta;
  final void Function() onReset;
  final bool autofocus;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is CharKey) {
      if (event.rune == 0x2b || event.rune == 0x3d) {
        onDelta(1); // '+' or '='
        return KeyEventResult.handled;
      }
      if (event.rune == 0x2d) {
        onDelta(-1); // '-'
        return KeyEventResult.handled;
      }
      if (event.rune == 0x20) {
        onReset(); // space
        return KeyEventResult.handled;
      }
    }
    // Arrows, Tab and 'q' fall through — the focus chain bubbles them up.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: _onKey,
      child: Builder(builder: (context) {
        var focused = Focus.of(context).hasFocus;
        var dim = Color.rgb(0x4a, 0x4a, 0x5a);

        var header = DecoratedBox(
          decoration: BoxDecoration(
            fill: Cell(rune: 0x20, bg: focused ? color : Color.rgb(38, 38, 50)),
          ),
          child: Text(
            ' $label',
            fg: focused ? Color.rgb(20, 20, 30) : dim,
            style: TextStyle.bold,
          ),
        );

        var body = Padding(
          padding: EdgeInsets.all(1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$count',
                hAlign: HorizontalAlign.center,
                style: TextStyle.bold,
                fg: focused ? Color.brightWhite : dim,
              ),
              SizedBox(height: 1),
              Text(
                focused ? '+   -   space' : '',
                hAlign: HorizontalAlign.center,
                fg: color,
              ),
            ],
          ),
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            fill: Cell(
              rune: 0x20,
              bg: focused ? Color.rgb(26, 30, 44) : Color.rgb(18, 18, 26),
            ),
            border: BoxBorder(
              chars: focused ? BorderChars.double() : BorderChars.rounded(),
              fg: focused ? color : dim,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(child: body),
            ],
          ),
        );
      }),
    );
  }
}

/// Root of the playground. Owns the six counters; handles `q` at the top of
/// the focus chain so it works no matter which card is focused.
class PlaygroundApp extends StatefulWidget {
  const PlaygroundApp({super.key});

  @override
  State<PlaygroundApp> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<PlaygroundApp> {
  final List<int> _counts = List<int>.filled(6, 0);

  void _delta(int index, int delta) =>
      setState(() => _counts[index] = _counts[index] + delta);

  void _reset(int index) => setState(() => _counts[index] = 0);

  /// One grid row of cards, each in an [Expanded] with gaps between.
  Widget _row(List<Widget> cards) => Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(width: 2),
              Expanded(child: cards[i]),
            ],
          ],
        ),
      );

  FocusCard _card(int index) => FocusCard(
        label: _labels[index],
        color: _palette[index],
        count: _counts[index],
        autofocus: index == 0,
        onDelta: (d) => _delta(index, d),
        onReset: () => _reset(index),
      );

  @override
  Widget build(BuildContext context) {
    var total = _counts.fold<int>(0, (sum, c) => sum + c);
    var app = TerminalApp.of(context);

    // A non-focusable, non-traversable Focus that wraps the whole UI. It is an
    // ancestor of every card's focus node, so unhandled keys bubble to it —
    // here it handles 'q'. Tab never lands on it (skipTraversal).
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is CharKey && event.rune == 0x71) {
          app.exit(); // 'q'
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              fill: Cell(rune: 0x20, bg: Color.rgb(30, 30, 46)),
            ),
            child: Row(
              children: [
                Text(
                  ' Focus Playground',
                  fg: Color.brightWhite,
                  style: TextStyle.bold,
                ),
                Expanded(child: SizedBox()),
                Text('total: $total ', fg: Color.brightCyan),
              ],
            ),
          ),
          SizedBox(height: 1),
          _row([_card(0), _card(1), _card(2)]),
          SizedBox(height: 1),
          _row([_card(3), _card(4), _card(5)]),
          SizedBox(height: 1),
          Text(
            '  Tab / Shift-Tab cycle  ·  arrows navigate  ·  '
            '+ / - adjust  ·  space reset  ·  q quit',
            fg: Color.rgb(0x6a, 0x6a, 0x7a),
          ),
        ],
      ),
    );
  }
}

Future<void> main() => runApp(const PlaygroundApp());
