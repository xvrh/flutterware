import 'lang.dart';

/// Result of a count operation for a single file.
class ResultByFile {
  final Lang lang;
  int lines = 0;
  int blanks = 0;
  int comments = 0;

  ResultByFile(this.lang);
}

/// Result of a count operation for a single language.
class ResultByLang {
  final Lang lang;
  int files = 0;
  int lines = 0;
  int blanks = 0;
  int comments = 0;

  ResultByLang(this.lang);

  @override
  String toString() {
    return '[files=$files, blanks=$blanks, comments=$comments, code=$lines]';
  }
}

List<ResultByLang> computeResultByLang(List<ResultByFile> files) {
  var results = <Lang, ResultByLang>{};

  for (var file in files) {
    var v = results[file.lang] ??= ResultByLang(file.lang);
    v.files++;
    v.lines += file.lines;
    v.blanks += file.blanks;
    v.comments += file.comments;
  }

  return results.values.toList();
}

ResultByFile computeLines(List<String> lines, Lang lang) {
  var resByFile = ResultByFile(lang);
  var idxMultiComment = -1;
  for (var line in lines) {
    idxMultiComment = _handleLine(line, lang, idxMultiComment, resByFile);
  }

  return resByFile;
}

int _handleLine(
    String line, Lang lang, int idxMultiComment, ResultByFile result) {
  // Ignore full line?
  var rmMatches = lang.rmMatches;
  if (rmMatches != null && rmMatches.hasMatch(line)) {
    return idxMultiComment;
  }

  // Should we care about a margin?
  var marginLength = lang.marginLength;
  if (marginLength != null && line.trim().isNotEmpty) {
    if (line.length < marginLength) {
      return idxMultiComment;
    }
    line = line.substring(marginLength);
  }

  // Remove spaces
  line = line.trim();

  // Are we inside a multiline comment?
  if (idxMultiComment != -1) {
    // yes, looking for the closing chars
    var idx = line.indexOf(lang.cmtMultiEnds[idxMultiComment]);
    if (idx != -1) {
      var after = line
          .substring(idx + lang.cmtMultiEnds[idxMultiComment].length)
          .trim();
      if (after.isEmpty) {
        result.comments++;
      } else {
        result.lines++;
      }
      return -1;
    }
    result.comments++;
    return idxMultiComment;
  }

  // Is line empty?
  if (line.isEmpty) {
    result.blanks++;
    return idxMultiComment;
  }

  // Single line comment?
  if (lang.cmtSingle != null && lang.cmtSingle!.hasMatch(line)) {
    result.comments++;
    return idxMultiComment;
  }

  // Ignore portions inside a line ?
  if (lang.rmInline != null && lang.rmInline!.hasMatch(line)) {
    lang.rmInline!.allMatches(line).forEach((m) {
      line = line.replaceFirst(m.group(0)!, '');
    });
  }

  // Does a multiline comment begin?
  if (idxMultiComment == -1 && lang.cmtMultiStarts.isNotEmpty) {
    var firstIdx = -1;
    for (var i = 0; i < lang.cmtMultiStarts.length; i++) {
      var containsIdx = line.indexOf(lang.cmtMultiStarts[i]);
      if (containsIdx != -1) {
        if (firstIdx == -1 || firstIdx > containsIdx) {
          firstIdx = containsIdx;
          idxMultiComment = i;
        }
      }
    }
    if (idxMultiComment != -1) {
      var insideString = false;
      if (firstIdx != 0) {
        // may be inside a string...
        var before = line.substring(0, firstIdx);
        var n1 = RegExp("'").allMatches(before).length;
        var n2 = RegExp('"').allMatches(before).length;
        if ((n1 % 2) != 0 || (n2 % 2) != 0) {
          insideString = true;
          idxMultiComment = -1;
          // ignoring
        }
      }
      if (!insideString) {
        var idxStart = line.indexOf(lang.cmtMultiStarts[idxMultiComment]);
        if (idxStart != -1) {
          var idxEnd =
              line.indexOf(lang.cmtMultiEnds[idxMultiComment], idxStart);
          if (idxEnd != -1) {
            var after = line
                .substring(idxEnd + lang.cmtMultiEnds[idxMultiComment].length)
                .trim();
            if (idxStart > 0 || after.isNotEmpty) {
              result.lines++;
            } else {
              result.comments++;
            }
            return -1;
          }

          if (idxStart > 0) {
            result.lines++;
          } else {
            result.comments++;
          }
          return idxMultiComment;
        }
      }
    }
  }

  // Here: should be safe to count the line as code
  result.lines++;
  return -1;
}
