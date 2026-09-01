/// A hunk's lines, tokenised — **two sides, and a chunk at a time**.
///
/// This is the thing about highlighting a diff that a code block does not have
/// to deal with, and the reason this file exists rather than a call to
/// `tokenizeLines` from the row widget.
///
/// A hunk is two files interleaved. Its `-` and `+` lines are alternative
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
/// Each side is then a [LazyLineTokens], which is what parses it forward in
/// chunks as rows are built. That class is shared with the plain-text body an
/// untracked file gets: the pairing above is the only part of colouring a diff
/// that a file with one side does not have.
///
/// A hunk is still a fragment, and that is the one real limit: a hunk
/// beginning inside a block comment starts the tokeniser in the wrong state and
/// there is nothing in the patch to fix it with. An untracked file has no such
/// limit — it is read whole.
///
/// Pure Dart apart from the token type, so the pairing is testable without
/// pumping a widget.
library;

import '../ui/syntax.dart';
import 'diff_lines.dart';
import 'patch_index.dart';

/// One hunk's tokens, by the index of the line within the hunk.
class HunkTokens {
  HunkTokens._(this._placed, this._new, this._old);

  /// Which side each line is on, and where in it. Null for a line that is not
  /// code — the `\ No newline at end of file` marker.
  final List<({bool old, int index})?> _placed;
  final LazyLineTokens? _new;
  final LazyLineTokens? _old;

  static final none = HunkTokens._(const [], null, null);

  /// Parses on demand, so a row that is never built costs nothing and the
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
/// The old side is only built when there is something on it, which is most
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
    LazyLineTokens(newSide, language: language),
    hasRemoved ? LazyLineTokens(oldSide, language: language) : null,
  );
}

/// Tokenises hunks once and remembers them — the twin of [HunkLineCache], with
/// the same lifetime and the same key.
///
/// Beside the line cache rather than inside it, because they are wanted at
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
