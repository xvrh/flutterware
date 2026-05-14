import 'dart:async';

import '../tui.dart';

Future<void> main() async {
  // Print some normal CLI output above the inline region first, so we can
  // visually confirm the scrollback is preserved.
  print('--- preceding shell output (this should remain visible above) ---');
  print('flutterware status:');

  await Terminal.run((terminal) async {
    var lastKey = '(none)';
    var keyCount = 0;

    void repaint() {
      terminal.draw((b) {
        final w = terminal.cols;
        _drawBorder(b, 0, 0, terminal.rows, w);
        b.writeAt(1, 2, 'Inline region: $w cols × ${terminal.rows} rows');
        b.writeAt(2, 2, 'Last key: $lastKey (count: $keyCount)');
        b.writeAt(3, 2, '(q to quit)');
      });
    }

    repaint();
    final resizeSub = terminal.resizes.listen((_) => repaint());

    try {
      await for (final event in terminal.keys) {
        keyCount++;
        lastKey = _describe(event);
        if (event is CharKey && event.rune == 0x71 /* 'q' */) break;
        if (event is CharKey &&
            event.rune == 0x63 /* 'c' */ &&
            event.modifiers.contains(Modifier.ctrl)) {
          break;
        }
        repaint();
      }
    } finally {
      await resizeSub.cancel();
    }
  }, mode: const InlineMode(rows: 5));

  print('--- inline region exited; back to normal shell output ---');
}

void _drawBorder(CellBuffer b, int row, int col, int rows, int cols) {
  const tl = 0x250C, tr = 0x2510, bl = 0x2514, br = 0x2518;
  const h = 0x2500, v = 0x2502;
  b.set(row, col, const Cell(rune: tl));
  b.set(row, col + cols - 1, const Cell(rune: tr));
  b.set(row + rows - 1, col, const Cell(rune: bl));
  b.set(row + rows - 1, col + cols - 1, const Cell(rune: br));
  for (var c = col + 1; c < col + cols - 1; c++) {
    b.set(row, c, const Cell(rune: h));
    b.set(row + rows - 1, c, const Cell(rune: h));
  }
  for (var r = row + 1; r < row + rows - 1; r++) {
    b.set(r, col, const Cell(rune: v));
    b.set(r, col + cols - 1, const Cell(rune: v));
  }
}

String _describe(KeyEvent event) {
  final mods = event.modifiers.isEmpty
      ? ''
      : '${event.modifiers.map((m) => m.name).join('+')}+';
  return switch (event) {
    CharKey(:final rune) => '$mods${String.fromCharCode(rune)} (0x${rune.toRadixString(16)})',
    SpecialKey(:final code) => '$mods${code.name}',
  };
}
