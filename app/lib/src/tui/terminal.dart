import 'dart:async';
import 'dart:io';

import 'ansi.dart';
import 'buffer.dart';
import 'cell.dart';
import 'cursor_query.dart';
import 'input.dart';

/// Rendering mode for a [Terminal] session.
sealed class TerminalMode {
  const TerminalMode();
}

/// Take over the whole terminal via the alt-screen buffer. The default.
final class FullScreenMode extends TerminalMode {
  const FullScreenMode();
}

/// Render into a fixed-height region anchored at the cursor's position
/// when [Terminal.run] starts. Normal scrollback above the region is
/// preserved. Suitable for status panels and dashboards that coexist with
/// regular CLI output.
final class InlineMode extends TerminalMode {
  /// Height of the region in rows. Must be > 0.
  final int rows;
  const InlineMode({required this.rows}) : assert(rows > 0);
}

/// Compute the inline region's new origin row after [linesPrinted] lines are
/// printed into the scrollback above it.
///
/// The region drifts downward as lines are inserted above it, until it is
/// pinned against the bottom of the terminal (`terminalLines - regionRows`),
/// after which further lines scroll the screen and the anchor stays put.
/// Clamped to a minimum of 0 so a terminal shorter than the region still
/// yields a valid row.
int anchorRowAfterPrintAbove({
  required int originRow,
  required int regionRows,
  required int linesPrinted,
  required int terminalLines,
}) {
  final maxOrigin = terminalLines - regionRows;
  var next = originRow + linesPrinted;
  if (next > maxOrigin) next = maxOrigin;
  if (next < 0) next = 0;
  return next;
}

/// Owns the terminal lifecycle: alt-screen entry/exit, raw-mode stdin,
/// signal handling, double-buffered painting, and crash-safe restore.
///
/// Usage:
/// ```dart
/// await Terminal.run((terminal) async {
///   terminal.draw((buffer) { ... });
///   await for (final event in terminal.keys) { ... }
/// });
/// ```
class Terminal {
  /// Run [body] inside an active terminal session. The terminal is restored
  /// to its previous state on normal completion, on uncaught error, and on
  /// SIGINT/SIGTERM/SIGHUP.
  static Future<void> run(
    FutureOr<void> Function(Terminal terminal) body, {
    TerminalMode mode = const FullScreenMode(),
  }) async {
    final terminal = Terminal._(mode);
    await terminal._run(body);
  }

  Terminal._(this._mode);

  final TerminalMode _mode;

  int _rows = 0;
  int _cols = 0;
  late CellBuffer _front;
  late CellBuffer _back;

  /// The most recent paint callback passed to [draw]. Replayed by
  /// [printAbove] to redraw the region after it has been re-anchored.
  void Function(CellBuffer buffer)? _lastPaint;

  bool _wasEcho = false;
  bool _wasLine = false;
  bool _restored = false;

  final _resizeController = StreamController<void>.broadcast();
  final _keysController = StreamController<KeyEvent>.broadcast();
  StreamSubscription<KeyEvent>? _keysSub;
  final _subs = <StreamSubscription>[];

  final _stdinController = StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _stdinSub;
  int _originRow = 0;
  int _originCol = 0;
  bool _anchored = false;

  int get rows => _rows;
  int get cols => _cols;

  /// Emits when the terminal is resized. The caller is responsible for
  /// calling [draw] in response — the engine clears the screen on resize
  /// but does not repaint until asked.
  Stream<void> get resizes => _resizeController.stream;

  /// Stream of parsed key events. Broadcast, so multiple listeners are OK.
  Stream<KeyEvent> get keys => _keysController.stream;

  Future<void> _run(FutureOr<void> Function(Terminal) body) async {
    _installSignalHandlers();
    await _enter();
    try {
      await runZonedGuarded(() async {
        await body(this);
      }, (error, stack) {
        _restore();
        stderr.writeln('Unhandled error in Terminal.run: $error');
        stderr.writeln(stack);
        exitCode = 1;
      });
    } finally {
      _restore();
    }
  }

