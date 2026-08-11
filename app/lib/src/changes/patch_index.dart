/// A unified diff, **indexed rather than parsed**.
///
/// The screen this feeds needs the file list, the per-file counts and every
/// hunk's position before it paints anything, and needs a file's *text* only
/// when somebody expands that file. Measured on this repository, a realistic
/// agent branch is 470–520 KB of patch and the worst range tried was 3.6 MB —
/// all of it produced by git in well under 100 ms. Decoding that into Dart
/// strings is the expensive half, so this scans the bytes, records offsets, and
/// allocates a string for nothing it does not have to.
///
/// The scan looks at the first byte of each line. Content lines advance a
/// cursor and are never materialised; [textFor] slices them out later.
///
/// Pure Dart — `fw` links this.
library;

import 'dart:convert';
import 'dart:typed_data';

/// What happened to a file, as the patch header describes it.
///
/// Binary is not here: a binary file is still added, modified or deleted, and
/// [FileChange.isBinary] says so separately rather than costing a fifth state
/// that every `switch` would have to spell.
enum ChangeStatus { added, modified, deleted, renamed }

/// One `@@` hunk: where it sits, how heavy it is, and where its bytes are.
///
/// [oldStart]/[newStart] are what the ruler draws — position in the file — and
/// [added]/[removed] are its weight. Both come out of the scan; neither costs a
/// second pass.
class HunkSpan {
  const HunkSpan({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.added,
    required this.removed,
    required this.byteStart,
    required this.byteEnd,
    this.context,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;

  final int added;
  final int removed;

  /// Byte range of the whole hunk, `@@` line included.
  final int byteStart;
  final int byteEnd;

  /// What git wrote after the closing `@@` — usually the enclosing function.
  /// Null when it wrote nothing.
  final String? context;

  /// Lines the expanded view will draw for this hunk, known **before any of it
  /// is decoded**. This is what keeps a virtualised list's scroll extent from
  /// jumping when a file is expanded.
  ///
  /// Every line of the new side, plus the removed ones that are drawn beside
  /// them — context appears in both counts and is drawn once.
  int get displayLines => newCount + removed;
}

/// One file's entry in the patch.
class FileChange {
  const FileChange({
    required this.path,
    required this.status,
    required this.added,
    required this.removed,
    required this.hunks,
    required this.byteStart,
    required this.byteEnd,
    this.oldPath,
    this.isBinary = false,
  });

  /// Where the file is *now*. For a deletion, where it was.
  final String path;

  /// Where a rename came from. Null otherwise.
  final String? oldPath;

  final ChangeStatus status;

  final int added;
  final int removed;

  /// Binary files carry no lines and no hunks. They are still counted as files:
  /// deleting a 2 MB asset is a real change.
  final bool isBinary;

  final List<HunkSpan> hunks;

  /// Byte range of this file's whole block, from `diff --git` to the byte
  /// before the next one. Slicing it yields a patch that `git apply` accepts,
  /// which is what makes the round-trip test in the suite meaningful.
  final int byteStart;
  final int byteEnd;

  int get patchBytes => byteEnd - byteStart;
  int get lines => added + removed;
}

/// The whole patch: the bytes, and where everything is in them.
class PatchIndex {
  const PatchIndex({required this.bytes, required this.files});

  static final empty = PatchIndex(bytes: Uint8List(0), files: const []);

  final Uint8List bytes;
  final List<FileChange> files;

  int get added => files.fold(0, (sum, f) => sum + f.added);
  int get removed => files.fold(0, (sum, f) => sum + f.removed);

  /// This file's patch, decoded on demand.
  ///
  /// **Malformed UTF-8 is replaced, never thrown on.** A patch is whatever was
  /// in the user's files, and a lone invalid byte in one line must not cost the
  /// whole view — the alternative is a screen that works until somebody commits
  /// a latin-1 file.
  String textFor(FileChange file) => const Utf8Decoder(
    allowMalformed: true,
  ).convert(bytes, file.byteStart, file.byteEnd);

  /// One hunk's text, for a view that materialises a file a hunk at a time.
  String textForHunk(HunkSpan hunk) => const Utf8Decoder(
    allowMalformed: true,
  ).convert(bytes, hunk.byteStart, hunk.byteEnd);
}

const _lf = 0x0a;
const _cr = 0x0d;
const _plus = 0x2b;
const _minus = 0x2d;
const _space = 0x20;
const _backslash = 0x5c;

/// Indexes `git diff` output.
///
/// Tolerant by construction: a line it does not recognise advances the cursor.
/// This runs against whatever git the user has, and one unfamiliar header must
/// not cost the file list.
PatchIndex indexPatch(Uint8List bytes) {
  var files = <FileChange>[];
  var scanner = _Scanner(bytes);

  _FileBuilder? current;

  void finish(int end) {
    if (current case var file?) {
      files.add(file.build(end));
      current = null;
    }
  }

  while (scanner.next()) {
    // Two ends, and confusing them is the bug this file exists to not have.
    // [line] includes the terminator so byte ranges join up with no gaps;
    // [text] excludes it so a parsed path does not end in a newline.
    var start = scanner.lineStart;
    var line = scanner.lineEnd;
    var text = scanner.contentEnd;

    // Inside a hunk the header's counts say where it ends, so content is
    // classified before anything could be mistaken for a header — a removed
    // line reading `--- x` is real content, and only the remaining-line budget
    // knows it is not the start of the next file.
    if (current?.hunk case var hunk? when !hunk.done) {
      hunk.consume(bytes, start, text);
      if (hunk.done) current!.closeHunk(line);
      continue;
    }

    if (_startsWith(bytes, start, text, _diffGit)) {
      finish(start);
      current = _FileBuilder(start)..readDiffGitLine(bytes, start, text);
      continue;
    }

    if (current == null) continue;

    if (_startsWith(bytes, start, text, _atAt)) {
      current!.openHunk(bytes, start, text, line);
    } else if (_startsWith(bytes, start, text, _oldFile)) {
      current!.readOldPath(bytes, start + _oldFile.length, text);
    } else if (_startsWith(bytes, start, text, _newFile)) {
      current!.readNewPath(bytes, start + _newFile.length, text);
    } else if (_startsWith(bytes, start, text, _deletedFile)) {
      current!.status = ChangeStatus.deleted;
    } else if (_startsWith(bytes, start, text, _newFileMode)) {
      current!.status = ChangeStatus.added;
    } else if (_startsWith(bytes, start, text, _renameFrom)) {
      // No `a/` here — unlike `---`/`+++`, git writes these paths bare, and
      // stripping would eat a real directory called `a`.
      current!.oldPath = _decodePath(bytes, start + _renameFrom.length, text);
      current!.status = ChangeStatus.renamed;
    } else if (_startsWith(bytes, start, text, _renameTo)) {
      current!.newPath = _decodePath(bytes, start + _renameTo.length, text);
      current!.status = ChangeStatus.renamed;
    } else if (_startsWith(bytes, start, text, _binaryFiles) ||
        _startsWith(bytes, start, text, _gitBinaryPatch)) {
      current!.isBinary = true;
    }
  }

  finish(bytes.length);
  return PatchIndex(bytes: bytes, files: files);
}

/// Walks lines without allocating one.
class _Scanner {
  _Scanner(this.bytes);

  final Uint8List bytes;
  var _cursor = 0;

  var lineStart = 0;

  /// Exclusive, and **includes the newline** so byte ranges join up: a file's
  /// range ends where the next one begins, with nothing between them.
  var lineEnd = 0;

  /// Excludes the line terminator, CRLF included — what a header parses from.
  var contentEnd = 0;

  bool next() {
    if (_cursor >= bytes.length) return false;
    lineStart = _cursor;
    var i = _cursor;
    while (i < bytes.length && bytes[i] != _lf) {
      i++;
    }
    contentEnd = i;
    if (contentEnd > lineStart && bytes[contentEnd - 1] == _cr) contentEnd--;
    lineEnd = i < bytes.length ? i + 1 : i;
    _cursor = lineEnd;
    return true;
  }
}

class _FileBuilder {
  _FileBuilder(this.byteStart);

  final int byteStart;

  String? oldPath;
  String? newPath;

  /// Only when the `diff --git` line could be split unambiguously — see
  /// [readDiffGitLine]. The last resort, because it is the only source that can
  /// be wrong.
  String? guessedPath;

  var status = ChangeStatus.modified;
  var isBinary = false;
  var added = 0;
  var removed = 0;

  final hunks = <HunkSpan>[];
  _HunkBuilder? hunk;

  void readOldPath(Uint8List bytes, int start, int end) {
    var path = _decodePath(bytes, start, end);
    if (path == '/dev/null') {
      status = ChangeStatus.added;
    } else {
      oldPath ??= _stripPrefix(path);
    }
  }

  void readNewPath(Uint8List bytes, int start, int end) {
    var path = _decodePath(bytes, start, end);
    if (path == '/dev/null') {
      status = ChangeStatus.deleted;
    } else {
      newPath = _stripPrefix(path);
    }
  }

  /// `diff --git a/x b/x` is **ambiguous and cannot be split in general** — git
  /// does not quote a path containing a space, so `a/with space.txt b/with
  /// space.txt` has three plausible split points. Verified against git 2.x:
  /// only `"` and `\` (and non-ASCII without `core.quotePath=false`) force
  /// quoting; a space does not.
  ///
  /// So this is a **fallback**, and it only accepts the one case it can prove:
  /// both halves naming the same path. `--- `/`+++ ` carry a disambiguating
  /// trailing tab and are preferred; `rename from`/`rename to` are whole-line
  /// and are preferred over both. What is left for this is a binary file or a
  /// mode-only change that was not renamed — which is exactly where no other
  /// line names the file at all.
  void readDiffGitLine(Uint8List bytes, int start, int end) {
    var line = _decodePath(bytes, start + _diffGit.length, end);
    if (line.startsWith('"')) {
      // Both halves quoted: the first ends at the first unescaped quote.
      var close = _closingQuote(line);
      if (close < 0) return;
      guessedPath = _stripPrefix(_unquote(line.substring(0, close + 1)));
      return;
    }
    // `a/P b/P` for the same P: the halves are equal length, so the separator
    // sits exactly in the middle.
    if (line.length.isOdd) {
      var half = line.length ~/ 2;
      if (line[half] == ' ') {
        var left = line.substring(0, half);
        var right = line.substring(half + 1);
        if (_stripPrefix(left) == _stripPrefix(right)) {
          guessedPath = _stripPrefix(left);
        }
      }
    }
  }

  void openHunk(Uint8List bytes, int start, int textEnd, int lineEnd) {
    closeHunk(start);
    var header = _parseHunkHeader(bytes, start, textEnd);
    if (header == null) return;
    hunk = _HunkBuilder(header, start);
    // `@@ -1,0 +1,0 @@` and mode-only stubs are already finished.
    if (hunk!.done) closeHunk(lineEnd);
  }

  void closeHunk(int end) {
    if (hunk case var open?) {
      var span = open.build(end);
      hunks.add(span);
      added += span.added;
      removed += span.removed;
      hunk = null;
    }
  }

  FileChange build(int end) {
    closeHunk(end);
    var path = newPath ?? oldPath ?? guessedPath ?? '(unknown)';
    // A rename that also changed content reports both sides; one that did not
    // reports only `rename from`/`rename to`, and then `oldPath` is the source
    // rather than a same-path echo.
    var from = status == ChangeStatus.renamed ? oldPath : null;
    return FileChange(
      path: path,
      oldPath: from == path ? null : from,
      status: status,
      added: added,
      removed: removed,
      isBinary: isBinary,
      hunks: List.unmodifiable(hunks),
      byteStart: byteStart,
      byteEnd: end,
    );
  }
}

class _HunkBuilder {
  _HunkBuilder(this.header, this.byteStart);

  final _HunkHeader header;
  final int byteStart;

  late var _oldLeft = header.oldCount;
  late var _newLeft = header.newCount;

  var added = 0;
  var removed = 0;

  bool get done => _oldLeft <= 0 && _newLeft <= 0;

  void consume(Uint8List bytes, int start, int end) {
    // An empty line inside a hunk is a context line whose single space some
    // tool stripped. Treating it as an unknown header would end the hunk early
    // and swallow the rest of the file.
    var first = start < end ? bytes[start] : _space;
    switch (first) {
      case _plus:
        added++;
        _newLeft--;
      case _minus:
        removed++;
        _oldLeft--;
      case _backslash:
        // `\ No newline at end of file` belongs to the line before it and
        // counts as nothing.
        break;
      default:
        _oldLeft--;
        _newLeft--;
    }
  }

  HunkSpan build(int end) => HunkSpan(
    oldStart: header.oldStart,
    oldCount: header.oldCount,
    newStart: header.newStart,
    newCount: header.newCount,
    added: added,
    removed: removed,
    byteStart: byteStart,
    byteEnd: end,
    context: header.context,
  );
}

class _HunkHeader {
  const _HunkHeader({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    this.context,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String? context;
}

/// Parses `@@ -a,b +c,d @@ context`.
///
/// **An omitted count means 1**, not 0 — `@@ -1 +1 @@` is a one-line change and
/// reading it as zero would end the hunk before its content and hand the rest
/// of the file to the header parser.
_HunkHeader? _parseHunkHeader(Uint8List bytes, int start, int end) {
  var text = _decodeAscii(bytes, start, end);
  var close = text.indexOf(' @@');
  if (close < 0) return null;
  var ranges = text.substring(_atAt.length, close).trim().split(' ');
  if (ranges.length < 2) return null;

  var old = _parseRange(ranges[0], '-');
  var neu = _parseRange(ranges[1], '+');
  if (old == null || neu == null) return null;

  var context = text.substring(close + 3).trim();
  return _HunkHeader(
    oldStart: old.$1,
    oldCount: old.$2,
    newStart: neu.$1,
    newCount: neu.$2,
    context: context.isEmpty ? null : context,
  );
}

(int, int)? _parseRange(String token, String sign) {
  if (!token.startsWith(sign)) return null;
  var body = token.substring(1);
  var comma = body.indexOf(',');
  if (comma < 0) {
    var start = int.tryParse(body);
    return start == null ? null : (start, 1);
  }
  var start = int.tryParse(body.substring(0, comma));
  var count = int.tryParse(body.substring(comma + 1));
  if (start == null || count == null) return null;
  return (start, count);
}

/// A path from a header line: unquoted if git quoted it, and with the trailing
/// tab git appends when the path contains a space.
String _decodePath(Uint8List bytes, int start, int end) {
  var text = const Utf8Decoder(
    allowMalformed: true,
  ).convert(bytes, start, end < start ? start : end);
  // git writes `+++ b/with space.txt\t` — the tab is the unified-diff
  // convention for making a spaced path parseable, and it is not in the name.
  var tab = text.indexOf('\t');
  if (tab >= 0) text = text.substring(0, tab);
  return text.startsWith('"') ? _unquote(text) : text;
}

String _decodeAscii(Uint8List bytes, int start, int end) =>
    const Utf8Decoder(allowMalformed: true).convert(bytes, start, end);

String _stripPrefix(String path) {
  if (path.length > 2 && (path.startsWith('a/') || path.startsWith('b/'))) {
    return path.substring(2);
  }
  return path;
}

int _closingQuote(String text) {
  for (var i = 1; i < text.length; i++) {
    if (text[i] == r'\') {
      i++;
      continue;
    }
    if (text[i] == '"') return i;
  }
  return -1;
}

/// Undoes git's C-style quoting: `"a/caf\303\251.txt"` → `a/café.txt`.
///
/// Octal escapes are bytes of a UTF-8 sequence, so they are collected as bytes
/// and decoded together — decoding each one alone yields two mojibake
/// characters instead of one é.
String _unquote(String quoted) {
  var body = quoted.substring(
    1,
    quoted.length - (quoted.endsWith('"') ? 1 : 0),
  );
  var out = <int>[];
  for (var i = 0; i < body.length; i++) {
    if (body[i] != r'\') {
      out.addAll(utf8.encode(body[i]));
      continue;
    }
    i++;
    if (i >= body.length) break;
    switch (body[i]) {
      case 'n':
        out.add(0x0a);
      case 't':
        out.add(0x09);
      case 'r':
        out.add(0x0d);
      case 'a':
        out.add(0x07);
      case 'b':
        out.add(0x08);
      case 'f':
        out.add(0x0c);
      case 'v':
        out.add(0x0b);
      case r'\':
        out.add(0x5c);
      case '"':
        out.add(0x22);
      default:
        var digits = body.substring(i, (i + 3).clamp(0, body.length));
        var value = int.tryParse(digits, radix: 8);
        if (value == null) {
          out.addAll(utf8.encode(body[i]));
        } else {
          out.add(value);
          i += 2;
        }
    }
  }
  return const Utf8Decoder(allowMalformed: true).convert(out);
}

bool _startsWith(Uint8List bytes, int start, int end, List<int> prefix) {
  if (end - start < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[start + i] != prefix[i]) return false;
  }
  return true;
}

final _diffGit = ascii.encode('diff --git ');
final _atAt = ascii.encode('@@');
final _oldFile = ascii.encode('--- ');
final _newFile = ascii.encode('+++ ');
final _newFileMode = ascii.encode('new file mode');
final _deletedFile = ascii.encode('deleted file mode');
final _renameFrom = ascii.encode('rename from ');
final _renameTo = ascii.encode('rename to ');
final _binaryFiles = ascii.encode('Binary files ');
final _gitBinaryPatch = ascii.encode('GIT binary patch');
