// A token library as a document: the editor's own, the way a scene file is.
//
// A library is a `*.tokens.dart` the editor writes — values it holds,
// draws and compares against — shared by every scene of every group that
// lists it. This is the object those scenes share: one per file, with its
// own journal (an edit to a token is undone here, never in a scene), its
// own dirty flag and save door, and the same disk discipline as a scene
// file: it re-parses what it emits before writing, writes nothing when the
// bytes are already there, and adopts a version that arrived on disk as one
// undoable step.
//
// Pure Dart: `fw`, a codemod and the panel edit a library through the same
// door.
import 'package:dart_style/dart_style.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:path/path.dart' as p;

import 'scene_file.dart';
import 'tokens_file.dart';
import 'workspace.dart';

/// The result of opening a library: the document, or why there is none.
class TokensLibraryOpen {
  TokensLibraryOpen._(this.library, this.refusals);

  final TokensLibrary? library;
  final List<SceneRefusal> refusals;

  bool get ok => library != null;
}

class TokensLibrary extends SceneListenable implements SceneSavable {
  TokensLibrary({
    required this.path,
    List<SceneTokenDecl> tokens = const [],
    List<String> modes = const [],
    String? source,
  }) : tokens = [...tokens],
       declaredModes = [...modes],
       _disk = source;

  /// Read a file through the parse door — its list symbol derived from its
  /// name, the way discovery derives it.
  static TokensLibraryOpen open(String path, String source) {
    var parsed = parseTokensFile(source, symbol: tokensSymbolFor(path));
    if (!parsed.ok) return TokensLibraryOpen._(null, parsed.refusals);
    return TokensLibraryOpen._(
      TokensLibrary(
        path: path,
        tokens: parsed.tokens,
        modes: parsed.modes,
        source: source,
      ),
      const [],
    );
  }

  /// The modes this library declares by name, in the file's order — a mode
  /// exists here before any token differs in it, which is how one is added
  /// from the panel.
  final List<String> declaredModes;

  /// Where it lives — the identity a workspace dedupes on.
  @override
  final String path;

  String get symbol => tokensSymbolFor(path);

  String get fileName => p.basename(path);

  /// The declarations, in the file's order. Mutated only through the doors
  /// below, so every change is journaled and announced.
  final List<SceneTokenDecl> tokens;

  String? _disk;

  /// Whether [source] is the text this library last read or wrote.
  @override
  bool matchesDisk(String source) => source == _disk;

  var _revision = 0;
  var _savedRevision = 0;

  /// Bumped by every edit — what an autosave arms on.
  int get revision => _revision;

  @override
  bool get isDirty => _revision != _savedRevision;

  // --- Queries -------------------------------------------------------------

