/// Word-wrapping for the TUI paint kit.
library;

/// Wrap [text] to lines no wider than [width] runes.
///
/// Splits on existing '\n' first, then word-wraps each segment on spaces.
/// A single word longer than [width] is hard-broken at the width boundary.
/// When [width] <= 0, returns the segments split only on '\n'.
List<String> wrapText(String text, int width) {
  var segments = text.split('\n');
  if (width <= 0) return segments;

  var lines = <String>[];
  for (var segment in segments) {
    var current = '';
    for (var word in segment.split(' ')) {
      var w = word;
      // Hard-break a word that cannot fit even on its own line.
      while (w.runes.length > width) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        lines.add(String.fromCharCodes(w.runes.take(width)));
        w = String.fromCharCodes(w.runes.skip(width));
      }
      if (current.isEmpty) {
        current = w;
      } else if (current.runes.length + 1 + w.runes.length <= width) {
        current = '$current $w';
      } else {
        lines.add(current);
        current = w;
      }
    }
    lines.add(current);
  }
  return lines;
}
