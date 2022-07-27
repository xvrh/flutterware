import 'dart:math' as math;


String getElapsedAsSeconds(Duration duration) {
  final double seconds = duration.inMilliseconds / Duration.millisecondsPerSecond;
  return '${seconds.toStringAsFixed(1)}s';
}

String getElapsedAsMilliseconds(Duration duration) {
  return '${duration.inMilliseconds}ms';
}


/// Smallest column that will be used for text wrapping. If the requested column
/// width is smaller than this, then this is what will be used.
const int kMinColumnWidth = 10;

/// Wraps a block of text into lines no longer than [columnWidth].
///
/// Tries to split at whitespace, but if that's not good enough to keep it under
/// the limit, then it splits in the middle of a word. If [columnWidth] (minus
/// any indent) is smaller than [kMinColumnWidth], the text is wrapped at that
/// [kMinColumnWidth] instead.
///
/// Preserves indentation (leading whitespace) for each line (delimited by '\n')
/// in the input, and will indent wrapped lines that same amount, adding
/// [indent] spaces in addition to any existing indent.
///
/// If [hangingIndent] is supplied, then that many additional spaces will be
/// added to each line, except for the first line. The [hangingIndent] is added
/// to the specified [indent], if any. This is useful for wrapping
/// text with a heading prefix (e.g. "Usage: "):
///
/// ```dart
/// String prefix = "Usage: ";
/// print(prefix + wrapText(invocation, indent: 2, hangingIndent: prefix.length, columnWidth: 40));
/// ```
///
/// yields:
/// ```
///   Usage: app main_command <subcommand>
///          [arguments]
/// ```
///
/// If [outputPreferences.wrapText] is false, then the text will be returned
/// unchanged. If [shouldWrap] is specified, then it overrides the
/// [outputPreferences.wrapText] setting.
///
/// If the amount of indentation (from the text, [indent], and [hangingIndent])
/// is such that less than [kMinColumnWidth] characters can fit in the
/// [columnWidth], then the indent is truncated to allow the text to fit.
String wrapText(String text, {
  required int columnWidth,
  required bool shouldWrap,
  int? hangingIndent,
  int? indent,
}) {
  assert(columnWidth >= 0);
  if (text == null || text.isEmpty) {
    return '';
  }
  indent ??= 0;
  hangingIndent ??= 0;
  final List<String> splitText = text.split('\n');
  final List<String> result = <String>[];
  for (final String line in splitText) {
    String trimmedText = line.trimLeft();
    final String leadingWhitespace = line.substring(0, line.length - trimmedText.length);
    List<String> notIndented;
    if (hangingIndent != 0) {
      // When we have a hanging indent, we want to wrap the first line at one
      // width, and the rest at another (offset by hangingIndent), so we wrap
      // them twice and recombine.
      final List<String> firstLineWrap = _wrapTextAsLines(
        trimmedText,
        columnWidth: columnWidth - leadingWhitespace.length - indent,
        shouldWrap: shouldWrap,
      );
      notIndented = <String>[firstLineWrap.removeAt(0)];
      trimmedText = trimmedText.substring(notIndented[0].length).trimLeft();
      if (trimmedText.isNotEmpty) {
        notIndented.addAll(_wrapTextAsLines(
          trimmedText,
          columnWidth: columnWidth - leadingWhitespace.length - indent - hangingIndent,
          shouldWrap: shouldWrap,
        ));
      }
    } else {
      notIndented = _wrapTextAsLines(
        trimmedText,
        columnWidth: columnWidth - leadingWhitespace.length - indent,
        shouldWrap: shouldWrap,
      );
    }
    String? hangingIndentString;
    final String indentString = ' ' * indent;
    result.addAll(notIndented.map<String>(
          (String line) {
        // Don't return any lines with just whitespace on them.
        if (line.isEmpty) {
          return '';
        }
        String truncatedIndent = '$indentString${hangingIndentString ?? ''}$leadingWhitespace';
        if (truncatedIndent.length > columnWidth - kMinColumnWidth) {
          truncatedIndent = truncatedIndent.substring(0, math.max(columnWidth - kMinColumnWidth, 0));
        }
        final String result = '$truncatedIndent$line';
        hangingIndentString ??= ' ' * hangingIndent!;
        return result;
      },
    ));
  }
  return result.join('\n');
}

// Used to represent a run of ANSI control sequences next to a visible
// character.
class _AnsiRun {
  _AnsiRun(this.original, this.character);

  String original;
  String character;
}

