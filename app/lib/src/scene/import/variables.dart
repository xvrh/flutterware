// A design file's variables, as saved JSON, becoming `scene_tokens.dart`.
//
// The smallest slice of the importer, pulled forward (master plan, M5½):
// variables need no node import at all, and they put real data against the
// token declaration before styles are built on it. Built on the JSON the
// design tool's REST API answers for a file's local variables — saved to
// disk, never fetched here, so CI needs no credential and the network lane
// (M8) is a wrapper around this.
//
// The rules the plan sets for every import apply: a variable that cannot be
// a token is REFUSED, by name and with the reason, never approximated. What
// is refused is the list of what to build next.
//
// The shape read (the variables endpoint's `meta`):
//
//   variableCollections: { id: { name, modes: [{modeId, name}],
//                                defaultModeId, variableIds } }
//   variables: { id: { name, resolvedType: COLOR|FLOAT|STRING|BOOLEAN,
//                      variableCollectionId, valuesByMode: { modeId: value },
//                      deletedButReferenced?, hiddenFromPublishing? } }
//
// A value is `{r, g, b, a}` in 0..1, a number, a string, a bool, or an
// alias `{type: 'VARIABLE_ALIAS', id}` to another variable — resolved in the
// same-named mode of the other variable's collection, else its default.
import 'dart:convert';

import 'package:flutterware/scene_authoring.dart';

import '../tokens_file.dart';

/// One variable that became a token: the identifier it got, where it came
/// from, its kind, its default value and the value in every mode.
class ImportedToken {
  ImportedToken({
    required this.name,
    required this.source,
    required this.kind,
    required this.value,
    required this.modes,
  });

  /// The Dart identifier — `brandPrimary` from `Brand/Primary`.
  final String name;

  /// `Collection · Variable/Name`, as the design file spells it.
  final String source;

  final SceneParamKind kind;
  final Object value;

  /// Mode name (an identifier) to value, every mode of the collection —
  /// the default mode included, so a set can be asked for by its name.
  final Map<String, Object> modes;

  SceneTokenDecl get decl => SceneTokenDecl(name, kind, value, modes: modes);
}

/// A variable that was not imported, and why.
class ImportRefusal {
  ImportRefusal(this.what, this.reason);

  /// The variable, as the design file names it.
  final String what;
  final String reason;

  @override
  String toString() => '$what — $reason';
}

/// What a read of the variables produced: the tokens, in the design file's
/// order, and every refusal.
class VariablesImport {
  VariablesImport(this.tokens, this.refusals, this.modeNames);

  final List<ImportedToken> tokens;
  final List<ImportRefusal> refusals;

  /// Every mode name across the collections, in first-seen order.
  final List<String> modeNames;
}

/// Reads the variables JSON — the endpoint's whole response or its `meta`.
VariablesImport importVariables(String json) {
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    return VariablesImport(const [], [
      ImportRefusal('the file', 'not JSON: ${e.message}'),
    ], const []);
  }
  if (decoded is! Map) {
    return VariablesImport(const [], [
      ImportRefusal('the file', 'not a JSON object'),
    ], const []);
  }
  var meta = switch (decoded['meta']) {
    Map m => m,
    _ => decoded,
  };
  var collections = (meta['variableCollections'] as Map?) ?? const {};
  var variables = (meta['variables'] as Map?) ?? const {};
  if (collections.isEmpty || variables.isEmpty) {
    return VariablesImport(const [], [
      ImportRefusal(
        'the file',
        'no variableCollections and variables — this is not the variables '
            "endpoint's answer",
      ),
    ], const []);
  }
  return _Importer(
    collections.cast<String, Object?>(),
    variables.cast<String, Object?>(),
  ).run();
}

class _Importer {
  _Importer(this.collections, this.variables);

  final Map<String, Object?> collections;
  final Map<String, Object?> variables;
  final refusals = <ImportRefusal>[];

  /// modeId → identifier, across every collection; same-named modes in two
  /// collections share the identifier, which is what makes `dark` one set.
  final _modeName = <String, String>{};
  final _modeNames = <String>[];

