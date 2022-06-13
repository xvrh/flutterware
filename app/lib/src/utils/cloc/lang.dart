import 'package:path/path.dart' as p;

const _htmlCommentFrom = r'<!--';
const _htmlCommentTo = r'-->';

const _javaCommentSingle = r'^\s*//';
const _javaCommentFrom = r'/*';
const _javaCommentTo = r'*/';
const _javaRmInline = r'//.*$';

const _shCommentSingle = r'^\s*#';
const _shRmMatches = r'^\s*#!';

const _sqlCommentSingle = r'^\s*--';

/// Static information relative to a single language.
class Lang {
  static final java = Lang('Java', const ['.java'], _javaCommentSingle)
    ..withMulti(_javaCommentFrom, _javaCommentTo)
    ..withRmInline(_javaRmInline);
  static final javaScript =
      Lang('JavaScript', const ['.js', '.jsx'], _javaCommentSingle)
        ..withMulti(_javaCommentFrom, _javaCommentTo)
        ..withRmInline(_javaRmInline);
  static final typeScript =
      Lang('TypeScript', const ['.ts', '.tsx'], _javaCommentSingle)
        ..withMulti(_javaCommentFrom, _javaCommentTo)
        ..withRmInline(_javaRmInline);
  static final html = Lang.noSingle('HTML', ['.html', '.htm'])
    ..withMulti(_htmlCommentFrom, _htmlCommentTo);
  static final sql = Lang('SQL', ['.sql', '.psql'], _sqlCommentSingle)
    ..withMulti(_javaCommentFrom, _javaCommentTo);
  static final shell = Lang('Shell', ['.sh'], _shCommentSingle)
    ..withRmMatches(_shRmMatches);
  static final csharp = Lang('C#', ['.cs'], _javaCommentSingle)
    ..withMulti(_javaCommentFrom, _javaCommentTo)
    ..withRmInline(_javaRmInline);
  static final xml = Lang.noSingle('XML', ['.xml'])
    ..withMulti(_htmlCommentFrom, _htmlCommentTo);
  static final dart = Lang('Dart', ['.dart'], _javaCommentSingle)
    ..withMulti(_javaCommentFrom, _javaCommentTo)
    ..withRmInline(_javaRmInline);

  static final languages = [
    java,
    javaScript,
    typeScript,
    html,
    sql,
    shell,
    csharp,
    xml,
    dart,
  ];

  /// Returns the lang object given a [filename], `null` otherwise.
  static Lang? fromFileName(String filename) {
    var extension = p.extension(filename).toLowerCase();
    for (var each in languages) {
      if (each.extensions.contains(extension)) {
        return each;
      }
    }
    return null;
  }

  /// Language file extension.
  final List<String> extensions;

  /// Language human readable description.
  final String name;

  /// Language single line comment.
  RegExp? cmtSingle;

  /// Language multi line comment start.
  final cmtMultiStarts = <String>[];

  /// Language multi line comment end.
  final cmtMultiEnds = <String>[];
  // In order to ignore portions inside a line.
  RegExp? rmInline;
  // In order to ignore full lines.
  RegExp? rmMatches;

  /// Some languages use a margin.
  int? marginLength;

  Lang(this.name, this.extensions, String? cmtSingle) {
    if (cmtSingle != null) {
      this.cmtSingle = RegExp(cmtSingle);
    }
  }

  Lang.noSingle(
    this.name,
    this.extensions,
  );

  void withMulti(String cmtMultiStart, String cmtMultiEnd) {
    cmtMultiStarts.add(cmtMultiStart);
    cmtMultiEnds.add(cmtMultiEnd);
  }

  void withMargin(int marginLength) {
    this.marginLength = marginLength;
  }

  void withRmInline(String? rmInline) {
    if (rmInline != null) {
      this.rmInline = RegExp(rmInline);
    }
  }

  void withRmMatches(String? rmMatches) {
    if (rmMatches != null) {
      this.rmMatches = RegExp(rmMatches);
    }
  }
}
