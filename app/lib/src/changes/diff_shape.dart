/// What a file's change *is*, read off the patch bytes.
///
/// The two answers here are the ones no glob can express, and they are the bulk
/// of what "noise" should catch on a real branch: a formatter ran, or an import
/// list got reordered. A pattern list cannot name those, because they are not a
/// property of the path.
///
/// **Bytes in, verdict out — no strings.** This walks the same [PatchIndex]
/// slices the view would decode, comparing bytes directly, so classifying every
/// file on a branch costs a scan rather than a megabyte of Dart strings. That is
/// the same bargain the index itself is built on.
///
/// Pure Dart.
library;

import 'dart:typed_data';

import 'change_set.dart';
import 'patch_index.dart';

/// A property of the change that demotes a file without a rule naming it.
enum DiffShape {
  /// Nothing derivable — the normal case, and the only one that is not a
  /// claim.
  none,

  /// Every changed line is the same code with different whitespace: a
  /// reformat, a reindent, a blank line added or removed.
  whitespaceOnly,

  /// Every changed line is an `import` or `part` directive.
  ///
  /// **`export` is deliberately not one of these.** An import is internal
  /// bookkeeping; an export is the package's public surface, and a barrel file
  /// gaining a line is an API change that belongs in the main list. Found by
  /// running this over a real branch, where `lib/plugins.dart` gaining one
  /// `export` was demoted — exactly the file a reviewer would want.
  importsOnly,
}

/// Classifies [file] within [patch].
///
/// **Returns [DiffShape.none] rather than guessing** for anything it cannot
/// read exactly: a binary file, a file with no hunks, or one past the size the
/// viewer expands. Demoting a file we did not actually look at is how a ranking
/// loses the trust it exists to have.
DiffShape shapeOf(PatchIndex patch, FileChange file) {
  if (file.isBinary || file.hunks.isEmpty) return DiffShape.none;
  if (file.patchBytes > ChangesLimits.filePatchBytes) return DiffShape.none;
  // Nothing was removed and nothing added — a mode or rename with no body.
  if (file.added == 0 && file.removed == 0) return DiffShape.none;

  var bytes = patch.bytes;
  var addedSqueezed = BytesBuilder(copy: false);
  var removedSqueezed = BytesBuilder(copy: false);
  var directivesOnly = _isDart(file.path);

  /// A blank line counts as *compatible* with a directive block but is not one.
  /// Without this, deleting two blank lines from a `.dart` file would report
  /// "only imports changed" — a claim about a change that contains no imports
  /// at all.
  var sawDirective = false;

  for (var hunk in file.hunks) {
    var cursor = hunk.byteStart;
    var first = true;
    while (cursor < hunk.byteEnd) {
      var end = _lineEnd(bytes, cursor, hunk.byteEnd);
      var contentEnd = _stripTerminator(bytes, cursor, end);
      // The `@@` line itself is the hunk's header, not one of its lines.
      if (first) {
        first = false;
        cursor = end;
        continue;
      }

      var marker = cursor < contentEnd ? bytes[cursor] : _lf;
      if (marker == _plus || marker == _minus) {
        var target = marker == _plus ? addedSqueezed : removedSqueezed;
        _writeWithoutWhitespace(bytes, cursor + 1, contentEnd, target);
        if (directivesOnly) {
          switch (_classifyLine(bytes, cursor + 1, contentEnd)) {
            case _Line.directive:
              sawDirective = true;
            case _Line.blank:
              break;
            case _Line.other:
              directivesOnly = false;
          }
        }
      }
      cursor = end;
    }
  }

  if (directivesOnly && sawDirective) return DiffShape.importsOnly;

  // Equal squeezed sides means the same code arrived differently spaced. Both
  // empty is the same statement about blank lines, and is still true.
  var added = addedSqueezed.takeBytes();
  var removed = removedSqueezed.takeBytes();
  return _sameBytes(added, removed) ? DiffShape.whitespaceOnly : DiffShape.none;
}

bool _isDart(String path) => path.endsWith('.dart');

enum _Line { directive, blank, other }

/// What one changed line is, for the imports-only question.
///
/// Deliberately strict: a continuation line (`    show Foo, Bar;` under a
/// wrapped `import`) reads as [_Line.other] and the file is shown normally.
/// **Failing towards showing** is the only acceptable direction for a rule that
/// hides things.
_Line _classifyLine(Uint8List bytes, int start, int end) {
  var cursor = start;
  while (cursor < end && _isSpace(bytes[cursor])) {
    cursor++;
  }
  if (cursor >= end) return _Line.blank;
  for (var keyword in _directives) {
    if (_startsWith(bytes, cursor, end, keyword)) return _Line.directive;
  }
  return _Line.other;
}

/// See [DiffShape.importsOnly] for why `export ` is not in this list.
const _directives = [
  [0x69, 0x6d, 0x70, 0x6f, 0x72, 0x74, 0x20], // 'import '
  [0x70, 0x61, 0x72, 0x74, 0x20], // 'part '
];

bool _startsWith(Uint8List bytes, int start, int end, List<int> needle) {
  if (end - start < needle.length) return false;
  for (var i = 0; i < needle.length; i++) {
    if (bytes[start + i] != needle[i]) return false;
  }
  return true;
}

void _writeWithoutWhitespace(
  Uint8List bytes,
  int start,
  int end,
  BytesBuilder into,
) {
  for (var i = start; i < end; i++) {
    var byte = bytes[i];
    if (!_isSpace(byte)) into.addByte(byte);
  }
}

bool _isSpace(int byte) =>
    byte == _space || byte == _tab || byte == _cr || byte == _lf;

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _lineEnd(Uint8List bytes, int start, int limit) {
  for (var i = start; i < limit; i++) {
    if (bytes[i] == _lf) return i + 1;
  }
  return limit;
}

int _stripTerminator(Uint8List bytes, int start, int end) {
  var last = end;
  if (last > start && bytes[last - 1] == _lf) last--;
  if (last > start && bytes[last - 1] == _cr) last--;
  return last;
}

const _lf = 0x0a;
const _cr = 0x0d;
const _tab = 0x09;
const _space = 0x20;
const _plus = 0x2b;
const _minus = 0x2d;
