/// Turning a hunk's byte slice into drawable lines — **on demand, and cached
/// per hunk**.
///
/// The whole architecture upstream exists so this is the only place a patch
/// becomes Dart strings, and so it happens for the hunks on screen rather than
/// for the megabyte behind them.
///
/// Pure Dart, so the parsing is testable without pumping a widget.
library;

import 'patch_index.dart';

enum DiffLineKind { context, added, removed, meta }

/// One line of a hunk, with the numbers that belong in the gutter.
class DiffLine {
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldNumber,
    this.newNumber,
  });

  final DiffLineKind kind;

  /// Without the leading `+`, `-` or space — the marker is the [kind], and
  /// keeping it in the text would put it under the syntax highlighter and
  /// inside anything the user copies.
  final String text;

  /// Null on the side the line does not exist.
  final int? oldNumber;
  final int? newNumber;
}

/// Splits one hunk's text into lines, numbering both sides.
///
/// The `@@` header is dropped: the list draws it as its own row, from the
/// [HunkSpan] rather than from the text.
///
/// `\ No newline at end of file` is [DiffLineKind.meta] — it belongs to the
/// line before it, consumes no line number, and would otherwise be drawn as a
/// context line the file does not contain.
List<DiffLine> parseHunkLines(String hunkText, HunkSpan hunk) {
  var lines = <DiffLine>[];
  var oldNumber = hunk.oldStart;
  var newNumber = hunk.newStart;

  var raw = hunkText.split('\n');
  for (var i = 0; i < raw.length; i++) {
    var line = raw[i];
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    // The header row is drawn from the span; and a trailing empty string is the
    // artefact of splitting on a final newline, not a line of the file.
    if (i == 0 && line.startsWith('@@')) continue;
    if (i == raw.length - 1 && line.isEmpty) continue;

    if (line.startsWith(r'\')) {
      lines.add(DiffLine(kind: DiffLineKind.meta, text: line));
      continue;
    }
    if (line.startsWith('+')) {
      lines.add(
        DiffLine(
          kind: DiffLineKind.added,
          text: line.substring(1),
          newNumber: newNumber++,
        ),
      );
      continue;
    }
    if (line.startsWith('-')) {
      lines.add(
        DiffLine(
          kind: DiffLineKind.removed,
          text: line.substring(1),
          oldNumber: oldNumber++,
        ),
      );
      continue;
    }
    // Context. An empty line here is a context line whose single space some
    // tool stripped, so `substring(1)` has to be guarded.
    lines.add(
      DiffLine(
        kind: DiffLineKind.context,
        text: line.isEmpty ? '' : line.substring(1),
        oldNumber: oldNumber++,
        newNumber: newNumber++,
      ),
    );
  }

  return lines;
}

/// Decodes hunks once and remembers them, keyed by their byte range.
///
/// Keyed by the range rather than by identity so a re-probe that produced an
/// equal patch does not throw the cache away — and dropped wholesale when the
/// patch actually moves, which the screen does by building a new cache.
class HunkLineCache {
  HunkLineCache(this._patch);

  final PatchIndex _patch;
  final _lines = <({int start, int end}), List<DiffLine>>{};

  List<DiffLine> linesFor(HunkSpan hunk) {
    var key = (start: hunk.byteStart, end: hunk.byteEnd);
    return _lines[key] ??= parseHunkLines(_patch.textForHunk(hunk), hunk);
  }

  /// How many hunks have been decoded. The assertion behind "lazy" — a test can
  /// scroll and check that the rest of the patch was never touched.
  int get decodedHunks => _lines.length;
}