  Future<void> _enter() async {
    _wasEcho = stdin.echoMode;
    _wasLine = stdin.lineMode;
    stdin.echoMode = false;
    stdin.lineMode = false;

    // Pipe stdin into our internal controller. Both the cursor-position query
    // (briefly, during inline-mode entry) and the key parser (for the rest of
    // the session) consume from _stdinController.stream.
    _stdinSub = stdin.listen(
      _stdinController.add,
      onError: _stdinController.addError,
      onDone: _stdinController.close,
    );

    var pendingLeftover = const <int>[];
    final mode = _mode;
    if (mode is InlineMode) {
      stdout.write(Ansi.hideCursor);
      stdout.write('\n' * mode.rows);
      stdout.write('\x1b[${mode.rows}F'); // CPL: cursor previous line × rows

      final result = await queryCursorPosition(
        bytes: _stdinController.stream,
        write: stdout.add,
        fallbackRow: stdout.terminalLines - mode.rows,
      );
      _originRow = result.row;
      _originCol = 0;
      _anchored = true;
      pendingLeftover = result.leftoverBytes;

      _rows = mode.rows;
      _cols = stdout.terminalColumns;
    } else {
      stdout.write(Ansi.enterAltScreen);
      stdout.write(Ansi.hideCursor);
      stdout.write(Ansi.clearScreen);
      stdout.write(Ansi.moveTo(0, 0));
      _originRow = 0;
      _originCol = 0;
      _anchored = true;
      _rows = stdout.terminalLines;
      _cols = stdout.terminalColumns;
    }

    _front = CellBuffer(_rows, _cols);
    _back = CellBuffer(_rows, _cols);

    // Hook up the key parser to the (now free) _stdinController.stream.
    _keysSub = parseKeyEvents(_stdinController.stream).listen(
      _keysController.add,
      onError: _keysController.addError,
      onDone: _keysController.close,
    );
    // Replay leftover bytes from the cursor-position query now that the parser
    // is subscribed and ready to receive them.
    if (pendingLeftover.isNotEmpty) {
      _stdinController.add(pendingLeftover);
    }

    // SIGWINCH — Unix only.
    try {
      _subs.add(ProcessSignal.sigwinch.watch().listen((_) => _onResize()));
    } catch (_) {/* not supported on this platform */}
  }

  void _onResize() {
    final newCols = stdout.terminalColumns;
    final mode = _mode;
    if (mode is InlineMode) {
      if (newCols == _cols) return; // height is fixed; only columns can change
      _cols = newCols;
      _front = CellBuffer(_rows, _cols);
      _back = CellBuffer(_rows, _cols);
      // Do NOT clearScreen — that would wipe scrollback content above the
      // inline region. Callers should repaint in response to the resizes
      // event; the new (empty) _front means every cell will appear changed
      // and be repainted.
    } else {
      final newRows = stdout.terminalLines;
      if (newRows == _rows && newCols == _cols) return;
      _rows = newRows;
      _cols = newCols;
      _front = CellBuffer(_rows, _cols);
      _back = CellBuffer(_rows, _cols);
      stdout.write(Ansi.clearScreen);
      stdout.write(Ansi.moveTo(0, 0));
    }
    _resizeController.add(null);
  }

  void _installSignalHandlers() {
    void onTermSignal(int code) {
      _restore();
      exit(code);
    }

    try {
      _subs.add(ProcessSignal.sigint.watch().listen((_) => onTermSignal(130)));
    } catch (_) {}
    try {
      _subs.add(ProcessSignal.sigterm.watch().listen((_) => onTermSignal(143)));
    } catch (_) {}
    try {
      _subs.add(ProcessSignal.sighup.watch().listen((_) => onTermSignal(129)));
    } catch (_) {}
  }

