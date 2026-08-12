/// Source code, tokenised — the one place the vendored `highlight` is spoken
/// to, and the one place a token class becomes a colour.
///
/// **Tokens, not spans.** The tokeniser's answer is cached by callers that
/// know nothing about a `BuildContext`, and a `TextSpan` carries a `Color` from
/// the palette — so a cache of spans is a cache that goes wrong the moment the
/// window changes theme. What is cached is [Token]s, which are plain data; the
/// colour is applied where the widget is built. It also makes the tokeniser
/// testable without pumping anything.
///
/// **The tokeniser is borrowed and the palette is not.** `highlight` ships
/// themes and none of them is this app's: they are picked for a light or a dark
/// editor, and this app is both. So the colours come from [FwPalette] — the same
/// greens and ambers the JSON view and the diff already use for the same kinds
/// of thing.
library;

import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/highlight_core.dart'
    show Mode, Node, highlight;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/bash.dart'
    as lang_bash;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/css.dart'
    as lang_css;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/dart.dart'
    as lang_dart;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/go.dart'
    as lang_go;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/groovy.dart'
    as lang_groovy;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/java.dart'
    as lang_java;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/javascript.dart'
    as lang_javascript;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/json.dart'
    as lang_json;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/kotlin.dart'
    as lang_kotlin;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/objectivec.dart'
    as lang_objectivec;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/python.dart'
    as lang_python;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/ruby.dart'
    as lang_ruby;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/rust.dart'
    as lang_rust;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/sql.dart'
    as lang_sql;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/swift.dart'
    as lang_swift;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/typescript.dart'
    as lang_typescript;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/xml.dart'
    as lang_xml;
// ignore: implementation_imports
import 'package:flutterware/src/third_party/highlight/lib/languages/yaml.dart'
    as lang_yaml;

import 'theme.dart';

/// One coloured run of a line. [className] is highlight.js's own vocabulary —
/// `keyword`, `string`, `comment` — or null for text no rule claimed.
class Token {
  const Token(this.text, [this.className]);

  final String text;
  final String? className;

  @override
  bool operator ==(Object other) =>
      other is Token && other.text == text && other.className == className;

  @override
  int get hashCode => Object.hash(text, className);

  @override
  String toString() => 'Token(${className ?? '-'}: $text)';
}

/// **A dozen and a half languages, not all 190.** `languages/all.dart` compiles
/// every definition `highlight` ships into the binary for a screen that will
/// meet four of them. These are the ones a Flutter repository's diff actually
/// contains; anything else is drawn plain, which is what the screen did before
/// there was any highlighting at all and is a perfectly good answer.
const _byExtension = {
  'dart': 'dart',
  'yaml': 'yaml',
  'yml': 'yaml',
  'json': 'json',
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'gradle': 'groovy',
  'groovy': 'groovy',
  'swift': 'swift',
  'java': 'java',
  'm': 'objectivec',
  'mm': 'objectivec',
  'h': 'objectivec',
  'py': 'python',
  'rb': 'ruby',
  'go': 'go',
  'rs': 'rust',
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'sql': 'sql',
  'xml': 'xml',
  'html': 'xml',
  'htm': 'xml',
  'plist': 'xml',
  'css': 'css',
};

/// Files with no extension that are still a language everybody knows.
const _byName = {'Podfile': 'ruby', 'Gemfile': 'ruby', 'Rakefile': 'ruby'};

/// Not `const`: a `Mode` is built at runtime, so this is the one table here
/// that cannot be. It is still a compile-time *set* — an unimported grammar is
/// unreachable and tree-shaken, which is the point of naming eighteen rather
/// than importing `languages/all.dart`.
final _definitions = {
  'bash': lang_bash.bash,
  'css': lang_css.css,
  'dart': lang_dart.dart,
  'go': lang_go.go,
  'groovy': lang_groovy.groovy,
  'java': lang_java.java,
  'javascript': lang_javascript.javascript,
  'json': lang_json.json,
  'kotlin': lang_kotlin.kotlin,
  'objectivec': lang_objectivec.objectivec,
  'python': lang_python.python,
  'ruby': lang_ruby.ruby,
  'rust': lang_rust.rust,
  'sql': lang_sql.sql,
  'swift': lang_swift.swift,
  'typescript': lang_typescript.typescript,
  'xml': lang_xml.xml,
  'yaml': lang_yaml.yaml,
};

/// Which language [path] is written in, or null for one we do not colour.
///
/// By extension, never by sniffing the content: a diff is a fragment, so
/// content detection would be guessing from a few lines — and `autoDetection`
/// runs every registered grammar over the text, which is the one thing here
/// expensive enough to matter.
String? languageForPath(String path) {
  var name = path.split('/').last;
  if (_byName[name] case var it?) return it;
  var dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return _byExtension[name.substring(dot + 1).toLowerCase()];
}

