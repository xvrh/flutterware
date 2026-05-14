import 'dart:async';

import '../tui.dart';

Future<void> main() async {
  await Terminal.run((terminal) async {
    var lastKey = '(none)';
    var keyCount = 0;

    void repaint() {
      terminal.draw((b) {
        final w = terminal.cols;
        final h = terminal.rows;
        const boxW = 36;
        const boxH = 5;
        final row = ((h - boxH) ~/ 2).clamp(0, h);
        final col = ((w - boxW) ~/ 2).clamp(0, w);
        _drawBorder(b, row, col, boxH, boxW);
        b.writeAt(row + 1, col + 2, 'Size: $w × $h');
        b.writeAt(row + 2, col + 2, 'Last key: $lastKey (count: $keyCount)');
        b.writeAt(row + 3, col + 2, '(q to quit)');
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
  });
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
