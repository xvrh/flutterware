// Stage 2 paint-kit demo. Run in a real terminal:
//   cd app && dart run examples/tui/paint_kit_demo.dart
// Press 'q' to quit.

import 'package:flutterware_app/src/tui/tui.dart';

const _lorem = 'The paint kit draws borders, fills, lines and word-wrapped '
    'text into a shared cell buffer. Every helper routes through one clipped '
    'write path, so a panel can never bleed past its own rectangle.';

const _overflow = 'This sentence is deliberately much wider and taller than '
    'the panel that contains it, to prove the clip holds. ';

void _paint(CellBuffer buffer) {
  var painter = Painter(buffer);
  painter.fill(Cell(rune: 0x20)); // blank background

  // Panel 1: rounded border, centered bold title.
  var panel1 = CellRect.fromTLWH(1, 2, 30, 5);
  painter.drawBorder(panel1, chars: BorderChars.rounded(), fg: Color.cyan);
  painter.drawText(
    panel1.deflate(1),
    'Paint kit',
    hAlign: HorizontalAlign.center,
    vAlign: VerticalAlign.center,
    style: TextStyle.bold,
  );

  // Panel 2: double border, wrapped paragraph.
  var panel2 = CellRect.fromTLWH(1, 35, 40, 9);
  painter.drawBorder(panel2, chars: BorderChars.double(), fg: Color.yellow);
  painter.drawText(panel2.deflate(1), _lorem);

  // Panel 3: clipping demo. A child painter is translated into the panel
  // interior and clipped to it; the text it draws is far too wide and tall
  // and must not escape the panel.
  var panel3 = CellRect.fromTLWH(8, 2, 30, 7);
  painter.drawBorder(panel3, chars: BorderChars.thick(), fg: Color.magenta);
  var interior = panel3.deflate(1);
  var clipped = painter
      .translate(interior.offset)
      .clip(CellRect.fromOffsetSize(CellOffset.zero, interior.size));
  clipped.drawText(
    CellRect.fromTLWH(0, 0, 60, 50),
    _overflow * 3,
    fg: Color.brightGreen,
  );

  // Footer.
  painter.drawText(
    CellRect.fromTLWH(buffer.rows - 1, 0, buffer.cols, 1),
    "Press 'q' to quit",
    fg: Color.brightBlack,
  );
}

Future<void> main() async {
  await Terminal.run((terminal) async {
    terminal.draw(_paint);
    var resizeSub = terminal.resizes.listen((_) => terminal.draw(_paint));
    try {
      await for (final event in terminal.keys) {
        if (event is CharKey && event.rune == 0x71 /* 'q' */) break;
      }
    } finally {
      await resizeSub.cancel();
    }
  });
}
