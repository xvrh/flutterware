import 'dart:async';
import 'dart:io';

import 'package:flutterware_app/src/tui/tui.dart';

/// print_above mechanism demo — an instrumented, step-through walkthrough of
/// how [Terminal.printAbove] scrolls log lines into the terminal scrollback
/// above an anchored inline region.
///
/// The bordered inline panel shows the live state of the mechanism: the
/// region's anchor row (`_originRow`), the terminal height, the "pin point",
/// the drift-vs-pinned phase, and how many lines have scrolled off into
/// scrollback. A horizontal gauge stands in for the vertical screen so the
/// region's position is visible at a glance. Each emitted line narrates what
/// that single `printAbove` call did, so the scrollback itself becomes a
/// readable transcript of the mechanism.
///
/// Controls: [space] emit one line · [a] toggle auto-play · [q] quit.
Future<void> main() async {
  print('print_above — scrolling mechanism demo');
  print('');
  print('The bordered panel below is an inline region. Every log line above');
  print('it is emitted by ONE Terminal.printAbove(1, ...) call. The mechanism');
  print('has two phases:');
  print('');
  print('  DRIFTING  the region has empty rows below it, so a new line just');
  print('            pushes the region DOWN — nothing leaves the screen and');
  print('            the anchor row (_originRow) increases by one.');
  print('  PINNED    the region sits on the last screen row, so a new line');
  print('            SCROLLS the screen — the top line drops into real');
  print('            scrollback and the anchor row stays put.');
  print('');
  print('Tip: launch this in a tall terminal with lots of empty space below');
  print('the prompt to watch the DRIFTING phase first. With the prompt near');
  print('the bottom the region anchors there and starts already PINNED.');
  print('');

  await Terminal.run(_demo, mode: const InlineMode(rows: 9));

  print('--- demo exited; the narrated log lines remain in scrollback ---');
}

// Braille spinner frames, for liveness.
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

Future<void> _demo(Terminal terminal) async {
  var emitted = 0;
  var scrolledOff = 0;
  var auto = false;
  var frames = 0;
  var lastNote = 'press [space] to emit the first line';

  int screenHeight() => stdout.terminalLines;
  int pinPoint() => screenHeight() - terminal.rows;

  void repaint() {
    frames++;
    terminal.draw((b) {
      final w = terminal.cols;
      final origin = terminal.originRow;
      final pin = pinPoint();
      final drifting = origin < pin;
      final spin = String.fromCharCode(_spinner[frames % _spinner.length]);

      _drawBorder(b, terminal.rows, w,
          title: ' print_above · scrolling mechanism $spin ');

      // Row 1 — current phase.
      b.writeAt(1, 2, 'PHASE', style: TextStyle.bold);
      if (drifting) {
        b.writeAt(1, 8, 'DRIFTING',
            fg: Color.brightYellow, style: TextStyle.bold);
        b.writeAt(1, 17,
            '— ${pin - origin} row(s) of headroom; next line moves the region down',
            style: TextStyle.dim);
      } else {
        b.writeAt(1, 8, 'PINNED', fg: Color.brightGreen, style: TextStyle.bold);
        b.writeAt(1, 15,
            '— region on the last row; next line scrolls into scrollback',
            style: TextStyle.dim);
      }

      // Row 2 — viewport gauge: a horizontal stand-in for the vertical
      // screen. Left edge = screen row 0, right edge = the last screen row.
      _drawGauge(b, 2, w,
          origin: origin,
          regionRows: terminal.rows,
          screenHeight: screenHeight(),
          scrolledOff: scrolledOff);

      // Row 3 — the last action.
      b.writeAt(3, 2, 'last: $lastNote', style: TextStyle.dim);

      // Row 4/5 — the mechanism's numbers.
      b.writeAt(
          4,
          2,
          'anchor _originRow = ${origin.toString().padLeft(3)}     '
          'screen height = ${screenHeight()}     '
          'region rows = ${terminal.rows}',
          fg: Color.brightCyan);
      b.writeAt(
          5,
          2,
          'pin point (height - region rows) = $pin     '
          'next printAbove ${drifting ? "drifts the region" : "scrolls the screen"}',
          fg: Color.brightCyan);

      // Row 6 — running counts. Every emitted line is either still visible
      // above the region or has scrolled off into scrollback.
      b.writeAt(
          6,
          2,
          'emitted = $emitted      on-screen above = ${emitted - scrolledOff}'
          '      in scrollback = $scrolledOff',
          style: TextStyle.bold);

      // Row 7 — controls.
      final controls =
          '[space] emit   [a] auto:${auto ? "ON " : "off"}   [q] quit';
      final controlsCol = (w - 2 - controls.length).clamp(2, w);
      b.writeAt(7, controlsCol, controls, fg: Color.brightBlack);
    });
  }

  // Emit one log line via a single Terminal.printAbove(1, ...) call and
  // narrate, in the line itself, exactly what that call did.
  void emitNext() {
    final before = terminal.originRow;
    final pin = pinPoint();
    // A one-row printAbove drifts the region down by one row while it has
    // headroom; once pinned, the anchor holds and one line scrolls off.
    final after = before < pin ? before + 1 : before;
    final scrolled = 1 - (after - before); // 0 while drifting, 1 once pinned
    emitted++;
    scrolledOff += scrolled;

    final pinned = scrolled == 1;
    final tag = pinned ? ' SCROLL ' : ' DRIFT  ';
    final tagColor = pinned ? Color.brightGreen : Color.brightYellow;
    final detail = pinned
        ? 'screen scrolled — top line pushed into scrollback; anchor held at $after'
        : 'region pushed down — anchor _originRow $before → $after';

    lastNote = '#$emitted ${pinned ? "SCROLL" : "DRIFT"} — $detail';

    terminal.printAbove(1, (b) {
      b.writeAt(0, 0, '#${emitted.toString().padLeft(3)}',
          fg: Color.brightBlack);
      b.writeAt(0, 5, tag,
          fg: Color.black, bg: tagColor, style: TextStyle.bold);
      b.writeAt(0, 14, 'printAbove(1)  →  $detail');
    });
    repaint();
  }

  repaint();
  final resizeSub = terminal.resizes.listen((_) => repaint());
  // A gentle ticker keeps the spinner alive while idle.
  final spinTicker =
      Timer.periodic(const Duration(milliseconds: 120), (_) => repaint());
  Timer? autoTicker;

  void setAuto(bool on) {
    if (auto == on) return;
    auto = on;
    autoTicker?.cancel();
    autoTicker = on
        ? Timer.periodic(const Duration(milliseconds: 700), (_) => emitNext())
        : null;
    repaint();
  }

  final quit = Completer<void>();
  final keySub = terminal.keys.listen((event) {
    if (event is! CharKey) return;
    switch (event.rune) {
      case 0x71: // q
        if (!quit.isCompleted) quit.complete();
      case 0x20: // space
        emitNext();
      case 0x61: // a
        setAuto(!auto);
    }
  });

  try {
    await quit.future;
  } finally {
    spinTicker.cancel();
    autoTicker?.cancel();
    await resizeSub.cancel();
    await keySub.cancel();
  }
}