  VariablesImport run() {
    for (var c in collections.values) {
      var collection = c! as Map;
      for (var m in (collection['modes'] as List?) ?? const []) {
        var mode = m as Map;
        // A mode is a whole set, so a name that is a keyword — "Default" is
        // the design tool's own default — gets a suffix rather than taking
        // every variable of the collection down with it.
        var name =
            _identifier('${mode['name']}') ??
            _identifier('${mode['name']} mode');
        if (name == null) {
          refusals.add(
            ImportRefusal(
              'mode "${mode['name']}" of ${collection['name']}',
              'its name makes no identifier',
            ),
          );
          continue;
        }
        _modeName['${mode['modeId']}'] = name;
        if (!_modeNames.contains(name)) _modeNames.add(name);
      }
    }

    var tokens = <ImportedToken>[];
    var taken = <String, String>{};
    // The file's own order, by collection then by the collection's list.
    for (var c in collections.values) {
      var collection = c! as Map;
      for (var id in (collection['variableIds'] as List?) ?? const []) {
        var raw = variables['$id'];
        if (raw is! Map) continue;
        var source = '${collection['name']} · ${raw['name']}';
        if (raw['deletedButReferenced'] == true) continue;
        var kind = _kind('${raw['resolvedType']}');
        if (kind == null) {
          refusals.add(
            ImportRefusal(
              source,
              'a ${raw['resolvedType']} is not a token kind',
            ),
          );
          continue;
        }
        var name = _identifier('${raw['name']}');
        if (name == null) {
          refusals.add(ImportRefusal(source, 'its name makes no identifier'));
          continue;
        }
        if (taken[name] case var other?) {
          refusals.add(
            ImportRefusal(
              source,
              'its name becomes "$name", which $other already took — rename '
              'one of them in the design file',
            ),
          );
          continue;
        }
        var modes = <String, Object>{};
        var failed = false;
        for (var m in (collection['modes'] as List?) ?? const []) {
          var modeId = '${(m as Map)['modeId']}';
          var modeName = _modeName[modeId];
          if (modeName == null) continue;
          var value = _resolve(raw, modeId, kind, const {});
          if (value == null) {
            refusals.add(
              ImportRefusal(
                source,
                'its value in mode "${m['name']}" could not be read',
              ),
            );
            failed = true;
            break;
          }
          modes[modeName] = value;
        }
        if (failed) continue;
        var defaultMode = _modeName['${collection['defaultModeId']}'];
        var value = modes[defaultMode] ?? modes.values.firstOrNull;
        if (value == null) {
          refusals.add(ImportRefusal(source, 'it has a value in no mode'));
          continue;
        }
        taken[name] = source;
        tokens.add(
          ImportedToken(
            name: name,
            source: source,
            kind: kind,
            value: value,
            modes: modes,
          ),
        );
      }
    }
    return VariablesImport(tokens, refusals, _modeNames);
  }

  static SceneParamKind? _kind(String resolvedType) => switch (resolvedType) {
    'COLOR' => SceneParamKind.color,
    'FLOAT' => SceneParamKind.number,
    'STRING' => SceneParamKind.string,
    'BOOLEAN' => SceneParamKind.bool,
    _ => null,
  };

  /// The value of [variable] in [modeId], following aliases. An alias into
  /// another collection is read in that collection's same-named mode when
  /// it has one, else in its default mode — the design tool's own rule.
  Object? _resolve(
    Map variable,
    String modeId,
    SceneParamKind kind,
    Set<String> seen,
  ) {
    var values = (variable['valuesByMode'] as Map?) ?? const {};
    var raw = values[modeId];
    if (raw is Map && raw['type'] == 'VARIABLE_ALIAS') {
      var target = variables['${raw['id']}'];
      if (target is! Map || seen.contains('${raw['id']}')) return null;
      var collection = collections['${target['variableCollectionId']}'];
      if (collection is! Map) return null;
      var wanted = _modeName[modeId];
      var targetMode = '${collection['defaultModeId']}';
      for (var m in (collection['modes'] as List?) ?? const []) {
        var id = '${(m as Map)['modeId']}';
        if (_modeName[id] == wanted) targetMode = id;
      }
      return _resolve(target, targetMode, kind, {...seen, '${raw['id']}'});
    }
    return switch ((kind, raw)) {
      (SceneParamKind.color, Map c) => _color(c),
      (SceneParamKind.number, num n) => n.toDouble(),
      (SceneParamKind.string, String s) => s,
      (SceneParamKind.bool, bool b) => b,
      _ => null,
    };
  }

