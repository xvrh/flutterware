import 'dart:async';

/// A block of rows pinned to the bottom of the terminal, with ordinary
/// scrollback growing above it.
///
/// Deliberately not the alternate screen and not a scroll region (`DECSTBM`).
/// Both were considered. Every line printed through [printAbove] should be a
/// real line in the user's terminal history — greppable, scrollable, still
/// there tomorrow — and a crash should leave a readable transcript rather than
/// half a restored screen. So the region is erased, the line is written, and
/// the region is painted again.
///
/// The whole mechanism is three sequences: `ESC[nF` returns to the first row of
/// the region, `ESC[2K` clears a row before rewriting it, and `ESC[0J` removes
/// the tail when the region gets shorter than it was.
///
/// Off a terminal this class is not used at all — see [Step] for the shape a
/// log gets. That is not a degradation path here because there is nothing
/// sensible to degrade to: a pinned region has no meaning in a file.
class LiveRegion {
  LiveRegion({required this.out, required this.rows});

  final StringSink out;

  /// What to paint, recomputed on every repaint.
  ///
  /// Returning a different number of rows than last time is fine; the region
  /// grows and shrinks with it.
  final List<String> Function() rows;

  Timer? _ticker;

  /// How many rows are on screen right now, which is how far up to go.
  var _painted = 0;

  /// Paints the region and keeps it current.
  ///
  /// [every] is the repaint interval, not a frame rate: nothing here animates
  /// faster than a spinner, and a terminal redrawn five times a second is
  /// already faster than it can be read.
  void start({Duration every = const Duration(milliseconds: 200)}) {
    if (_ticker != null) return;
    _paint();
    _ticker = Timer.periodic(every, (_) => _paint());
  }

  /// Writes [lines] into the scrollback above the region.
  ///
  /// The region is erased first so the lines land where the region was, and
  /// repainted after so it ends up below them again. Doing it the other way
  /// round — printing then erasing — puts the region's stale rows into the
  /// scrollback permanently.
  void printAbove(Iterable<String> lines) {
    var erased = _erase();
    for (var line in lines) {
      out.writeln(line);
    }
    if (erased) _paint();
  }

  /// Stops painting, removes the region, and writes [closing] where it was.
  ///
  /// Whatever [closing] holds is ordinary output: it stays on screen, which is
  /// what makes it the right place for the one line that outlives the run.
  void stop({Iterable<String> closing = const []}) {
    _ticker?.cancel();
    _ticker = null;
    _erase();
    for (var line in closing) {
      out.writeln(line);
    }
  }

  /// Stops painting and **keeps** the last frame, as ordinary output.
  ///
  /// The other ending. A region that was showing progress has nothing worth
  /// preserving, but one that was showing a result does — which stage failed,
  /// what each one cost — and erasing it to print the same thing again is how
  /// a transcript ends up missing the frame that mattered.
  void settle({Iterable<String> trailing = const []}) {
    _ticker?.cancel();
    _ticker = null;
    _paint();
    _painted = 0;
    for (var line in trailing) {
      out.writeln(line);
    }
  }

  bool _erase() {
    if (_painted == 0) return false;
    out.write('\x1b[${_painted}F\x1b[0J');
    _painted = 0;
    return true;
  }

  void _paint() {
    var lines = rows();
    var buffer = StringBuffer();
    if (_painted > 0) buffer.write('\x1b[${_painted}F');
    for (var line in lines) {
      buffer.write('\x1b[2K$line\n');
    }
    // The region just got shorter, and the rows below the new last one are
    // still showing the previous frame.
    if (lines.length < _painted) buffer.write('\x1b[0J');
    out.write(buffer);
    _painted = lines.length;
  }
}

/// Terminal decoration, in one place so that a call site cannot invent a
/// twelfth shade of grey.
///
/// Named for the role rather than the colour — `dim` and `ok` survive a
/// decision to render them differently, `brightBlack` does not. All of them are
/// the terminal's own palette rather than 24-bit values, so they land inside
/// whatever theme the user chose instead of on top of it.
abstract final class Ansi {
  static const reset = '\x1b[0m';
  static const bold = '\x1b[1m';
  static const dim = '\x1b[2m';
  static const ok = '\x1b[32m';
  static const bad = '\x1b[31m';
  static const busy = '\x1b[36m';

  static String style(String text, String code) => '$code$text$reset';

  /// The braille spinner, indexed by elapsed time rather than by a frame
  /// counter — so two spinners painted in the same frame agree, and one that
  /// starts late does not begin at the top of the cycle.
  static String spinner(Duration elapsed) =>
      _frames[(elapsed.inMilliseconds ~/ 100) % _frames.length];

  static const _frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
}
