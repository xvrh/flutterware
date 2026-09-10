import 'package:flutter/widgets.dart';

/// The smallest thing that behaves like a markdown renderer, so the demo has a
/// widget that really does destroy the catalog's string.
///
/// It splits the source on `**` and builds its own spans out of the pieces —
/// which is what any markdown package does, and why object identity cannot
/// follow the words down here: every span holds a fresh substring, and the
/// `**` themselves never reach a glyph at all.
///
/// The recovery is [data]. The string the catalog handed out is still sitting
/// on this widget untouched, and a scenario says so in one line:
///
/// ```dart
/// indexTranslationsIn<MiniMarkdown>((widget) => widget.data);
/// ```
///
/// Hand-rolled rather than a dependency on purpose: the point is the *shape* —
/// a widget that takes a string and renders it its own way — and a real
/// markdown package would only make the demo heavier, not more honest.
class MiniMarkdown extends StatelessWidget {
  const MiniMarkdown(this.data, {super.key, this.style, this.textAlign});

  /// The source text, `**bold**` and all.
  final String data;

  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        for (var (bold, text) in _split(data))
          TextSpan(
            text: text,
            style: bold ? const TextStyle(fontWeight: FontWeight.w900) : null,
          ),
      ],
    ),
    style: style,
    textAlign: textAlign,
  );

  /// `(bold, text)` runs, alternating on every `**`.
  ///
  /// An unclosed `**` is left to the last run rather than treated as an error:
  /// a renderer that throws on a translator's typo would take the screen down.
  static List<(bool, String)> _split(String source) {
    var runs = <(bool, String)>[];
    var bold = false;
    var at = 0;
    while (true) {
      var mark = source.indexOf('**', at);
      if (mark < 0) break;
      if (mark > at) runs.add((bold, source.substring(at, mark)));
      bold = !bold;
      at = mark + 2;
    }
    if (at < source.length) runs.add((bold, source.substring(at)));
    return runs;
  }
}
