import 'dart:async';

import 'package:flutterware_app/src/tui/tui.dart';

/// Inline-mode showcase: a build-progress style status panel that coexists
/// with normal shell output above it.
///
/// Exercises inline-mode rendering (anchored region, scrollback preserved),
/// an animated progress bar, colors and styles, and timer-driven repaints
/// through the encodeDiff origin offset.
Future<void> main() async {
  // Normal CLI output printed before the inline region — should remain
  // visible in scrollback above the panel.
  print('--- preceding shell output (this should remain visible above) ---');
  print('flutterware build:');

  await Terminal.run(_statusPanel, mode: const InlineMode(rows: 5));

  print('--- inline region exited; back to normal shell output ---');
}

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

Future<void> _statusPanel(Terminal terminal) async {
  final start = DateTime.now();
  var frames = 0;
  var lastKey = '(none)';
  var keyCount = 0;

  void repaint() {
    frames++;
    terminal.draw((b) {
      final w = terminal.cols;
      _drawBorder(b, 0, 0, terminal.rows, w,
          title: ' flutterware · inline status ');

      final elapsed = DateTime.now().difference(start);
      // Progress cycles 0..100 over ~8s so the bar visibly animates.
      final progress = (elapsed.inMilliseconds ~/ 80) % 101;
      final (label, color) = _phase(progress);

      // Row 1: spinner + phase label + progress bar + percentage.
      b.set(
          1,
          2,
          Cell(
              rune: _spinner[frames % _spinner.length],
              fg: Color.brightYellow));
      b.writeAt(1, 4, label.padRight(15), style: TextStyle.bold, fg: color);
      final barStart = 20;
      final barEnd = w - 7;
      final barWidth = (barEnd - barStart).clamp(0, w);
      final filled = (barWidth * progress / 100).round();
      for (var i = 0; i < barWidth; i++) {
        b.set(
          1,
          barStart + i,
          i < filled
              ? Cell(rune: 0x2588, fg: color)
              : const Cell(rune: 0x2591, fg: Color.brightBlack),
        );
      }
      b.writeAt(1, barEnd + 1, '${progress.toString().padLeft(3)}%', fg: color);

      // Row 2: elapsed time + most recent key.
      b.writeAt(2, 2, 'Elapsed ${_fmtDuration(elapsed)}', fg: Color.brightCyan);
      b.writeAt(2, 20, '· last key: $lastKey ($keyCount)',
          style: TextStyle.dim);

      // Row 3: quit hint.
      b.writeAt(3, 2, 'press q to quit', style: TextStyle.dim);
    });
  }

  repaint();
  final resizeSub = terminal.resizes.listen((_) => repaint());
  final ticker =
      Timer.periodic(const Duration(milliseconds: 100), (_) => repaint());

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
    ticker.cancel();
    await resizeSub.cancel();
  }
}

/// Maps a 0..100 progress value to a build-phase label and accent color.
(String, Color) _phase(int progress) {
  if (progress >= 100) return ('Done', Color.brightGreen);
  if (progress >= 75) return ('Optimizing', Color.brightMagenta);
  if (progress >= 50) return ('Linking', Color.brightBlue);
  if (progress >= 25) return ('Compiling', Color.brightYellow);
  return ('Resolving deps', Color.brightCyan);
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
