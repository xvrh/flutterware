/// A hunk's lines, tokenised — **two sides, and a chunk at a time**.
///
/// This is the thing about highlighting a diff that a code block does not have
/// to deal with, and the reason this file exists rather than a call to
/// `tokenizeLines` from the row widget.
///
/// **A hunk is two files interleaved.** Its `-` and `+` lines are alternative
/// versions of the same region, so feeding them to one tokeniser puts it in a
/// state neither version of the file is ever in — a removed line that opens a
/// quote the added line does not, and everything after it comes back as string.
/// So the hunk is reconstructed as its two sides:
///
/// - **old** = context + removed, in order
/// - **new** = context + added, in order
///
/// Each is a real fragment of a real file. Every line then takes its tokens
/// from its own side, and a context line — which is in both — takes the new
/// one.
///
/// **Each side is parsed forward in chunks, on demand.** Measured 2026-08-12:
/// ~0.28 ms per 1000 characters, so a whole added file — one hunk of a thousand
/// lines — is most of a frame if it is parsed in one go. A chunk is
/// [highlightChunkLines], and the tokeniser's own state is threaded from one to
/// the next, so the answer is *identical* to parsing the side whole. Chunking
/// is therefore a scheduling decision and nothing else: no cap, no file that
/// comes back grey, and no line whose colour depends on how you arrived at it.
///
/// **Fixed boundaries, never the viewport.** Chunking by what is on screen
/// would make a line's colour depend on where the scroll happened to start —
/// the same line grey inside a comment from one scroll position and code from
/// another. Boundaries are line indices, so a line's colour is a property of
/// the file.
///
/// **A hunk is still a fragment**, and that is the one real limit: a hunk
/// beginning inside a block comment starts the tokeniser in the wrong state and
/// there is nothing in the patch to fix it with.
///
/// Pure Dart apart from the token type, so the pairing is testable without
/// pumping a widget.
library;

import '../ui/syntax.dart';
import 'diff_lines.dart';
import 'patch_index.dart';

/// How many lines are tokenised at once.
///
/// **Measured 2026-08-12** on the vendored tokeniser, against
/// `database_panel_view.dart`: 0.29 ms for 20 lines, 1.60 ms for 200, 4.80 ms
/// for 600, 9.25 ms for 1110 — near enough linear at ~0.28 ms per 1000
/// characters. 200 keeps one chunk at about a tenth of a frame, which is small
/// enough that the row that triggers it is not the row that stutters.
///
/// Smaller would be finer-grained and would pay the per-call overhead more
/// often; larger starts to be felt on the first row of a big hunk. Nothing
/// about correctness turns on it — see the library comment.
const highlightChunkLines = 200;

/// One side of a hunk, parsed forward as it is read.
class _Side {
  _Side(this.lines, this.language);

  final List<String> lines;
  final String language;

  /// Tokens for `lines[0 .. _tokens.length)`. Grows a chunk at a time.
  final _tokens = <List<Token>>[];

  /// Where the last chunk left the tokeniser, threaded into the next one.
  SyntaxState? _state;

  List<Token>? at(int index) {
    if (index < 0 || index >= lines.length) return null;
    while (_tokens.length <= index) {
      _parseNext();
    }
    return _tokens[index];
  }

  void _parseNext() {
    var start = _tokens.length;
    var end = start + highlightChunkLines;
    if (end > lines.length) end = lines.length;
    var chunk = tokenizeChunk(
      lines.sublist(start, end).join('\n'),
      language: language,
      from: _state,
    );
    _state = chunk.state;
    _tokens.addAll(chunk.lines);
    // A grammar that returned fewer lines than it was given would loop here for
    // ever. It does not — `tokenizeChunk` pads — but a silent infinite loop in
    // a build method is not a thing to leave to a comment somewhere else.
    if (_tokens.length <= start) {
      for (var i = start; i < end; i++) {
        _tokens.add([Token(lines[i])]);
      }
    }
  }
}

/// One hunk's tokens, by the index of the line within the hunk.
class HunkTokens {
  HunkTokens._(this._placed, this._new, this._old);

  /// Which side each line is on, and where in it. Null for a line that is not
  /// code — the `\ No newline at end of file` marker.
  final List<({bool old, int index})?> _placed;
  final _Side? _new;
  final _Side? _old;

  static final none = HunkTokens._(const [], null, null);

  /// **Parses on demand**, so a row that is never built costs nothing and the
  /// row that is built pays for at most one chunk.
  List<Token>? at(int index) {
    if (index < 0 || index >= _placed.length) return null;
    var place = _placed[index];
    if (place == null) return null;
    return (place.old ? _old : _new)?.at(place.index);
  }
}

/// Pairs [lines] to their two sides, ready to be tokenised as [language].
///
/// **The old side is only built when there is something on it**, which is most
/// of the saving in practice: a hunk of pure additions — what an agent writing
/// new code produces — has no removed lines, so context and added both come
/// from the new side and the second side never exists.
HunkTokens tokenizeHunk(List<DiffLine> lines, {required String? language}) {
  if (language == null) return HunkTokens.none;

  var newSide = <String>[];
  var oldSide = <String>[];
  var placed = List<({bool old, int index})?>.filled(lines.length, null);
  var hasRemoved = false;

  for (var (index, line) in lines.indexed) {
    switch (line.kind) {
      case DiffLineKind.added:
        placed[index] = (old: false, index: newSide.length);
        newSide.add(line.text);
      case DiffLineKind.removed:
        hasRemoved = true;
        placed[index] = (old: true, index: oldSide.length);
        oldSide.add(line.text);
      case DiffLineKind.context:
        // In both sides, so both stay in step — and read off the new one,
        // which is the version of the file that still exists.
        placed[index] = (old: false, index: newSide.length);
        newSide.add(line.text);
        oldSide.add(line.text);
      case DiffLineKind.meta:
        // `\ No newline at end of file` is not code. It keeps its null and is
        // drawn in the meta style it already had.
        break;
    }
  }

  return HunkTokens._(
    placed,
    _Side(newSide, language),
    hasRemoved ? _Side(oldSide, language) : null,
  );
}

/// Tokenises hunks once and remembers them — the twin of [HunkLineCache], with
/// the same lifetime and the same key.
///
/// **Beside the line cache rather than inside it**, because they are wanted at
/// different moments: the lines are what the list measures itself with and are
/// needed for every hunk it builds, while the tokens are only wanted once a row
/// is actually painted, and are dropped wholesale for a file whose language
/// nothing here reads.
class HunkTokenCache {
  HunkTokenCache(this._lines, {required this.language});

  final HunkLineCache _lines;

  /// Null for a file we do not colour, which makes every lookup a cheap
  /// constant rather than a map miss per row.
  final String? language;

  final _tokens = <({int start, int end}), HunkTokens>{};

  HunkTokens forHunk(HunkSpan hunk) {
    if (language == null) return HunkTokens.none;
    var key = (start: hunk.byteStart, end: hunk.byteEnd);
    return _tokens[key] ??= tokenizeHunk(
      _lines.linesFor(hunk),
      language: language,
    );
  }

  /// How many hunks have been paired — the assertion behind "lazy". Note that
  /// pairing is not parsing: a hunk counted here has been split into its two
  /// sides and has tokenised only the chunks something asked for.
  int get tokenizedHunks => _tokens.length;
}