  /// Compute and emit the diff between the current back buffer and the
  /// caller's freshly-painted back buffer. The user's [paint] function
  /// receives a cleared back buffer.
  void draw(void Function(CellBuffer buffer) paint) {
    _lastPaint = paint;
    _back.clear();
    paint(_back);
    final diff =
        encodeDiff(_front, _back, originRow: _originRow, originCol: _originCol);
    if (diff.isNotEmpty) {
      stdout.write(diff);
    }
    _front.copyFrom(_back);
  }

  /// Insert [height] rows of content into the terminal scrollback immediately
  /// above the inline region, then redraw the region at its new anchor.
  ///
  /// [paint] receives a fresh [height]×cols [CellBuffer] addressed from
  /// (0, 0). Content wider than the terminal is clipped; lines are not
  /// wrapped. A non-positive [height] is a no-op.
  ///
  /// Only valid in inline mode. Throws [StateError] in full-screen mode,
  /// where the alt-screen buffer has no scrollback.
  void printAbove(int height, void Function(CellBuffer buffer) paint) {
    if (_mode is! InlineMode) {
      throw StateError('printAbove is only available in inline mode');
    }
    if (height <= 0) return;

    final lines = CellBuffer(height, _cols);
    paint(lines);

    final out = StringBuffer();
    // Write the new lines starting at the region's current top row. Each
    // trailing newline either drifts the region down or, once the region is
    // pinned at the bottom, scrolls a line into the terminal's scrollback.
    out.write(Ansi.moveTo(_originRow, 0));
    for (var r = 0; r < height; r++) {
      out.write(encodeRow(lines, rowIndex: r));
      out.write(Ansi.resetStyle); // so the erase below uses the default bg
      out.write('\x1b[K'); // erase to end of line
      out.write('\n');
    }

    _originRow = anchorRowAfterPrintAbove(
      originRow: _originRow,
      regionRows: _rows,
      linesPrinted: height,
      terminalLines: stdout.terminalLines,
    );

    // Wipe the now-stale region area, then redraw the region at the new
    // anchor by replaying the last paint callback against a blank front.
    out.write(Ansi.moveTo(_originRow, 0));
    out.write('\x1b[J'); // erase from cursor to end of screen

    _front = CellBuffer(_rows, _cols);
    _back.clear();
    (_lastPaint ?? (_) {})(_back);
    out.write(encodeDiff(_front, _back,
        originRow: _originRow, originCol: _originCol));
    _front.copyFrom(_back);

    stdout.write(out.toString());
  }

  /// Convenience over [printAbove] for plain text. [text] is split on '\n';
  /// each line becomes one scrollback row painted with the given style.
  ///
  /// Only valid in inline mode. Throws [StateError] in full-screen mode.
  void printTextAbove(
    String text, {
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
  }) {
    final textLines = text.split('\n');
    printAbove(textLines.length, (buffer) {
      for (var i = 0; i < textLines.length; i++) {
        buffer.writeAt(i, 0, textLines[i], fg: fg, bg: bg, style: style);
      }
    });
  }

  void _restore() {
    if (_restored) return;
    _restored = true;

    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _keysSub?.cancel();
    _stdinSub?.cancel();
    if (!_keysController.isClosed) _keysController.close();
    if (!_resizeController.isClosed) _resizeController.close();
    if (!_stdinController.isClosed) _stdinController.close();

    // Write restore sequences synchronously so they reach the terminal even
    // on the way out of the process.
    try {
      stdout.write(Ansi.resetStyle);
      if (_mode is InlineMode) {
        if (_anchored) {
          stdout.write(Ansi.moveTo(_originRow, 0));
          stdout.write('\x1b[J'); // clear to end of screen
        }
        stdout.write(Ansi.showCursor);
        stdout.write('\n'); // next prompt on a fresh line
      } else {
        stdout.write(Ansi.showCursor);
        stdout.write(Ansi.exitAltScreen);
      }
    } catch (_) {/* stdout may already be closed */}

    try {
      stdin.echoMode = _wasEcho;
      stdin.lineMode = _wasLine;
    } catch (_) {}
  }
}
