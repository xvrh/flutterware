import 'dart:async';

import 'package:flutterware_app/src/tui/tui.dart';

/// print_above showcase: a simulated `flutter build` whose log lines stream
/// into the terminal scrollback while a status panel stays pinned below.
///
/// Exercises [Terminal.printAbove] (colored log lines into scrollback),
/// the region staying intact and re-anchored after each insert, and a
/// timer-driven animated panel rendered with [Terminal.draw].
Future<void> main() async {
  print('--- flutterware build (print_above demo) ---');
  await Terminal.run(_dashboard, mode: const InlineMode(rows: 5));
  print('--- build finished; back to normal shell output ---');
}

// Braille spinner frames.
const _spinner = [
  0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807,
  0x280F,
];

// A scripted build log: (level, message). level: 0 info, 1 warn, 2 error.
const _script = <(int, String)>[
  (0, 'Resolving dependencies...'),
  (0, 'Got dependencies.'),
  (0, 'Running Gradle task assembleDebug...'),
  (0, 'Compiling lib/main.dart'),
  (0, 'Compiling lib/src/app.dart'),
  (1, 'lib/src/app.dart:42: unused import'),
  (0, 'Compiling lib/src/widgets/home.dart'),
  (0, 'Compiling lib/src/widgets/details.dart'),
  (1, 'lib/src/widgets/details.dart:88: deprecated API'),
  (0, 'Linking native libraries'),
  (2, 'ld: duplicate symbol _kFoo (recovered)'),
  (0, 'Bundling assets'),
  (0, 'Optimizing icon tree-shaking'),
  (0, 'Signing build/app/outputs/apk/debug/app-debug.apk'),
  (0, 'Built build/app/outputs/apk/debug/app-debug.apk (24.1MB)'),
];

Future<void> _dashboard(Terminal terminal) async {
  final start = DateTime.now();
  var frames = 0;
  var emitted = 0;
  var warns = 0;
  var errors = 0;
  var done = false;

  void repaint() {
    frames++;
    terminal.draw((b) {
      final w = terminal.cols;
      _drawBorder(b, 0, 0, terminal.rows, w,
          title: ' flutterware build ');

      final progress = (emitted / _script.length * 100).round();
      final color = done ? Color.brightGreen : Color.brightCyan;

      // Row 1: spinner + phase label.
      b.set(
          1,
          2,
          Cell(
              rune: done ? 0x2714 /* heavy check */
                  : _spinner[frames % _spinner.length],
              fg: color));
      b.writeAt(1, 4, done ? 'Build complete' : 'Building...',
          style: TextStyle.bold, fg: color);

      // Row 2: progress bar + percentage.
      final barStart = 2;
      final barEnd = w - 8;
      final barWidth = (barEnd - barStart).clamp(0, w);
      final filled = (barWidth * progress / 100).round();
      for (var i = 0; i < barWidth; i++) {
        b.set(
          2,
          barStart + i,
          i < filled
              ? Cell(rune: 0x2588, fg: color)
              : const Cell(rune: 0x2591, fg: Color.brightBlack),
        );
      }
      b.writeAt(2, barEnd + 1, '${progress.toString().padLeft(3)}%', fg: color);

      // Row 3: counts + elapsed + quit hint.
      final elapsed = DateTime.now().difference(start);
      b.writeAt(3, 2,
          'warnings $warns   errors $errors   elapsed ${elapsed.inSeconds}s',
          style: TextStyle.dim);
      b.writeAt(3, w - 19, 'press q to quit', style: TextStyle.dim);
    });
  }

  // Quit when the user presses q, or 1.5s after the build finishes.
  final quit = Completer<void>();
  void maybeFinish() {
    if (emitted >= _script.length && !done) {
      done = true;
      Timer(const Duration(milliseconds: 1500), () {
        if (!quit.isCompleted) quit.complete();
      });
    }
  }

  // Emit one scripted log line into the scrollback above the panel.
  void emitLogLine() {
    if (emitted >= _script.length) return;
    final (level, message) = _script[emitted];
    emitted++;
    final (tag, color) = switch (level) {
      2 => ('ERROR', Color.brightRed),
      1 => (' WARN', Color.brightYellow),
      _ => (' INFO', Color.brightGreen),
    };
    if (level == 1) warns++;
    if (level == 2) errors++;
    // The tag is colored; the message is default-colored. Two printTextAbove
    // calls would be two scrollback rows, so build one styled line via the
    // printAbove primitive instead.
    terminal.printAbove(1, (b) {
      b.writeAt(0, 0, tag, fg: color, style: TextStyle.bold);
      b.writeAt(0, 6, message);
    });
    repaint();
    maybeFinish();
  }

  repaint();
  final resizeSub = terminal.resizes.listen((_) => repaint());
  final ticker =
      Timer.periodic(const Duration(milliseconds: 100), (_) => repaint());
  final logTicker =
      Timer.periodic(const Duration(milliseconds: 350), (_) => emitLogLine());

  final keySub = terminal.keys.listen((event) {
    if (event is CharKey && event.rune == 0x71 /* q */) {
      if (!quit.isCompleted) quit.complete();
    }
  });

  try {
    await quit.future;
  } finally {
    ticker.cancel();
    logTicker.cancel();
    await resizeSub.cancel();
    await keySub.cancel();
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
