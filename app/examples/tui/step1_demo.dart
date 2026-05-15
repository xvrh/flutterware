import 'dart:async';

import 'package:flutterware_app/src/tui/tui.dart';

/// Full-screen feature showcase for the stage 1 TUI engine.
///
/// Exercises colors (ANSI + RGB), text styles, the encodeDiff style-reset
/// path, live timer-driven repaints, resize handling, and key input.
Future<void> main() async {
  await Terminal.run(_showcase);
}

const _ansiColors = <(String, Color)>[
  ('black', Color.black),
  ('red', Color.red),
  ('green', Color.green),
  ('yellow', Color.yellow),
  ('blue', Color.blue),
  ('magenta', Color.magenta),
  ('cyan', Color.cyan),
  ('white', Color.white),
  ('brightBlack', Color.brightBlack),
  ('brightRed', Color.brightRed),
  ('brightGreen', Color.brightGreen),
  ('brightYellow', Color.brightYellow),
  ('brightBlue', Color.brightBlue),
  ('brightMagenta', Color.brightMagenta),
  ('brightCyan', Color.brightCyan),
  ('brightWhite', Color.brightWhite),
];

// Braille spinner frames.
const _spinner = [
  0x280B,
  0x2819,
  0x2839,
  0x2838,
  0x283C,
  0x2834,
  0x2826,
  0x2827,
  0x2807,
  0x280F,
];

Future<void> _showcase(Terminal terminal) async {
  final startTime = DateTime.now();
  var frames = 0;
  final recentKeys = <String>[];

  void repaint() {
    frames++;
    terminal.draw((b) {
      final w = terminal.cols;
      final h = terminal.rows;
      _drawBorder(b, 0, 0, h, w,
          title: ' flutterware TUI engine — feature showcase ');

      var row = 2;

      // ANSI foreground swatches: a solid block in each of the 16 colors.
      b.writeAt(row, 3, 'ANSI fg:', style: TextStyle.bold);
      for (var i = 0; i < _ansiColors.length; i++) {
        final c = Cell(rune: 0x2588, fg: _ansiColors[i].$2);
        b.set(row, 13 + i * 2, c);
        b.set(row, 13 + i * 2 + 1, c);
      }
      row++;

      // ANSI background swatches: spaces painted with each background color.
      b.writeAt(row, 3, 'ANSI bg:', style: TextStyle.bold);
      for (var i = 0; i < _ansiColors.length; i++) {
        final c = Cell(rune: 0x20, bg: _ansiColors[i].$2);
        b.set(row, 13 + i * 2, c);
        b.set(row, 13 + i * 2 + 1, c);
      }
      row += 2;

      // 24-bit RGB gradient strip (red → green, constant blue).
      b.writeAt(row, 3, 'RGB:', style: TextStyle.bold);
      final stripWidth = (w - 16).clamp(0, 64);
      for (var i = 0; i < stripWidth; i++) {
        final t = stripWidth <= 1 ? 0.0 : i / (stripWidth - 1);
        final color = Color.rgb(
          (t * 255).round(),
          ((1 - t) * 255).round(),
          128,
        );
        b.set(row, 13 + i, Cell(rune: 0x2588, fg: color));
      }
      row += 2;

      // Text styles — adjacent styled/unstyled cells exercise the
      // encodeDiff style-reset branch.
      b.writeAt(row, 3, 'Styles:', style: TextStyle.bold);
      var c = 13;
      for (final (label, style) in const [
        ('Bold', TextStyle.bold),
        ('Dim', TextStyle.dim),
        ('Italic', TextStyle.italic),
        ('Underline', TextStyle.underline),
        ('Reverse', TextStyle.reverse),
      ]) {
        b.writeAt(row, c, label, style: style);
        c += label.length + 2;
      }
      row += 2;

      // Colored + styled combinations in one row.
      b.writeAt(row, 3, 'Combo:', style: TextStyle.bold);
      b.writeAt(row, 13, 'red+bold', fg: Color.red, style: TextStyle.bold);
      b.writeAt(row, 24, 'green+underline',
          fg: Color.brightGreen, style: TextStyle.underline);
      b.writeAt(row, 42, ' white-on-blue ',
          fg: Color.brightWhite, bg: Color.blue);
      row += 2;

      // Live stats — only these cells change between timer ticks, which
      // proves encodeDiff repaints just the diff (no full-screen redraw).
      final uptime = DateTime.now().difference(startTime);
      b.writeAt(row, 3, 'Uptime:', style: TextStyle.bold);
      b.writeAt(row, 13, _fmtDuration(uptime), fg: Color.brightCyan);
      b.writeAt(row, 26, 'Frames:', style: TextStyle.bold);
      b.writeAt(row, 34, '$frames', fg: Color.brightCyan);
      b.writeAt(row, 46, 'Spinner:', style: TextStyle.bold);
      b.set(
          row,
          55,
          Cell(
              rune: _spinner[frames % _spinner.length],
              fg: Color.brightYellow));
      row += 2;

      // Scrolling log of recent key events.
      b.writeAt(row, 3, 'Recent keys:', style: TextStyle.bold);
      row++;
      for (var i = 0; i < recentKeys.length; i++) {
        b.writeAt(row + i, 5, recentKeys[i], fg: Color.brightBlack);
      }

      b.writeAt(h - 2, 3, 'Press keys to test input · q to quit',
          style: TextStyle.dim);
    });
  }

  repaint();
  final resizeSub = terminal.resizes.listen((_) => repaint());
  // Drive repaints on a timer so the uptime/frames/spinner update live.
  final ticker =
      Timer.periodic(const Duration(milliseconds: 250), (_) => repaint());

  try {
    await for (final event in terminal.keys) {
      recentKeys.insert(0, _describe(event));
      if (recentKeys.length > 6) recentKeys.removeLast();
      if (event is CharKey && event.rune == 0x71 /* 'q' */) break;
      if (event is CharKey &&
          event.rune == 0x63 /* 'c' */ &&
          event.modifiers.contains(Modifier.ctrl)) {
        break;
      }
      repaint();
    }
  } finally {
    ticker.cancel();
    await resizeSub.cancel();
  }
}

void _drawBorder(CellBuffer b, int row, int col, int rows, int cols,
    {String? title}) {
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
  if (title != null) {
    b.writeAt(row, col + 2, title, style: TextStyle.bold);
  }
}

String _fmtDuration(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _describe(KeyEvent event) {
  final mods = event.modifiers.isEmpty
      ? ''
      : '${event.modifiers.map((m) => m.name).join('+')}+';
  return switch (event) {
    CharKey(:final rune) =>
      '$mods${String.fromCharCode(rune)} (0x${rune.toRadixString(16)})',
    SpecialKey(:final code) => '$mods${code.name}',
  };
}