/// Draws the viewport gauge on [row]: a horizontal bar standing in for the
/// vertical screen. The region's span is highlighted; as it drifts the block
/// slides right, then sticks at the right edge once pinned. A `N↑` marker on
/// the left counts lines that have scrolled off into scrollback.
void _drawGauge(
  CellBuffer b,
  int row,
  int width, {
  required int origin,
  required int regionRows,
  required int screenHeight,
  required int scrolledOff,
}) {
  final marker = scrolledOff > 0 ? '$scrolledOff↑' : '';
  if (marker.isNotEmpty) {
    b.writeAt(row, 2, marker, fg: Color.brightGreen, style: TextStyle.bold);
  }
  final trackStart = 2 + (marker.isEmpty ? 0 : marker.length + 1) + 1;
  final trackEnd = width - 3;
  final trackLen = trackEnd - trackStart;
  if (trackLen < 4 || screenHeight <= 0) return;

  b.set(row, trackStart - 1, const Cell(rune: 0x5B /* [ */));
  b.set(row, trackEnd, const Cell(rune: 0x5D /* ] */));

  final regStart =
      (origin * trackLen / screenHeight).floor().clamp(0, trackLen - 1);
  var regEnd = ((origin + regionRows) * trackLen / screenHeight)
      .ceil()
      .clamp(1, trackLen);
  if (regEnd <= regStart) regEnd = regStart + 1;

  for (var i = 0; i < trackLen; i++) {
    final inRegion = i >= regStart && i < regEnd;
    b.set(
      row,
      trackStart + i,
      inRegion
          ? const Cell(rune: 0x2588 /* full block */, fg: Color.brightCyan)
          : const Cell(rune: 0x00B7 /* middle dot */, fg: Color.brightBlack),
    );
  }
}

void _drawBorder(CellBuffer b, int rows, int cols, {String? title}) {
  const tl = 0x250C, tr = 0x2510, bl = 0x2514, br = 0x2518;
  const h = 0x2500, v = 0x2502;
  b.set(0, 0, const Cell(rune: tl));
  b.set(0, cols - 1, const Cell(rune: tr));
  b.set(rows - 1, 0, const Cell(rune: bl));
  b.set(rows - 1, cols - 1, const Cell(rune: br));
  for (var c = 1; c < cols - 1; c++) {
    b.set(0, c, const Cell(rune: h));
    b.set(rows - 1, c, const Cell(rune: h));
  }
  for (var r = 1; r < rows - 1; r++) {
    b.set(r, 0, const Cell(rune: v));
    b.set(r, cols - 1, const Cell(rune: v));
  }
  if (title != null) {
    b.writeAt(0, 2, title, style: TextStyle.bold);
  }
}
