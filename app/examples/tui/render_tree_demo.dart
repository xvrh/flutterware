// Stage 3 render-tree demo. Run in a real terminal:
//   cd app && dart run examples/tui/render_tree_demo.dart
// Press any key to update the left panel; press 'q' to quit.

import 'package:flutterware_app/src/tui/tui.dart';

const _leftLorem = 'The render tree lays this panel out with BoxConstraints '
    'and a RenderFlex column. Press a key to mutate this text.';

const _rightLorem = 'This panel is a relayout boundary: when the left panel '
    'updates, only its subtree is laid out again. Both panels share one '
    'RenderFlex row, sized by flex factors (left 1, right 2).';

late RenderText _leftBody;
var _counter = 0;

RenderBox _panel(String title, RenderText body, Color accent) {
  return RenderDecoratedBox(
    decoration: BoxDecoration(
      border: BoxBorder(chars: BorderChars.rounded(), fg: accent),
    ),
    child: RenderPadding(
      padding: EdgeInsets.all(1),
      child: RenderFlex(
        direction: Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RenderText(title, fg: accent, style: TextStyle.bold),
          body,
        ],
      ),
    ),
  );
}

RenderBox _buildScreen() {
  var header = RenderConstrainedBox(
    additionalConstraints: BoxConstraints.tightFor(height: 1),
    child: RenderDecoratedBox(
      decoration: BoxDecoration(fill: Cell(rune: 0x20, bg: Color.blue)),
      child: RenderText(
        'flutterware — render tree demo',
        fg: Color.brightWhite,
        bg: Color.blue,
        style: TextStyle.bold,
        hAlign: HorizontalAlign.center,
      ),
    ),
  );

  _leftBody = RenderText(_leftLorem);
  var left = _panel('Left panel', _leftBody, Color.cyan);
  var right = _panel('Right panel', RenderText(_rightLorem), Color.magenta);
  var row = RenderFlex(
    direction: Axis.horizontal,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [left, right],
  );
  row.setFlex(left, 1, fit: FlexFit.tight);
  row.setFlex(right, 2, fit: FlexFit.tight);

  var footer = RenderConstrainedBox(
    additionalConstraints: BoxConstraints.tightFor(height: 1),
    child: RenderText(
      "Press any key to update the left panel · 'q' to quit",
      fg: Color.brightBlack,
    ),
  );

  var screen = RenderFlex(
    direction: Axis.vertical,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [header, row, footer],
  );
  screen.setFlex(row, 1, fit: FlexFit.tight);
  return screen;
}

Future<void> main() async {
  await Terminal.run((terminal) async {
    var view = RenderTuiView(CellSize.zero);
    var owner = PipelineOwner();
    view.attach(owner);
    view.child = _buildScreen();
    view.prepareInitialFrame();

    void render() {
      terminal.draw((buffer) {
        view.configuration = CellSize(buffer.rows, buffer.cols);
        view.compositeFrame(Painter(buffer));
      });
    }

    render();
    var resizeSub = terminal.resizes.listen((_) => render());
    try {
      await for (final event in terminal.keys) {
        if (event is CharKey && event.rune == 0x71 /* 'q' */) break;
        _counter++;
        _leftBody.text = 'Updated $_counter time(s). Only the left panel '
            'subtree was laid out again — the right panel is untouched.';
        render();
      }
    } finally {
      await resizeSub.cancel();
    }
  });
}