final _registered = <String>{};

/// Where a parse left the tokeniser.
///
/// Opaque on purpose: it is a vendored `Mode`, and nothing above this file has
/// any business knowing that. Hand it to the next [tokenizeChunk] and the two
/// calls together produce exactly what one call over the whole text would —
/// which is what makes parsing a long file in pieces a *scheduling* decision
/// rather than a correctness one.
class SyntaxState {
  const SyntaxState._(this._top);

  final Mode? _top;
}

/// [source] as [language], one list of [Token]s per line.
///
/// **Parsed whole, then split** — never line by line. A string, a block comment
/// and a raw string all span lines, and a per-line parse starts each one in the
/// default state, so the second line of every comment comes back as code.
///
/// An unknown [language] gives one plain token per line rather than throwing.
List<List<Token>> tokenizeLines(String source, {required String? language}) =>
    tokenizeChunk(source, language: language).lines;

/// The same, resumably: [from] continues a previous chunk, and [SyntaxState] in
/// the result continues this one.
///
/// What this cannot fix is a construct that opened above text nobody has —
/// a diff hunk starting inside a block comment, where the bytes above are not
/// in the patch at all. Within one text, chunked or not, the answer is the same.
({List<List<Token>> lines, SyntaxState state}) tokenizeChunk(
  String source, {
  required String? language,
  SyntaxState? from,
}) {
  var lines = source.split('\n');
  var definition = language == null ? null : _definitions[language];
  if (definition == null) {
    return (
      lines: [
        for (var line in lines) [Token(line)],
      ],
      state: const SyntaxState._(null),
    );
  }
  if (_registered.add(language!)) {
    highlight.registerLanguage(language, definition);
  }

  var out = <List<Token>>[[]];
  void emit(String text, String? className) {
    // A token's text can straddle newlines — a block comment is one node — so
    // the split happens here rather than on the source, which is what keeps
    // the tree walk and the line numbering from having to agree twice.
    var parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) out.add([]);
      if (parts[i].isNotEmpty) out.last.add(Token(parts[i], className));
    }
  }

  void walk(List<Node> nodes, String? inherited) {
    for (var node in nodes) {
      var className = node.className ?? inherited;
      if (node.value case var value?) {
        emit(value, className);
      } else if (node.children case var children?) {
        walk(children, className);
      }
    }
  }

  var result = highlight.parse(
    source,
    language: language,
    continuation: from?._top,
  );
  walk(result.nodes ?? const [], null);

  // The tokeniser drops nothing, but a grammar that failed to consume the tail
  // would leave this short — and a caller indexing by line must not walk off
  // the end of it.
  while (out.length < lines.length) {
    out.add([Token(lines[out.length])]);
  }
  return (lines: out, state: SyntaxState._(result.top));
}

/// What a token class is drawn in.
///
/// Null for text no rule claimed, which inherits whatever the row is already
/// using — the diff's own tint for an added or removed line.
Color? tokenColor(BuildContext context, String? className) {
  var colors = context.colors;
  // The classes highlight.js emits, collapsed to the six things this palette
  // has an opinion about. Everything else reads as plain code, which is the
  // right default: a highlighter that colours nine kinds of thing is a
  // highlighter nobody can read a diff through.
  return switch (className) {
    'comment' || 'quote' => colors.mut2,
    'string' || 'subst' || 'regexp' || 'symbol' => colors.grn,
    'number' || 'literal' => colors.amber,
    'keyword' || 'built_in' || 'selector-tag' => colors.accent,
    'type' ||
    'class' ||
    'title' ||
    'meta' ||
    'attr' ||
    'attribute' => colors.info,
    _ => null,
  };
}

/// [tokens] as spans, coloured from the palette.
List<InlineSpan> spansFor(
  BuildContext context,
  List<Token> tokens, {
  TextStyle? style,
}) => [
  for (var token in tokens)
    TextSpan(
      text: token.text,
      style: (style ?? const TextStyle()).copyWith(
        color: tokenColor(context, token.className),
      ),
    ),
];

/// [source] as one flat list of spans — a code *block*, where a diff wants
/// [tokenizeLines].
List<InlineSpan> codeSpans(
  BuildContext context,
  String source, {
  String language = 'dart',
}) {
  var lines = tokenizeLines(source, language: language);
  return [
    for (var (index, tokens) in lines.indexed) ...[
      if (index > 0) const TextSpan(text: '\n'),
      ...spansFor(context, tokens),
    ],
  ];
}
