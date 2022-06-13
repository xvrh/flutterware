import 'dart:io';
import 'package:collection/collection.dart';
import 'count.dart';
import 'lang.dart';

export 'lang.dart' show Lang;

typedef ExclusionPredicate = bool Function(Lang, List<String>);

ClocReport countLinesOfCode(Iterable<File> files,
    {ExclusionPredicate? exclude}) {
  var results = <ResultByFile>[];
  for (var file in files) {
    var lang = Lang.fromFileName(file.path);
    if (lang != null) {
      var lines = file.readAsLinesSync();

      var isExcluded = false;
      if (exclude != null) {
        isExcluded = exclude(lang, lines);
      }

      if (!isExcluded) {
        var result = computeLines(lines, lang);
        results.add(result);
      }
    }
  }
  var resultsByLang = computeResultByLang(results);

  return ClocReport(
      ClocResult(
          files: resultsByLang.map((r) => r.files).sum,
          lines: resultsByLang.map((r) => r.lines).sum,
          comments: resultsByLang.map((r) => r.comments).sum,
          blanks: resultsByLang.map((r) => r.blanks).sum),
      {
        for (var l in resultsByLang)
          l.lang: ClocResult(
            files: l.files,
            lines: l.lines,
            comments: l.comments,
            blanks: l.blanks,
          ),
      });
}

class ClocReport {
  final ClocResult global;
  final Map<Lang, ClocResult> languages;

  ClocReport(this.global, this.languages);

  ClocResult forLanguage(Lang lang) => languages[lang] ?? ClocResult.zero;

  @override
  String toString() => 'ClocReport(global: $global, languages: $languages)';
}

class ClocResult {
  static final zero = ClocResult(files: 0, lines: 0, comments: 0, blanks: 0);

  final int files;
  final int lines;
  final int comments;
  final int blanks;

  ClocResult(
      {required this.files,
      required this.lines,
      required this.comments,
      required this.blanks});

  ClocResult operator +(ClocResult other) {
    return ClocResult(
        files: files + other.files,
        lines: lines + other.lines,
        blanks: blanks + other.blanks,
        comments: comments + other.comments);
  }

  @override
  String toString() => 'ClocResult(files: $files, lines: $lines, '
      'comments: $comments, blanks: $blanks';
}

bool linesContainsAnyOf(Iterable<String> lines, Iterable<String> anyOf) {
  for (var line in lines) {
    line = line.toLowerCase();
    for (var matcher in anyOf) {
      if (line.contains(matcher.toLowerCase())) {
        return true;
      }
    }
  }
  return false;
}
