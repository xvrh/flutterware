import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/diff_lines.dart';
import 'package:flutterware_app/src/changes/hunk_syntax.dart';
import 'package:flutterware_app/src/ui/syntax.dart';

/// The two things about highlighting a *diff* that a code block does not have
/// to deal with: a hunk is two files interleaved, and a hunk is a fragment.
void main() {
  DiffLine line(DiffLineKind kind, String text) =>
      DiffLine(kind: kind, text: text);

  /// The class the highlighter gave [text] within [tokens], or null.
  String? classOf(List<Token>? tokens, String text) {
    for (var token in tokens ?? const <Token>[]) {
      if (token.text.contains(text)) return token.className;
    }
    return null;
  }

  group('the language table', () {
    test('by extension, case-insensitively', () {
      expect(languageForPath('app/lib/main.dart'), 'dart');
      expect(languageForPath('pubspec.YAML'), 'yaml');
      expect(languageForPath('ios/Runner/Info.plist'), 'xml');
      expect(languageForPath('android/app/build.gradle'), 'groovy');
    });

    test('a name with no extension, when everybody knows it', () {
      expect(languageForPath('ios/Podfile'), 'ruby');
    });

    test('anything else is null, which draws plain', () {
      // Not an error and not a guess. A `.md` diff is prose, and prose lit up
      // as code is worse than prose.
      expect(languageForPath('README.md'), isNull);
      expect(languageForPath('LICENSE'), isNull);
      expect(languageForPath('lib/thing.'), isNull);
    });
  });

  group('a line at a time', () {
    test('a multi-line string stays a string on its second line', () {
      // The whole reason the hunk is parsed as one text rather than per line:
      // a per-line parse starts each line in the default state, so the second
      // line of every multi-line construct comes back as code.
      var lines = tokenizeLines(
        "var a = '''\nstill a string\n''';",
        language: 'dart',
      );
      expect(lines, hasLength(3));
      expect(classOf(lines[1], 'still a string'), 'string');
    });

    test('one list per line, always — even for trailing blanks', () {
      var lines = tokenizeLines('var a = 1;\n\n\n', language: 'dart');
      expect(lines, hasLength(4));
    });

    test('an unknown language is one plain token per line', () {
      var lines = tokenizeLines('a\nb', language: null);
      expect(lines, [
        [const Token('a')],
        [const Token('b')],
      ]);
    });
  });

  group('two sides, not one text', () {
    test('a removed line cannot corrupt the added line under it', () {
      // The failure this exists to prevent: fed as one string, the `'` that the
      // removed line opens is closed by the `'` on the added line, and
      // everything between reads as one string. Parsed per side, neither line
      // has ever seen the other.
      var lines = [
        line(DiffLineKind.context, 'void main() {'),
        line(DiffLineKind.removed, "  var a = 'unterminated"),
        line(DiffLineKind.added, "  var a = 'closed';"),
        line(DiffLineKind.context, '}'),
      ];

      var tokens = tokenizeHunk(lines, language: 'dart');

      expect(
        classOf(tokens.at(2), 'closed'),
        'string',
        reason: 'the added line is a string of its own',
      );
      expect(
        classOf(tokens.at(2), 'var'),
        'keyword',
        reason: "the added line's keyword survived the removed line above it",
      );
      expect(
        classOf(tokens.at(3), '}'),
        isNull,
        reason: 'the context line after it is code, not the tail of a string',
      );
    });

    test('a context line reads from the new side', () {
      var lines = [
        line(DiffLineKind.removed, 'final x = 1;'),
        line(DiffLineKind.added, 'const x = 2;'),
        line(DiffLineKind.context, 'return x;'),
      ];

      var tokens = tokenizeHunk(lines, language: 'dart');
      expect(classOf(tokens.at(0), 'final'), 'keyword');
      expect(classOf(tokens.at(1), 'const'), 'keyword');
      expect(classOf(tokens.at(2), 'return'), 'keyword');
    });

    test('a meta line is not code and gets nothing', () {
      var lines = [
        line(DiffLineKind.added, 'var a = 1;'),
        line(DiffLineKind.meta, r'\ No newline at end of file'),
      ];

      var tokens = tokenizeHunk(lines, language: 'dart');
      expect(tokens.at(0), isNotNull);
      expect(tokens.at(1), isNull);
    });

    test('every line of a long hunk still lines up', () {
      // The pairing is index arithmetic over two lists, and an off-by-one here
      // would colour one line with another's tokens — a bug that looks like a
      // bad highlighter rather than like a bad index.
      var lines = [
        for (var i = 0; i < 60; i++)
          line(switch (i % 3) {
            0 => DiffLineKind.context,
            1 => DiffLineKind.added,
            _ => DiffLineKind.removed,
          }, 'var v$i = $i;'),
      ];

      var tokens = tokenizeHunk(lines, language: 'dart');
      for (var i = 0; i < lines.length; i++) {
        expect(
          classOf(tokens.at(i), 'v$i'),
          isNull,
          reason: 'v$i is an identifier wherever it is',
        );
        expect(
          [for (var t in tokens.at(i)!) t.text].join(),
          'var v$i = $i;',
          reason: 'line $i kept its own text',
        );
      }
    });
  });

  group('chunked, and identical to parsing it whole', () {
    /// A hunk of [count] added lines, `mark`ed at [markAt] so a test can find
    /// one line among a thousand.
    List<DiffLine> tall(int count, {int? markAt, String mark = ''}) => [
      for (var i = 0; i < count; i++)
        line(DiffLineKind.added, i == markAt ? mark : 'var v$i = $i;'),
    ];

    test('a hunk far past one chunk is still coloured', () {
      // The whole point of chunking rather than capping: there is no size at
      // which this screen quietly stops colouring. A wholly added file arrives
      // as one hunk of a thousand lines and is the case that used to go grey.
      var tokens = tokenizeHunk(tall(1200), language: 'dart');

      expect(classOf(tokens.at(0), 'var'), 'keyword');
      expect(
        classOf(tokens.at(1199), 'var'),
        'keyword',
        reason: 'the last line of the fifth chunk, as much as the first',
      );
    });

    test('a construct that straddles a chunk boundary survives it', () {
      // The reason the tokeniser's own state is threaded from one chunk to the
      // next rather than each chunk starting fresh. Parsed independently, the
      // chunk beginning inside this string would read it as code.
      var opensAt = highlightChunkLines - 2;
      var lines = [
        ...tall(opensAt),
        line(DiffLineKind.added, "var doc = '''"),
        for (var i = 0; i < 10; i++)
          line(DiffLineKind.added, 'still inside the string $i'),
        line(DiffLineKind.added, "''';"),
      ];

      var tokens = tokenizeHunk(lines, language: 'dart');

      // Read across the boundary, which is where a fresh-start chunk would go
      // wrong — several lines past it, so this is not the boundary line itself.
      expect(
        classOf(tokens.at(opensAt + 5), 'still inside the string 4'),
        'string',
      );
    });

    test('a line reads the same however you arrived at it', () {
      // Chunk boundaries are line indices, never the viewport. If they were the
      // viewport, this is the test that would fail: the same line, asked for
      // after a different first read, coming back a different colour.
      var lines = [
        ...tall(highlightChunkLines * 2),
        line(DiffLineKind.added, "var tail = 'x';"),
      ];

      var topFirst = tokenizeHunk(lines, language: 'dart');
      topFirst.at(0);
      var jumped = tokenizeHunk(lines, language: 'dart');

      var last = lines.length - 1;
      expect(
        [for (var t in jumped.at(last)!) '${t.className}:${t.text}'],
        [for (var t in topFirst.at(last)!) '${t.className}:${t.text}'],
      );
    });

    test('a file with no grammar is never parsed at all', () {
      var lines = [line(DiffLineKind.added, '# a heading')];
      expect(tokenizeHunk(lines, language: null).at(0), isNull);
    });
  });
}
