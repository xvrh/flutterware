import 'dart:async';
import 'dart:io';

import 'ansi.dart';
import 'buffer.dart';
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

  // ignore: unused_field — wired up in Task 4 (inline-mode branching)
  final TerminalMode _mode;

  int _rows = 0;
  int _cols = 0;
  late CellBuffer _front;
  late CellBuffer _back;

  bool _wasEcho = false;
  bool _wasLine = false;
  bool _restored = false;

  final _resizeController = StreamController<void>.broadcast();
  final _keysController = StreamController<KeyEvent>.broadcast();
  StreamSubscription<KeyEvent>? _keysSub;
  final _subs = <StreamSubscription>[];

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
    _enter();
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

  void _enter() {
    _wasEcho = stdin.echoMode;
    _wasLine = stdin.lineMode;
    stdin.echoMode = false;
    stdin.lineMode = false;

    stdout.write(Ansi.enterAltScreen);
    stdout.write(Ansi.hideCursor);
    stdout.write(Ansi.clearScreen);
    stdout.write(Ansi.moveTo(0, 0));

    _rows = stdout.terminalLines;
    _cols = stdout.terminalColumns;
    _front = CellBuffer(_rows, _cols);
    _back = CellBuffer(_rows, _cols);

    // Pipe parsed key events into the public stream.
    _keysSub = parseKeyEvents(stdin).listen(
      _keysController.add,
      onError: _keysController.addError,
      onDone: _keysController.close,
    );

    // SIGWINCH — Unix only. Errors silently ignored on platforms without it.
    try {
      _subs.add(ProcessSignal.sigwinch.watch().listen((_) => _onResize()));
    } catch (_) {/* not supported on this platform */}
  }

  void _onResize() {
    final newRows = stdout.terminalLines;
    final newCols = stdout.terminalColumns;
    if (newRows == _rows && newCols == _cols) return;
    _rows = newRows;
    _cols = newCols;
    _front = CellBuffer(_rows, _cols);
    _back = CellBuffer(_rows, _cols);
    // Force a full repaint by clearing the screen; the caller will redraw
    // on the next resizes event and the diff will show every cell as changed.
    stdout.write(Ansi.clearScreen);
    stdout.write(Ansi.moveTo(0, 0));
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
    _back.clear();
    paint(_back);
    final diff = encodeDiff(_front, _back);
    if (diff.isNotEmpty) {
      stdout.write(diff);
    }
    _front.copyFrom(_back);
  }

  void _restore() {
    if (_restored) return;
    _restored = true;

    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _keysSub?.cancel();
    if (!_keysController.isClosed) _keysController.close();
    if (!_resizeController.isClosed) _resizeController.close();

    // Write restore sequences synchronously so they reach the terminal even
    // on the way out of the process.
    try {
      stdout.write(Ansi.resetStyle);
      stdout.write(Ansi.showCursor);
      stdout.write(Ansi.exitAltScreen);
    } catch (_) {/* stdout may already be closed */}

    try {
      stdin.echoMode = _wasEcho;
      stdin.lineMode = _wasLine;
    } catch (_) {}
  }
}