  static SceneColor? _color(Map c) {
    int channel(Object? v) => switch (v) {
      num n => (n.clamp(0, 1) * 255).round(),
      _ => -1,
    };
    var r = channel(c['r']), g = channel(c['g']), b = channel(c['b']);
    var a = c.containsKey('a') ? channel(c['a']) : 255;
    if (r < 0 || g < 0 || b < 0 || a < 0) return null;
    return SceneColor((a << 24) | (r << 16) | (g << 8) | b);
  }

  /// `Brand/Primary` → `brandPrimary`, `Spacing - 2x` → `spacing2x`; null
  /// when nothing usable is left, or the result is a Dart keyword.
  static String? _identifier(String raw) {
    var words = raw
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return null;
    var out = StringBuffer();
    for (var (i, w) in words.indexed) {
      if (i == 0) {
        out.write(w[0].toLowerCase() + w.substring(1));
      } else {
        out.write(w[0].toUpperCase() + w.substring(1));
      }
    }
    var name = '$out';
    if (!isValidNodeName(name) || _keywords.contains(name)) return null;
    return name;
  }

  static const _keywords = {
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'base',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'of',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'sealed',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'when',
    'while',
    'with',
    'yield',
  };
}

/// The line that marks a tokens file as the importer's, so the next import
/// may replace it without asking. A file without it is somebody's own.
const importedTokensMarker = '// @flutterware:tokens imported from';

/// Whether [source] is a tokens file this importer wrote.
bool isImportedTokensFile(String source) =>
    source.startsWith(importedTokensMarker);

/// `scene_tokens.dart` from an import: the marker, then one `Token<…>` per
/// variable with its modes, in the design file's order. What
/// [parseTokensFile] reads back, so the round trip is the test.
String emitImportedTokens(VariablesImport import, {required String from}) {
  var out = StringBuffer('''
$importedTokensMarker $from
//
// The design file's variables, as tokens. Each is `Token<T>('name', value,
// modes: {…})` — the value is the collection's default mode, `modes` names
// every mode. Every scene of the package may read them through its tokens
// formal: `fill: tokens.brandPrimary`.
//
// Written by an import, and replaced by the next one: a hand edit here is
// lost then. Refusals, if any, are listed at the end.
import 'package:flutterware/scene_authoring.dart';

final $sceneTokensSymbol = [
''');
  for (var t in import.tokens) {
    out.writeln('  // ${t.source}');
    var modes = t.modes.isEmpty
        ? ''
        : ', modes: {${[for (var e in t.modes.entries) "'${e.key}': ${_literal(e.value)}"].join(', ')}}';
    out.writeln(
      "  ${t.kind == SceneParamKind.color ? '' : 'const '}"
      "Token<${_type(t.kind)}>('${t.name}', ${_literal(t.value)}$modes),",
    );
  }
  out.writeln('];');
  if (import.refusals.isNotEmpty) {
    out
      ..writeln()
      ..writeln('// Not imported:');
    for (var r in import.refusals) {
      out.writeln('//   $r');
    }
  }
  return '$out';
}

String _type(SceneParamKind kind) => switch (kind) {
  SceneParamKind.color => 'SceneColor',
  SceneParamKind.number => 'double',
  SceneParamKind.string => 'String',
  SceneParamKind.bool => 'bool',
  SceneParamKind.list => 'List<Object?>',
};

String _literal(Object value) => switch (value) {
  SceneColor c =>
    'const SceneColor(0x${c.argb.toRadixString(16).toUpperCase().padLeft(8, '0')})',
  String s =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'",
  double d => d == d.roundToDouble() && d.abs() < 1e15 ? '${d.round()}' : '$d',
  var v => '$v',
};
