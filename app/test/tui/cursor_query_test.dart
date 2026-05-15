import 'dart:async';
import 'dart:convert';

import 'package:flutterware_app/src/tui/cursor_query.dart';
import 'package:test/test.dart';

void main() {
  group('queryCursorPosition', () {
    test('parses a clean response and returns 0-indexed row', () async {
      final input = StreamController<List<int>>();
      final outputBuf = <int>[];

      final future = queryCursorPosition(
        bytes: input.stream,
        write: outputBuf.addAll,
        fallbackRow: -1,
      );

      // Simulate terminal response: CSI 5;12R (row 5, col 12, 1-indexed).
      input.add('\x1b[5;12R'.codeUnits);

      final result = await future;
      expect(result.row, 4); // 0-indexed
      expect(result.col, 11);
      expect(result.leftoverBytes, isEmpty);
      // The query helper should have written CSI 6n.
      expect(utf8.decode(outputBuf), '\x1b[6n');

      await input.close();
    });

    test('response split across chunks', () async {
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: -1,
      );

      input.add([0x1b, 0x5b]);
      input.add('5'.codeUnits);
      input.add(';12R'.codeUnits);

      final result = await future;
      expect(result.row, 4);
      expect(result.col, 11);
      expect(result.leftoverBytes, isEmpty);
      await input.close();
    });

    test('non-response bytes before the response are forwarded as leftover',
        () async {
      // The user typed 'A' before the response arrived.
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: -1,
      );

      input.add([0x41]); // 'A'
      input.add('\x1b[3;7R'.codeUnits);

      final result = await future;
      expect(result.row, 2);
      expect(result.col, 6);
      expect(result.leftoverBytes, [0x41]);
      await input.close();
    });

    test('non-response bytes after the response are forwarded as leftover',
        () async {
      // The user typed 'B' right after the response.
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: -1,
      );

      input.add('\x1b[3;7R'.codeUnits);
      input.add([0x42]); // 'B' — arrives in the same async tick

      final result = await future;
      expect(result.row, 2);
      // 'B' arrived in a separate chunk after the helper had completed; it is
      // NOT captured in leftoverBytes (the helper has already resolved).
      expect(result.leftoverBytes, isEmpty);
      await input.close();
    });

    test('interleaved escape-prefixed non-response bytes survive', () async {
      // An up-arrow key '\x1b[A' interleaves: ESC, [, A. The parser must
      // recognize that this isn't a position response (A isn't a digit after
      // ESC [), discard its partial-parse state, and forward those 3 bytes
      // to leftoverBytes. Then the real response comes through.
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: -1,
      );

      input.add(
          '\x1b[A'.codeUnits); // arrow up — must NOT be consumed as response
      input.add('\x1b[10;20R'.codeUnits); // real response

      final result = await future;
      expect(result.row, 9);
      expect(result.col, 19);
      expect(result.leftoverBytes, '\x1b[A'.codeUnits);
      await input.close();
    });

    test('timeout returns fallback row and empty leftover', () async {
      final input = StreamController<List<int>>();
      final result = await queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: 42,
        timeout: const Duration(milliseconds: 50),
      );
      expect(result.row, 42);
      expect(result.col, 0);
      expect(result.leftoverBytes, isEmpty);
      await input.close();
    });

    test('timeout forwards any bytes received before timeout as leftover',
        () async {
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: 42,
        timeout: const Duration(milliseconds: 50),
      );

      input.add([0x58, 0x59]); // 'X', 'Y' — random non-response bytes
      // No response ever comes.

      final result = await future;
      expect(result.row, 42);
      expect(result.leftoverBytes, [0x58, 0x59]);
      await input.close();
    });

    test('timeout with mid-sequence pending bytes forwards them as leftover',
        () async {
      // The terminal started sending what looked like a response but never
      // completed it. The bytes ESC [ 1 are "tentatively consumed" by the
      // parser; on timeout they must be forwarded as leftover, not dropped.
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: 7,
        timeout: const Duration(milliseconds: 50),
      );

      input.add([0x1b, 0x5b, 0x31]); // ESC [ 1 — partial response
      // No further bytes; timeout fires.

      final result = await future;
      expect(result.row, 7);
      expect(result.leftoverBytes, [0x1b, 0x5b, 0x31]);
      await input.close();
    });
  });
}