  SceneTokenDecl? named(String name) {
    for (var t in tokens) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// Every mode this library knows — declared by name, or named by a
  /// token — sorted. The file written declares all of them.
  List<String> get modes =>
      {...declaredModes, for (var t in tokens) ...t.modes.keys}.toList()
        ..sort();

  /// Why [wanted] cannot be a token's name here, or null when it can.
  /// [taken] names what the group's other libraries and exports already
  /// use — a scene reads one `tokens.name`, whichever file declares it.
  String? nameProblem(
    String wanted, {
    String? renaming,
    Set<String> taken = const {},
  }) {
    if (!isValidNodeName(wanted)) {
      return '"$wanted" is not a valid name — a Dart identifier: letters, '
          'digits and underscores, not starting with a digit';
    }
    if (wanted == renaming) return null;
    if (named(wanted) != null) return '"$wanted" is already in $fileName';
    if (taken.contains(wanted)) {
      return '"$wanted" is already declared elsewhere in the group';
    }
    return null;
  }

  /// A free name off [base]: `brand`, `brand2`, `brand3`…
  String freeName(String base, {Set<String> taken = const {}}) {
    if (!isValidNodeName(base)) base = 'token';
    if (nameProblem(base, taken: taken) == null) return base;
    for (var i = 2; ; i++) {
      if (nameProblem('$base$i', taken: taken) == null) return '$base$i';
    }
  }

  // --- Journal -------------------------------------------------------------

  static const _journalCap = 100;
  final _undo = <(String, List<SceneTokenDecl>, List<String>)>[];
  final _redo = <(String, List<SceneTokenDecl>, List<String>)>[];
  String? _openMerge;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.$1;

  /// One journaled edit. A [mergeKey] folds a run of edits — a drag, a
  /// keystroke sequence — into one entry, until [endMerge].
  void perform(String label, void Function() mutate, {String? mergeKey}) {
    var merge =
        mergeKey != null &&
        _redo.isEmpty &&
        _undo.isNotEmpty &&
        _openMerge == mergeKey;
    _openMerge = mergeKey;
    if (!merge) {
      _undo.add((label, List.of(tokens), List.of(declaredModes)));
      if (_undo.length > _journalCap) _undo.removeAt(0);
      _redo.clear();
    }
    mutate();
    _revision++;
    notifyListeners();
  }

  void endMerge() => _openMerge = null;

  void undo() {
    if (_undo.isEmpty) return;
    var (label, before, modes) = _undo.removeLast();
    _redo.add((label, List.of(tokens), List.of(declaredModes)));
    tokens
      ..clear()
      ..addAll(before);
    declaredModes
      ..clear()
      ..addAll(modes);
    _openMerge = null;
    _revision++;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    var (label, after, modes) = _redo.removeLast();
    _undo.add((label, List.of(tokens), List.of(declaredModes)));
    tokens
      ..clear()
      ..addAll(after);
    declaredModes
      ..clear()
      ..addAll(modes);
    _revision++;
    notifyListeners();
  }

  // --- Modes ---------------------------------------------------------------

  /// Declares a mode. Nothing differs in it yet: every token shows its
  /// default there until one is set.
  void addMode(String name) {
    name = name.trim();
    if (!isValidNodeName(name) || name == 'default') {
      throw ArgumentError('"$name" is not a mode name — an identifier');
    }
    if (modes.contains(name)) throw ArgumentError('there is a "$name" mode');
    perform('Add mode $name', () => declaredModes.add(name));
  }

  /// Renames a mode; every token's value in it follows.
  void renameMode(String name, String wanted) {
    wanted = wanted.trim();
    if (wanted == name) return;
    if (!modes.contains(name)) throw ArgumentError('no mode "$name"');
    if (!isValidNodeName(wanted) || wanted == 'default') {
      throw ArgumentError('"$wanted" is not a mode name — an identifier');
    }
    if (modes.contains(wanted)) {
      throw ArgumentError('there is a "$wanted" mode');
    }
    perform('Rename mode $name', () {
      var i = declaredModes.indexOf(name);
      if (i >= 0) {
        declaredModes[i] = wanted;
      } else {
        declaredModes.add(wanted);
      }
      for (var (j, t) in tokens.indexed) {
        if (!t.modes.containsKey(name)) continue;
        tokens[j] = _withModes(t, {
          for (var e in t.modes.entries)
            if (e.key == name) wanted: e.value else e.key: e.value,
        });
      }
    });
  }

  /// Deletes a mode; every value a token held in it goes with it.
  void deleteMode(String name) {
    if (!modes.contains(name)) throw ArgumentError('no mode "$name"');
    perform('Delete mode $name', () {
      declaredModes.remove(name);
      for (var (j, t) in tokens.indexed) {
        if (!t.modes.containsKey(name)) continue;
        tokens[j] = _withModes(t, {
          for (var e in t.modes.entries)
            if (e.key != name) e.key: e.value,
        });
      }
    });
  }

  /// How many tokens differ in [mode].
  int differingIn(String mode) =>
      tokens.where((t) => t.modes.containsKey(mode)).length;

  static SceneTokenDecl _withModes(SceneTokenDecl t, Map<String, Object> m) =>
      t.style != null
      ? SceneTokenDecl.style(t.name, t.style!, modes: m)
      : SceneTokenDecl(t.name, t.kind!, t.value!, modes: m);

  // --- Doors ---------------------------------------------------------------

  /// Declares a value token. With no [value] the kind's zero.
  void add(
    String name,
    SceneParamKind kind, {
    Object? value,
    Set<String> taken = const {},
  }) {
    if (kind == SceneParamKind.list) {
      throw ArgumentError('a token is not a list');
    }
    if (nameProblem(name, taken: taken) case var problem?) {
      throw ArgumentError(problem);
    }
    var v = value ?? _zeroOf(kind);
    if (!_holds(kind, v)) {
      throw ArgumentError('a ${kind.name} token does not hold a $v');
    }
    perform('Add token $name', () {
      tokens.add(SceneTokenDecl(name, kind, v));
    });
  }

  /// Declares a text style — the text subset of the table, shared whole.
  void addStyle(
    String name, {
    SceneTextStyle style = const SceneTextStyle(fontSize: 16),
    Set<String> taken = const {},
  }) {
    if (nameProblem(name, taken: taken) case var problem?) {
      throw ArgumentError(problem);
    }
    perform('Add style $name', () {
      tokens.add(SceneTokenDecl.style(name, style));
    });
  }

  /// Renames a token. The scenes reading it are the caller's to follow —
  /// a library does not know its readers.
  void rename(String name, String wanted, {Set<String> taken = const {}}) {
    wanted = wanted.trim();
    if (wanted == name) return;
    var i = tokens.indexWhere((t) => t.name == name);
    if (i < 0) throw ArgumentError('no token "$name"');
    if (nameProblem(wanted, renaming: name, taken: taken) case var problem?) {
      throw ArgumentError(problem);
    }
    perform('Rename token $name', () {
      tokens[i] = _renamed(tokens[i], wanted);
    });
  }

  /// Sets a value token's value — the default, or in [mode]. A mode value
  /// equal to the default is the default: the mode entry goes.
  void setValue(String name, Object value, {String? mode, String? mergeKey}) {
    var i = tokens.indexWhere((t) => t.name == name);
    if (i < 0) throw ArgumentError('no token "$name"');
    var t = tokens[i];
    var kind = t.kind;
    if (kind == null || !t.hasValue) {
      throw ArgumentError('"$name" holds no value to set');
    }
    if (!_holds(kind, value)) {
      throw ArgumentError('"$name" is a ${t.typeName} — a $value is not one');
    }
    perform('Edit token $name', mergeKey: mergeKey, () {
      if (mode == null) {
        tokens[i] = SceneTokenDecl(
          name,
          kind,
          value,
          modes: {
            for (var e in t.modes.entries)
              if (e.value != value) e.key: e.value,
          },
        );
      } else {
        tokens[i] = SceneTokenDecl(
          name,
          kind,
          t.value!,
          modes: {
            for (var e in t.modes.entries)
              if (e.key != mode) e.key: e.value,
            if (value != t.value) mode: value,
          },
        );
      }
    });
  }

  /// Replaces a style token's fields — the default's, or [mode]'s. A mode
  /// style equal to the default is the default: the mode entry goes.
  void setStyle(
    String name,
    SceneTextStyle style, {
    String? mode,
    String? mergeKey,
  }) {
    var i = tokens.indexWhere((t) => t.name == name);
    if (i < 0) throw ArgumentError('no token "$name"');
    var t = tokens[i];
    if (!t.isStyle || !t.hasValue) {
      throw ArgumentError('"$name" is not a style');
    }
    perform('Edit style $name', mergeKey: mergeKey, () {
      if (mode == null) {
        tokens[i] = SceneTokenDecl.style(
          name,
          style,
          modes: {
            for (var e in t.modes.entries)
              if (e.value != style) e.key: e.value,
          },
        );
      } else {
        tokens[i] = SceneTokenDecl.style(
          name,
          t.style!,
          modes: {
            for (var e in t.modes.entries)
              if (e.key != mode) e.key: e.value,
            if (style != t.style) mode: style,
          },
        );
      }
    });
  }

  /// Deletes a token. Whether anything reads it is the caller's to check —
  /// across every scene of every group that lists this file.
  void delete(String name) {
    var i = tokens.indexWhere((t) => t.name == name);
    if (i < 0) throw ArgumentError('no token "$name"');
    perform('Delete token $name', () => tokens.removeAt(i));
  }

  // --- File ----------------------------------------------------------------

  String emit() => emitTokensLibrary(tokens, symbol: symbol, modes: modes);

  /// Emit, refuse to write anything the parser would reject, and hand the
  /// text to [write]. Returns the refusals — empty on success.
  @override
  List<SceneRefusal> save(void Function(String path, String source) write) {
    var source = emit();
    var check = parseTokensFile(source, symbol: symbol);
    if (!check.ok) return check.refusals;
    if (source != _disk) {
      write(path, source);
      _disk = source;
    }
    _savedRevision = _revision;
    return const [];
  }

  /// Takes the version [source] on disk, as one undoable step.
  List<SceneRefusal> adopt(String source) {
    var parsed = parseTokensFile(source, symbol: symbol);
    if (!parsed.ok) return parsed.refusals;
    perform('Reload from disk', () {
      tokens
        ..clear()
        ..addAll(parsed.tokens);
      declaredModes
        ..clear()
        ..addAll(parsed.modes);
    });
    _disk = source;
    _savedRevision = _revision;
    return const [];
  }

  static SceneTokenDecl _renamed(SceneTokenDecl t, String name) =>
      t.style != null
      ? SceneTokenDecl.style(name, t.style!, modes: t.modes)
      : SceneTokenDecl(name, t.kind!, t.value!, modes: t.modes);

  static Object _zeroOf(SceneParamKind kind) => switch (kind) {
    SceneParamKind.string => '',
    SceneParamKind.number => 0.0,
    SceneParamKind.color => const SceneColor(0xFF000000),
    SceneParamKind.bool => false,
    SceneParamKind.list => const <Object?>[],
  };

  static bool _holds(SceneParamKind kind, Object value) => switch (kind) {
    SceneParamKind.string => value is String,
    SceneParamKind.number => value is double,
    SceneParamKind.color => value is SceneColor,
    SceneParamKind.bool => value is bool,
    SceneParamKind.list => value is List,
  };
}

/// The header every library file carries: the marker, then what the file
/// is — for the reader who opens it in an IDE rather than in the editor.
const tokensLibraryHeader =
    '''
$sceneTokensFileMarker
// Owned by the flutterware scene editor, which reads and writes this whole
// file. A token is `Token<T>('name', value, modes: {…})`; every scene of a
// group that lists this library reads it as `tokens.name`. Hand edits are
// welcome inside the grammar; anything outside it is refused with a line
// number rather than silently dropped.
''';

/// A library's whole text: the header, the authoring import, and one
/// `Token<…>` per declaration under [symbol]. What [parseTokensFile] reads
/// back, so the round trip is the test.
String emitTokensLibrary(
  List<SceneTokenDecl> tokens, {
  required String symbol,
  List<String> modes = const [],
}) {
  var out = StringBuffer(tokensLibraryHeader)
    ..writeln("import 'package:flutterware/scene_authoring.dart';")
    ..writeln();
  if (modes.isNotEmpty) {
    out
      ..writeln(
        'const ${modesSymbolFor(symbol)} = [${modes.map((m) => "'$m'").join(', ')}];',
      )
      ..writeln();
  }
  if (tokens.isEmpty) {
    out.writeln('final $symbol = <Token<Object>>[];');
  } else {
    out.writeln('final $symbol = [');
    for (var t in tokens) {
      out.writeln('  ${_tokenLiteral(t)},');
    }
    out.writeln('];');
  }
  return _formatter.format(out.toString());
}

String _tokenLiteral(SceneTokenDecl t) {
  if (t.style case var style?) {
    var modes = t.modes.isEmpty
        ? ''
        : ', modes: {${[for (var e in t.modes.entries) "'${e.key}': ${_styleLiteral(e.value as SceneTextStyle)}"].join(', ')}}';
    return "const Token<SceneTextStyle>('${t.name}', ${_styleLiteral(style)}$modes)";
  }
  var modes = t.modes.isEmpty
      ? ''
      : ', modes: {${[for (var e in t.modes.entries) "'${e.key}': ${_valueLiteral(e.value)}"].join(', ')}}';
  return "const Token<${t.typeName}>('${t.name}', ${_valueLiteral(t.value!)}$modes)";
}

String _styleLiteral(SceneTextStyle s) {
  var fields = [
    if (s.fontSize case var v?) 'fontSize: ${_valueLiteral(v)}',
    if (s.weight case var v?) 'weight: SceneFontWeight.w${v.value}',
    if (s.color case var v?) 'color: ${_valueLiteral(v)}',
    if (s.align case var v?) 'align: SceneTextAlign.${v.name}',
    if (s.maxLines case var v?) 'maxLines: $v',
  ];
  return 'SceneTextStyle(${fields.join(', ')})';
}

String _valueLiteral(Object value) => switch (value) {
  SceneColor c =>
    'SceneColor(0x${c.argb.toRadixString(16).toUpperCase().padLeft(8, '0')})',
  String s =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'",
  double d => d == d.roundToDouble() && d.abs() < 1e15 ? '${d.round()}' : '$d',
  var v => '$v',
};

final _formatter = DartFormatter(
  languageVersion: DartFormatter.latestLanguageVersion,
);
