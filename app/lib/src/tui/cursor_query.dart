import 'dart:async';

/// Result of a [queryCursorPosition] call.
///
/// [row] and [col] are 0-indexed.
/// [leftoverBytes] are any bytes received during the query that were NOT
/// part of the position response (typically keystrokes the user typed
/// while the query was in flight). Callers should forward these to their
/// regular input pipeline.
class CursorPositionResult {
  final int row;
  final int col;
  final List<int> leftoverBytes;
  const CursorPositionResult({
    required this.row,
    required this.col,
    required this.leftoverBytes,
  });
}

/// Query the terminal for the current cursor position.
///
/// Writes `CSI 6n` via [write], then consumes bytes from [bytes] until a
/// `CSI <row>;<col> R` response arrives. Returns 0-indexed coordinates.
///
/// If the terminal does not respond within [timeout], returns a result with
/// [CursorPositionResult.row] equal to [fallbackRow] and any bytes received
/// during the wait forwarded as `leftoverBytes`.
///
/// The query writes its own bytes and reads from the provided stream — it
/// does not touch `stdin` or `stdout` directly, which makes it unit-testable
/// without a real terminal.
Future<CursorPositionResult> queryCursorPosition({
  required Stream<List<int>> bytes,
  required void Function(List<int>) write,
  required int fallbackRow,
  Duration timeout = const Duration(milliseconds: 200),
}) async {
  final completer = Completer<CursorPositionResult>();
  final leftover = <int>[];

  // Parser state: looking for ESC [ <digits> ; <digits> R
  // _State values:
  //   0 = scanning for ESC
  //   1 = saw ESC, expect [
  //   2 = saw ESC[, expect first digit of row
  //   3 = in row digits (>=1 already consumed), expect more digits or ;
  //   4 = saw ;, expect first digit of col
  //   5 = in col digits, expect more digits or R
  var state = 0;
  var row = 0;
  var col = 0;
  // Bytes that we tentatively consumed as part of a possible response.
  // If parsing bails out, these are flushed back to [leftover].
  final pending = <int>[];

  void rollback(int trailingByte) {
    leftover.addAll(pending);
    leftover.add(trailingByte);
    pending.clear();
    state = 0;
    row = 0;
    col = 0;
  }

  late StreamSubscription<List<int>> sub;
  sub = bytes.listen(
    (chunk) {
      if (completer.isCompleted) {
        leftover.addAll(chunk);
        return;
      }
      for (final byte in chunk) {
        if (completer.isCompleted) {
          leftover.add(byte);
          continue;
        }
        switch (state) {
          case 0:
            if (byte == 0x1b /* ESC */) {
              pending.add(byte);
              state = 1;
            } else {
              leftover.add(byte);
            }
            break;
          case 1:
            if (byte == 0x5b /* [ */) {
              pending.add(byte);
              state = 2;
            } else {
              rollback(byte);
            }
            break;
          case 2:
            if (byte >= 0x30 && byte <= 0x39) {
              pending.add(byte);
              row = byte - 0x30;
              state = 3;
            } else {
              rollback(byte);
            }
            break;
          case 3:
            if (byte >= 0x30 && byte <= 0x39) {
              pending.add(byte);
              row = row * 10 + (byte - 0x30);
            } else if (byte == 0x3b /* ; */) {
              pending.add(byte);
              state = 4;
            } else {
              rollback(byte);
            }
            break;
          case 4:
            if (byte >= 0x30 && byte <= 0x39) {
              pending.add(byte);
              col = byte - 0x30;
              state = 5;
            } else {
              rollback(byte);
            }
            break;
          case 5:
            if (byte >= 0x30 && byte <= 0x39) {
              pending.add(byte);
              col = col * 10 + (byte - 0x30);
            } else if (byte == 0x52 /* R */) {
              // Response complete.
              completer.complete(CursorPositionResult(
                row: row - 1,
                col: col - 1,
                leftoverBytes: List.unmodifiable(leftover),
              ));
            } else {
              rollback(byte);
            }
            break;
        }
      }
    },
    onError: (Object error, StackTrace stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        // Stream closed before a response arrived. Treat as timeout-like.
        completer.complete(CursorPositionResult(
          row: fallbackRow,
          col: 0,
          leftoverBytes: List.unmodifiable(leftover),
        ));
      }
    },
  );

  write('\x1b[6n'.codeUnits);

  try {
    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => CursorPositionResult(
        row: fallbackRow,
        col: 0,
        leftoverBytes: List.unmodifiable(leftover),
      ),
    );
    return result;
  } finally {
    await sub.cancel();
  }
}