/// Wraps a block of text into lines no longer than [columnWidth], starting at the
/// [start] column, and returning the result as a list of strings.
///
/// Tries to split at whitespace, but if that's not good enough to keep it
/// under the limit, then splits in the middle of a word. Preserves embedded
/// newlines, but not indentation (it trims whitespace from each line).
///
/// If [columnWidth] is not specified, then the column width will be the width of the
/// terminal window by default. If the stdout is not a terminal window, then the
/// default will be [outputPreferences.wrapColumn].
///
/// The [columnWidth] is clamped to [kMinColumnWidth] at minimum (so passing negative
/// widths is fine, for instance).
///
/// If [outputPreferences.wrapText] is false, then the text will be returned
/// simply split at the newlines, but not wrapped. If [shouldWrap] is specified,
/// then it overrides the [outputPreferences.wrapText] setting.
List<String> _wrapTextAsLines(String text, {
  int start = 0,
  required int columnWidth,
  required bool shouldWrap,
}) {
  if (text == null || text.isEmpty) {
    return <String>[''];
  }
  assert(start >= 0);

  // Splits a string so that the resulting list has the same number of elements
  // as there are visible characters in the string, but elements may include one
  // or more adjacent ANSI sequences. Joining the list elements again will
  // reconstitute the original string. This is useful for manipulating "visible"
  // characters in the presence of ANSI control codes.
  List<_AnsiRun> splitWithCodes(String input) {
    final RegExp characterOrCode = RegExp('(\u001b\\[[0-9;]*m|.)', multiLine: true);
    List<_AnsiRun> result = <_AnsiRun>[];
    final StringBuffer current = StringBuffer();
    for (final Match match in characterOrCode.allMatches(input)) {
      current.write(match[0]);
      if (match[0]!.length < 4) {
        // This is a regular character, write it out.
        result.add(_AnsiRun(current.toString(), match[0]!));
        current.clear();
      }
    }
    // If there's something accumulated, then it must be an ANSI sequence, so
    // add it to the end of the last entry so that we don't lose it.
    if (current.isNotEmpty) {
      if (result.isNotEmpty) {
        result.last.original += current.toString();
      } else {
        // If there is nothing in the string besides control codes, then just
        // return them as the only entry.
        result = <_AnsiRun>[_AnsiRun(current.toString(), '')];
      }
    }
    return result;
  }

  String joinRun(List<_AnsiRun> list, int start, [ int? end ]) {
    return list.sublist(start, end).map<String>((_AnsiRun run) => run.original).join().trim();
  }

  final List<String> result = <String>[];
  final int effectiveLength = math.max(columnWidth - start, kMinColumnWidth);
  for (final String line in text.split('\n')) {
    // If the line is short enough, even with ANSI codes, then we can just add
    // add it and move on.
    if (line.length <= effectiveLength || !shouldWrap) {
      result.add(line);
      continue;
    }
    final List<_AnsiRun> splitLine = splitWithCodes(line);
    if (splitLine.length <= effectiveLength) {
      result.add(line);
      continue;
    }

    int currentLineStart = 0;
    int? lastWhitespace;
    // Find the start of the current line.
    for (int index = 0; index < splitLine.length; ++index) {
      if (splitLine[index].character.isNotEmpty && _isWhitespace(splitLine[index])) {
        lastWhitespace = index;
      }

      if (index - currentLineStart >= effectiveLength) {
        // Back up to the last whitespace, unless there wasn't any, in which
        // case we just split where we are.
        if (lastWhitespace != null) {
          index = lastWhitespace;
        }

        result.add(joinRun(splitLine, currentLineStart, index));

        // Skip any intervening whitespace.
        while (index < splitLine.length && _isWhitespace(splitLine[index])) {
          index++;
        }

        currentLineStart = index;
        lastWhitespace = null;
      }
    }
    result.add(joinRun(splitLine, currentLineStart));
  }
  return result;
}

/// Returns true if the code unit at [index] in [text] is a whitespace
/// character.
///
/// Based on: https://en.wikipedia.org/wiki/Whitespace_character#Unicode
bool _isWhitespace(_AnsiRun run) {
  final int rune = run.character.isNotEmpty ? run.character.codeUnitAt(0) : 0x0;
  return rune >= 0x0009 && rune <= 0x000D ||
      rune == 0x0020 ||
      rune == 0x0085 ||
      rune == 0x1680 ||
      rune == 0x180E ||
      rune >= 0x2000 && rune <= 0x200A ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202F ||
      rune == 0x205F ||
      rune == 0x3000 ||
      rune == 0xFEFF;
}