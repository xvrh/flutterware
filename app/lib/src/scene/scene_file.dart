// Disposable spike: the scene file grammar, its parser and its emitter — the
// tier-2 round-trip bet measured on the touched model instead of a predicted
// one.
//
// THE GRAMMAR, on a page. A scene file is:
//   - a `//@flutterware:scene=…` marker in its first line
//   - the authoring import, which every scene file has, and ANY OTHER
//     IMPORT the file needs — preserved verbatim and written back, because
//     the tool owns this file and a dropped import is the shredder this
//     grammar exists to prevent. Prefixes are the author's (`as app`).
//     Nothing else at file level: no part, no export, no library
//   - one SCENE class, and after it any number of MOTION classes that
//     animate it (`class X(super.scene) extends SceneMotion<Scene>`) — the
//     pair is one file, one marker, one round trip. The motion grammar is
//     in motion_file.dart. Its parameters — typed holes whose
//     default is the mockup — are the class's PRIMARY CONSTRUCTOR: each is
//     `final <String|double|Color> <name> = <literal>` in the class header,
//     which is one spelling for the formal, the field and the default at
//     once, and puts the name in scope for every node below
//   - the class members are node fields: `late final <name> = <Node>(…);`
//     — THE FIELD NAME IS THE NODE'S IDENTITY (unique by Dart's own rules,
//     shared namespace with the parameters), and one field must be `root`,
//     a Frame
//   - a node is a constructor invocation: Frame, Text, Shape, Ext or Scene,
//     with named arguments from that node's fixed vocabulary; Text takes its
//     content as one positional string, Ext takes its registration entry as
//     one positional identifier, Scene takes another scene file's class
//     name the same way (its `args:` override that scene's parameters)
//   - an ExternalNode additionally takes `build:`, a closure returning the
//     app's widget — `build: (a) => app.DrinkBadge(a.number('size'))`. THE
//     TOOL DOES NOT READ IT: it keeps the span exactly as written and puts
//     it back, because it cannot author app code and must not lose it
//     either. The arg names inside are the grammar's stringly boundary
//   - `children: [ … ]` lists nodes BY FIELD NAME — every node is declared
//     as its own field and placed exactly once (forward references are fine;
//     `late` is what makes sibling references legal Dart)
//   - values are: int/double literals (optionally negated), single string
//     literals with no interpolation, bool literals, `Color(0x…)`,
//     allowlisted enum references, `args: {'k': literal}` maps, and — where
//     the types agree — A PARAMETER'S NAME, which binds the property to the
//     typed hole
//   - a parameter may also be a LIST of records — `final List<({String
//     item, String qty})> lines = const [(item: '…', qty: '12')]`. A frame
//     drawn once per item is `FrameNode.repeating(over: lines, row: (line)
//     => [ … ])`, and inside that closure — THE GRAMMAR'S ONE PLACE WHERE
//     NODES ARE WRITTEN INLINE — a cell reads a field as `line.item`. The
//     cells of a repeated row are not fields, so they have no names and
//     cannot be selected: which cell of which row would it be
//   - a Frame with `layout: NodeLayout.table` takes `columns: [ … ]` — one
//     size per column, in the same `null`/number/`double.infinity`
//     vocabulary a node's size uses — and `cellPadding`. Its children are
//     rows and their children are cells
//   - nothing else: no comments inside the class body, no loops, no
//     conditionals, no method calls, no arithmetic, no identifiers off the
//     allowlist, no inline nodes in children, no class that is neither the
//     scene nor a motion, no orphan fields (an
//     undeclared drop on the next save is the shredder this grammar exists
//     to prevent). Refused with a line number, never dropped.
//
// Invariants the tests hold:
//   - parse(emit(model)) succeeds and re-emits identically (model identity)
//   - emit ∘ parse is the identity on canonical files
//   - accepted non-canonical spellings (`final` for `late final`, forward
//     references, `1024.0`, lowercase hex, a quoted Ext entry, a
//     `final`-less or type-less header formal) converge to canonical in
//     one emit
//   - every hostile construct is refused with an offset and a name, and
//     nothing ever throws.
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dart_style/dart_style.dart';
import 'package:flutterware/scene_authoring.dart';

import 'motion_file.dart';

const sceneFileMarker = '//@flutterware:scene=0.8';

/// The one library a scene file imports. Its vocabulary IS the model's own
/// class names — `FrameNode`, `TextNode`, `SceneColor` — because a spelling
/// that differs from the type is a spelling the compiler cannot check.
const sceneAuthoringUri = 'package:flutterware/scene_authoring.dart';
const sceneAuthoringImport = "import '$sceneAuthoringUri';";

/// The generated arguments file, which lives beside the scenes it serves.
/// One name, so a scene file's import of it never has to be worked out.
const sceneArgsFileName = 'scene_args.dart';

/// One refused construct: where it is and what to do instead.
class SceneRefusal {
  SceneRefusal(this.offset, this.line, this.construct, this.message);

  final int offset;
  final int line;

  /// A short name for what was found — `for element`, `interpolation`,
  /// `unknown property` — stable enough to test against.
  final String construct;

  final String message;

  @override
  String toString() => 'line $line: $construct — $message';
}

/// What a parse produced: a document, or the complete list of reasons there
/// is none. All-or-nothing by design — a partially loaded scene is the lie
/// the editor must never tell — but the refusals are *collected*, so one
/// hostile edit does not hide the next.
class SceneParse {
  SceneParse(
    this.doc,
    this.className,
    this.refusals, [
    this.motions = const {},
    this.imports = const [],
  ]);

  final SceneDocument? doc;
  final String? className;
  final List<SceneRefusal> refusals;

  /// Every import but the authoring one, verbatim and in the order they
  /// should be written back. The tool cannot invent these — an Ext names an
  /// app widget, and only the author knows where it lives — so it keeps
  /// them instead.
  final List<String> imports;

  /// The motion classes declared beside the scene, by class name, in file
  /// order — a scene may carry several (an intro, an outro) or none.
  final Map<String, MotionDocument> motions;

  bool get ok => doc != null;
}

// ---------------------------------------------------------------------------
// Emit
// ---------------------------------------------------------------------------

final _formatter = DartFormatter(
  languageVersion: DartFormatter.latestLanguageVersion,
);

String emitSceneFile(
  SceneDocument doc, {
  String className = 'SceneFile',
  Map<String, MotionDocument> motions = const {},
  List<String> imports = const [],
}) {
  if (doc.root.name != 'root') {
    throw ArgumentError(
      'the root node is the `root` field, so its name '
      'must be "root" — got "${doc.root.name}"',
    );
  }
  var out = StringBuffer('''
$sceneFileMarker
// Owned by the flutterware scene editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar: every node is a
// `late final` field (the field name is the node's identity), placed exactly
// once in a children list; a parameter is a `final` in the class header
// whose default is the mockup. Anything outside the grammar is refused with
// a line number rather than silently dropped.
//
// This is ordinary Dart: it compiles, it analyzes, and an app mounts it.
$sceneAuthoringImport
${_imports(imports, needsArgs: _placesSomething(doc))}
''');
  var seen = <String>{};
  var params = <String, SceneParamDecl>{};
  for (var p in doc.params) {
    if (!isValidNodeName(p.name) || !seen.add(p.name)) {
      throw ArgumentError('"${p.name}" is not a usable parameter name');
    }
    params[p.name] = p;
  }
  if (doc.params.isEmpty) {
    out.writeln('class $className extends SceneDefinition {');
  } else {
    // The primary constructor: formal, field and default in one spelling,
    // in scope for every node initializer below.
    out.write('class $className({');
    for (var p in doc.params) {
      out.write('final ${p.typeName} ${p.name} = ${_paramDefault(p)}, ');
    }
    out.writeln('}) extends SceneDefinition {');
  }
  void field(SceneNode n) {
    // A repeated row's cells are written inside its closure, not beside it:
    // they are not fields, so the walk stops here.
    var repeated = n is FrameNode && (n.repeated?.source.isNotEmpty ?? false);
    if (!repeated) {
      for (var c in n.children) {
        field(c);
      }
    }
    if (!isValidNodeName(n.name) || !seen.add(n.name)) {
      throw ArgumentError(
        '"${n.name}" is not a usable node name — names are '
        'field names: valid Dart identifiers, unique in the scene',
      );
    }
    // `root` implements SceneDefinition's abstract getter, so it is an
    // override like any other member that does.
    if (n.name == 'root') out.writeln('  @override');
    out.write('  late final ${n.name} = ');
    _emitNode(out, n, params);
    out.writeln(';');
  }

  field(doc.root);
  out.writeln('}');
  // The motions of the pair live in the same file, after the scene they
  // animate — one document, one marker, one round trip (grammar 0.5).
  for (var entry in motions.entries) {
    out.writeln();
    emitMotionClass(out, entry.value, doc, className: entry.key);
  }
  return _formatter.format(out.toString());
}

/// Whether the scene places anything whose arguments are generated — an
/// external widget or a nested scene. Both spell a `…Args` class, and both
/// therefore need the generated vocabulary in scope.
bool _placesSomething(SceneDocument doc) {
  for (var (node, _) in doc.walk()) {
    if (node is ExternalNode || node is SceneRefNode) return true;
  }
  return false;
}

/// The file's other imports, canonically: package ones first, each group
/// sorted, so the order a hand edit put them in converges in one emit.
///
/// The tool cannot invent an import — only the author knows where a widget
/// lives — with one exception: the generated arguments file, whose name is
/// fixed and whose absence would make a scene that places anything stop
/// compiling the moment the editor added the node.
String _imports(List<String> imports, {bool needsArgs = false}) {
  var all = [
    ...imports,
    if (needsArgs && !imports.any((i) => i.contains("'$sceneArgsFileName'")))
      "import '$sceneArgsFileName';",
  ];
  if (all.isEmpty) return '';
  imports = all;
  var packages = [
    for (var i in imports)
      if (i.contains("'package:")) i,
  ]..sort();
  var relative = [
    for (var i in imports)
      if (!i.contains("'package:")) i,
  ]..sort();
  return '${[...packages, ...relative].join('\n')}\n';
}

String _paramDefault(SceneParamDecl p) => switch (p.kind) {
  SceneParamKind.string => _str(p.defaultValue as String),
  SceneParamKind.number => _num(p.defaultValue as double),
  SceneParamKind.color => 'const ${_color(p.defaultValue as SceneColor)}',
  SceneParamKind.bool => '${p.defaultValue}',
  SceneParamKind.list => 'const [${p.items.map(_item).join(', ')}]',
};

/// One item, as a record literal — the shape that gives `line.item` a type.
String _item(SceneItem item) =>
    '(${[for (var e in item.entries) '${e.key}: ${_argValue(e.value)}'].join(', ')})';

void _emitNode(
  StringBuffer out,
  SceneNode n,
  Map<String, SceneParamDecl> ps, {
  String? list,
  bool inline = false,
}) {
  var props = <String>[];
  var scopeList = list;

  /// A bound property is spelled as its reference, always: the binding is
  /// the stronger of the two, and an edit reached the parameter's default
  /// before this ran ([reconcileBindings]), so the reference IS the value.
  /// The only reason to write a literal instead is a binding with nothing
  /// behind it — a parameter not declared, an item reference outside the
  /// closure that gives it a name — and [reconcileBindings] removes those
  /// too, so here it is a guard, not a rule.
  String? ref(String key) {
    switch (n.bindings[key]) {
      case null:
        return null;
      case ParamRef(:var name):
        var p = ps[name];
        return p == null || p.kind == SceneParamKind.list ? null : name;
      case ItemRef(:var list, :var field):
        // Spelled with the closure's own parameter rather than the list's
        // name, and only inside the closure.
        if (scopeList != list) return null;
        var decl = ps[list];
        if (decl == null || decl.kind != SceneParamKind.list) return null;
        var items = decl.items;
        if (items.isEmpty || !items.first.containsKey(field)) return null;
        return '$_rowParam.$field';
    }
  }

  void add(String key, Object? current, String Function() spell) {
    props.add('$key: ${ref(key) ?? spell()}');
  }

  void common() {
    if (n.x != 0 || n.bindings.containsKey('x')) {
      add('x', n.x, () => _num(n.x));
    }
    if (n.y != 0 || n.bindings.containsKey('y')) {
      add('y', n.y, () => _num(n.y));
    }
    if (n.width case var w?) add('width', w, () => _size(w));
    if (n.height case var h?) add('height', h, () => _size(h));
    if (n.fill case var f?) add('fill', f, () => _color(f));
    if (n.borderColor case var b?) {
      add('borderColor', b, () => _color(b));
      if (n.borderWidth != 1) {
        add('borderWidth', n.borderWidth, () => _num(n.borderWidth));
      }
    }
    if (n.corner != 0) {
      add('corner', n.corner, () => _num(n.corner));
    }
    if (n.opacity != 1) add('opacity', n.opacity, () => _num(n.opacity));
    if (!n.visible || n.bindings.containsKey('visible')) {
      add('visible', n.visible, () => '${n.visible}');
    }
  }

  switch (n) {
    case FrameNode f:
      common();
      if (f.layout != NodeLayout.absolute) {
        props.add('layout: NodeLayout.${f.layout.name}');
      }
      if (f.gap != 8) add('gap', f.gap, () => _num(f.gap));
      // One number while one number says it, four names when it does not.
      // A frame that only ever wanted `padding: 16` keeps writing that.
      if (!f.padding.isZero) {
        if (f.padding.isUniform) {
          add('padding', f.padding.left, () => _num(f.padding.left));
        } else {
          for (var (name, value) in [
            ('paddingLeft', f.padding.left),
            ('paddingTop', f.padding.top),
            ('paddingRight', f.padding.right),
            ('paddingBottom', f.padding.bottom),
          ]) {
            if (value != 0) props.add('$name: ${_num(value)}');
          }
        }
      }
      if (f.columns.isNotEmpty) {
        props.add('columns: [${f.columns.map(_track).join(', ')}]');
      }
      if (!f.cellPadding.isZero) {
        if (f.cellPadding.isUniform) {
          props.add('cellPadding: ${_num(f.cellPadding.left)}');
        } else {
          for (var (name, value) in [
            ('cellPaddingLeft', f.cellPadding.left),
            ('cellPaddingTop', f.cellPadding.top),
            ('cellPaddingRight', f.cellPadding.right),
            ('cellPaddingBottom', f.cellPadding.bottom),
          ]) {
            if (value != 0) props.add('$name: ${_num(value)}');
          }
        }
      }
      if (f.mainAlign != SceneMainAxisAlignment.start) {
        props.add('mainAlign: SceneMainAxisAlignment.${f.mainAlign.name}');
      }
      if (f.crossAlign != SceneCrossAxisAlignment.center) {
        props.add('crossAlign: SceneCrossAxisAlignment.${f.crossAlign.name}');
      }
      // A repeat writes its cells INLINE, inside the closure that binds
      // them — they are not fields, because there is no one row for them to
      // belong to.
      if (f.repeated?.source case var list? when list.isNotEmpty) {
        var cells = [for (var c in f.children) _emitCell(c, ps, list)];
        out.write(
          'FrameNode.repeating(over: $list, '
          'row: ($_rowParam) => [${cells.join(', ')}], '
          '${props.join(', ')})',
        );
        return;
      }
      if (f.children.isNotEmpty) {
        props.add(
          inline
              ? 'children: [${[for (var c in f.children) _emitCell(c, ps, list!)].join(', ')}]'
              : 'children: [${f.children.map((c) => c.name).join(', ')}]',
        );
      }
      out.write('FrameNode(${props.join(', ')})');
    case TextNode t:
      props.add(ref('text') ?? _str(t.text));
      common();
      if (t.fontSize != 16) add('fontSize', t.fontSize, () => _num(t.fontSize));
      if (t.weight != SceneFontWeight.w400) {
        props.add('weight: SceneFontWeight.w${t.weight.value}');
      }
      if (t.color != const SceneColor(0xFF1A1A1A)) {
        add('color', t.color, () => _color(t.color));
      }
      if (t.align != SceneTextAlign.left) {
        props.add('align: SceneTextAlign.${t.align.name}');
      }
      if (t.maxLines case var lines?) {
        add('maxLines', lines.toDouble(), () => '$lines');
      }
      out.write('TextNode(${props.join(', ')})');
    case ShapeNode s:
      common();
      if (s.circle) props.add('circle: true');
      out.write('ShapeNode(${props.join(', ')})');
    case ExternalNode e:
      props.add(_argsLiteral(e.entry, e.args, 'a registration entry name'));
      common();
      out.write('ExternalNode(${props.join(', ')})');
    case SceneRefNode r:
      props.add(_argsLiteral(r.sceneClassName, r.args, 'a scene class name'));
      common();
      out.write('SceneRefNode(${props.join(', ')})');
  }
}

/// `const DrinkBadgeArgs(size: 140)` — the whole of an external node's
/// identity and arguments, and the reason a scene file spells no strings.
///
/// The class is generated from the app's declaration of that widget (or,
/// for a nested scene, from the child's own parameter list), so a name that
/// is not a declared argument does not compile. Every argument the node
/// carries is written; what a caller left at the declared default was never
/// read into the node in the first place.
String _argsLiteral(String entry, Map<String, Object?> args, String what) {
  if (!isValidNodeName(entry)) {
    throw ArgumentError('"$entry" is not $what');
  }
  for (var name in args.keys) {
    if (!isValidNodeName(name)) {
      throw ArgumentError('"$name" is not an argument name');
    }
  }
  var named = [for (var e in args.entries) '${e.key}: ${_argValue(e.value)}']
      .join(', ');
  return 'const ${entry}Args($named)';
}

/// What the closure's parameter is called. One name, because the cells it
/// binds are unnamed too and a second convention would only be a second
/// thing to remember.
const _rowParam = 'line';

/// One cell of a repeated row, written inline. Its own children are written
/// inline too — the whole subtree is anonymous.
String _emitCell(SceneNode cell, Map<String, SceneParamDecl> ps, String list) {
  var out = StringBuffer();
  _emitNode(out, cell, ps, list: list, inline: true);
  return '$out';
}

/// Canonical number spelling: an integral double is an int literal, anything
/// else is Dart's own round-trippable `toString`. One spelling per value is
/// what makes emit ∘ parse an identity.
String _num(double v) =>
    v == v.roundToDouble() && v.abs() < 1e15 ? '${v.round()}' : '$v';

/// A size, which is a number or the word for "as much as the parent gives".
/// Spelled the way Flutter spells it, because that is what it means.
String _size(double v) => v.isInfinite ? 'double.infinity' : _num(v);

/// A column track: a size, or the word for "as wide as the widest cell".
String _track(double? v) => v == null ? 'null' : _size(v);

String _color(SceneColor c) =>
    'SceneColor(0x${c.argb.toRadixString(16).padLeft(8, '0').toUpperCase()})';

String _str(String s) {
  var out = StringBuffer("'");
  for (var rune in s.runes) {
    switch (rune) {
      case 0x5C:
        out.write(r'\\');
      case 0x27:
        out.write(r"\'");
      case 0x24:
        out.write(r'\$');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        out.writeCharCode(rune);
    }
  }
  out.write("'");
  return '$out';
}

String _argValue(Object? v) => switch (v) {
  num n => n is double ? _num(n) : '$n',
  String s => _str(s),
  bool b => '$b',
  // A colour argument is what a nested scene's colour parameter takes.
  SceneColor c => _color(c),
  _ => _str('$v'),
};

// ---------------------------------------------------------------------------
// Parse
// ---------------------------------------------------------------------------

SceneParse parseSceneFile(
  String source, {
  Map<String, Set<String>> declaredArgs = const {},
}) {
  var p = _Parser(source, declaredArgs);
  var doc = p.parse();
  var motions = <String, MotionDocument>{};
  // A motion is half a pair and resolves its targets against the scene, so
  // the motions of the file are read only once the scene is in hand.
  if (doc != null && p.refusals.isEmpty) {
    for (var decl in p.motionClasses) {
      var parsed = parseMotionClass(
        decl,
        source,
        scene: doc,
        sceneClassName: p.className!,
      );
      p.refusals.addAll(parsed.refusals);
      if (parsed.doc case var motion?) motions[parsed.className!] = motion;
    }
  }
  return SceneParse(
    p.refusals.isEmpty ? doc : null,
    p.className,
    p.refusals,
    motions,
    p.imports,
  );
}

class _Parser {
  _Parser(this.source, this.declaredArgs);

  final String source;

  /// Entry label to the argument names that widget declares — the app's
  /// declaration file, read before any scene file. An entry that is absent
  /// is not checked: a package with no declarations still parses, it just
  /// gets no second grader.
  final Map<String, Set<String>> declaredArgs;
  final refusals = <SceneRefusal>[];
  String? className;

  /// Classes carrying `extends SceneMotion<…>` — parsed after the scene.
  final motionClasses = <ClassDeclaration>[];

  /// Imports other than the authoring one, verbatim.
  final imports = <String>[];

  late final _lines = source.split('\n');

  /// Declared parameters, filled from the class header before any field is
  /// parsed.
  final _params = <String, SceneParamDecl>{};

  /// While a `row:` closure is being read: the closure's parameter name and
  /// the list it draws from. This is the ONLY place an item reference is
  /// legal, which is why it is a scope rather than a check afterwards.
  ({String param, String list})? _itemScope;

  /// Names for the cells of a repeated row. They are not fields — the file
  /// writes them inline — so they get a derived name the editor can key its
  /// tree and its rects on, and the emitter never writes it.
  var _cellSeq = 0;

  void refuse(int offset, String construct, String message) {
    var line = 1;
    var seen = 0;
    for (var l in _lines) {
      if (offset <= seen + l.length) break;
      seen += l.length + 1;
      line++;
    }
    refusals.add(SceneRefusal(offset, line, construct, message));
  }

  SceneDocument? parse() {
    if (!_lines.first.contains('@flutterware:scene')) {
      refuse(
        0,
        'missing marker',
        'a scene file starts with "$sceneFileMarker"',
      );
    }
    var result = parseString(content: source, throwIfDiagnostics: false);
    for (var error in result.errors) {
      refuse(error.offset, 'syntax error', error.message);
    }
    if (refusals.isNotEmpty && result.errors.isNotEmpty) return null;
    _readDirectives(result.unit, source);

    ClassDeclaration? found;
    for (var decl in result.unit.declarations) {
      if (decl is ClassDeclaration) {
        // The pair shares one file: the scene class, and the motion classes
        // that animate it — told apart by the extends clause they must have.
        if (decl.extendsClause?.superclass.name.lexeme == 'SceneMotion') {
          motionClasses.add(decl);
        } else if (found != null) {
          // The file holds the pair: the scene, and the motions animating
          // it. A second class with no extends clause is a motion missing
          // the one thing that makes it one.
          refuse(
            decl.offset,
            'extends',
            'a scene file holds one scene class and its motions — a motion '
                'is `class ${decl.namePart.typeName.lexeme}(super.scene) '
                'extends SceneMotion<${found.namePart.typeName.lexeme}>`',
          );
        } else {
          found = decl;
        }
      } else {
        refuse(
          decl.offset,
          'declaration',
          'only the scene class and its motions may be declared here',
        );
      }
    }
    if (found == null) {
      refuse(0, 'no class', 'a scene file holds exactly one scene class');
      return null;
    }
    className = found.namePart.typeName.lexeme;
    _refuseComments(found);

    // Phase 0: the class header's primary constructor, if any, declares
    // the parameters — read before any field, so every node initializer
    // may reference them.
    var declared = <String, int>{};
    if (found.namePart case PrimaryConstructorDeclaration pc) {
      _readParams(pc, declared);
    }

    // Phase 1: every member is a node field. The field name is the node's
    // identity; children lists are collected as references and linked
    // after every declaration is known, which is what makes forward
    // references (ordinary under `late final`) free.
    var nodes = <String, SceneNode>{};
    var childRefs = <String, List<(String, int)>>{};
    for (var member in found.body.members) {
      if (member is ConstructorDeclaration) {
        refuse(
          member.offset,
          'constructor',
          'parameters live in the class header — '
              "`class ${className!}({final String title = '…'})`",
        );
        continue;
      }
      if (member is! FieldDeclaration || member.fields.variables.length != 1) {
        refuse(
          member.offset,
          'member',
          'the scene class holds only node fields — '
              '`late final <name> = <Node>(…);`',
        );
        continue;
      }
      var variable = member.fields.variables.single;
      var name = variable.name.lexeme;
      var initializer = variable.initializer;
      if (initializer == null) {
        refuse(
          member.offset,
          'no initializer',
          _params.containsKey(name)
              ? '"$name" is a parameter — the header already declares its '
                    'field; there is nothing to add below'
              : '`$name` must be initialized with a node',
        );
        continue;
      }
      if (declared.containsKey(name)) {
        refuse(
          variable.offset,
          'duplicate name',
          '"$name" is already declared — parameters and nodes share one '
              'namespace, and a name is an identity',
        );
        continue;
      }
      declared[name] = variable.offset;
      var node = _node(name, initializer, childRefs);
      if (node != null) nodes[name] = node;
    }

    var root = nodes['root'];
    if (root == null) {
      if (refusals.isEmpty) {
        refuse(
          found.offset,
          'no root',
          'the scene class declares `late final root = Frame(…)`',
        );
      }
      return null;
    }
    if (root is! FrameNode) {
      refuse(declared['root']!, 'root kind', '`root` must be a Frame(…)');
      return null;
    }

    // Phase 2: link. Every reference resolves, every node has one parent,
    // and everything hangs off root — a placed-but-unreachable node (a
    // cycle, or a child of an orphan) would be silently dropped by the next
    // save, which is exactly the shredder this parser exists to refuse.
    var placed = <String>{};
    for (var entry in childRefs.entries) {
      var frame = nodes[entry.key];
      for (var (ref, offset) in entry.value) {
        if (ref == 'root') {
          refuse(
            offset,
            'root as child',
            '`root` is the tree — it cannot be placed inside itself',
          );
          continue;
        }
        var child = nodes[ref];
        if (child == null) {
          refuse(
            offset,
            'unknown reference',
            '"$ref" is not a node declared in this scene',
          );
          continue;
        }
        if (!placed.add(ref)) {
          refuse(
            offset,
            'placed twice',
            '"$ref" is already placed — a node has exactly one parent',
          );
          continue;
        }
        if (frame is FrameNode) frame.children.add(child);
      }
    }
    var reachable = <SceneNode>{};
    void reach(SceneNode n) {
      if (!reachable.add(n)) return;
      n.children.forEach(reach);
    }

    reach(root);
    for (var entry in nodes.entries) {
      if (entry.key == 'root') continue;
      if (!placed.contains(entry.key)) {
        refuse(
          declared[entry.key]!,
          'orphan node',
          '"${entry.key}" is declared but never placed in a children list — '
              'the next save would silently drop it',
        );
      } else if (!reachable.contains(entry.value)) {
        refuse(
          declared[entry.key]!,
          'unreachable node',
          '"${entry.key}" is placed, but its parent chain never reaches '
              '`root` — the next save would silently drop it',
        );
      }
    }
    var doc = SceneDocument(root);
    doc.params.addAll(_params.values);
    // An item reference cannot escape its closure — the grammar has no way
    // to write one outside a `row:` — so there is nothing to check here any
    // more. What is left is turning each recorded binding into the closure
    // everything draws through.
    bindRepeats(doc);
    return doc;
  }

  /// The file level: the authoring import, which must be there, and every
  /// other import, kept exactly as written. A `part`, an `export` or a
  /// `library` is refused — the tool rewrites this whole file, and those
  /// change what that means.
  void _readDirectives(CompilationUnit unit, String source) {
    var hasAuthoring = false;
    for (var directive in unit.directives) {
      if (directive is! ImportDirective) {
        refuse(
          directive.offset,
          'directive',
          'a scene file imports and nothing else — no part, export or '
              'library declaration',
        );
        continue;
      }
      var text = source.substring(directive.offset, directive.end);
      if (directive.uri.stringValue == sceneAuthoringUri) {
        if (directive.prefix != null || directive.combinators.isNotEmpty) {
          refuse(
            directive.offset,
            'authoring import',
            'the authoring import is written plain — $sceneAuthoringImport',
          );
          continue;
        }
        hasAuthoring = true;
        continue;
      }
      imports.add(text);
    }
    if (!hasAuthoring) {
      refuse(
        0,
        'missing import',
        'a scene file is Dart, so it imports its vocabulary — '
            '$sceneAuthoringImport',
      );
    }
  }

  /// The header's formals are the parameter table: each is a named
  /// `final <Type> <name> = <literal>` — one spelling for the formal, the
  /// field and the default, and the default IS the mockup.
  void _readParams(
    PrimaryConstructorDeclaration pc,
    Map<String, int> declared,
  ) {
    if (pc.constKeyword != null) {
      refuse(
        pc.constKeyword!.offset,
        'const',
        'a scene is never const — its nodes are late finals',
      );
    }
    for (var p in pc.formalParameters.parameters) {
      var name = p.name?.lexeme;
      if (p is FieldFormalParameter) {
        refuse(
          p.offset,
          'parameter',
          'a scene parameter is spelled in full in the header — '
              "`final String $name = '…'` — never `this.`",
        );
        continue;
      }
      if (!p.isNamed || name == null) {
        refuse(
          p.offset,
          'parameter',
          'a scene parameter is a named header formal with a default — '
              "`final String title = '…'`",
        );
        continue;
      }
      var dflt = p.defaultClause?.value;
      if (dflt == null) {
        refuse(
          p.offset,
          'no default',
          'a parameter carries its mockup as the default value',
        );
        continue;
      }
      if (_params.containsKey(name)) {
        refuse(p.offset, 'duplicate name', '"$name" is declared twice');
        continue;
      }
      var parsed = _paramDefaultOf(dflt);
      if (parsed == null) {
        refuse(
          dflt.offset,
          'parameter default',
          'a default is a string, number, bool or SceneColor(0x…) literal',
        );
        continue;
      }
      var decl = SceneParamDecl(name, parsed.$1, parsed.$2);
      if (p is RegularFormalParameter &&
          p.type != null &&
          '${p.type}' != decl.typeName) {
        refuse(
          p.type!.offset,
          'parameter type',
          'this default makes "$name" a ${decl.typeName} — spell it '
              '`final ${decl.typeName} $name`',
        );
        continue;
      }
      _params[name] = decl;
      declared[name] = p.offset;
    }
  }

  (SceneParamKind, Object)? _paramDefaultOf(Expression e) {
    var inner = e;
    var negate = false;
    if (inner is PrefixExpression && inner.operator.lexeme == '-') {
      negate = true;
      inner = inner.operand;
    }
    switch (inner) {
      case SimpleStringLiteral(:var value):
        return (SceneParamKind.string, value);
      case BooleanLiteral(:var value):
        return (SceneParamKind.bool, value);
      case IntegerLiteral(:var value?):
        return (SceneParamKind.number, (negate ? -value : value).toDouble());
      case DoubleLiteral(:var value):
        return (SceneParamKind.number, negate ? -value : value);
      case ListLiteral list:
        return (SceneParamKind.list, _items(list));
      default:
        if (_invocation(inner) case ('SceneColor', var args)
            when args.arguments.length == 1) {
          var v = args.arguments.single.argumentExpression;
          if (v is IntegerLiteral && v.value != null) {
            return (SceneParamKind.color, SceneColor(v.value!));
          }
        }
        return null;
    }
  }

  /// A list parameter's mockup: items, each a RECORD of named fields whose
  /// values are strings or numbers. A record rather than a map because the
  /// field names are then a TYPE, and `line.item` inside a repeat's closure
  /// is checked against it.
  List<SceneItem> _items(ListLiteral list) {
    var items = <SceneItem>[];
    for (var element in list.elements) {
      if (element is! RecordLiteral) {
        refuse(
          element.offset,
          element is Expression ? _kind(element) : _elementKind(element),
          "an item is a record literal — (item: 'Espresso beans', qty: '12')",
        );
        continue;
      }
      var item = <String, Object>{};
      for (var field in element.fields) {
        if (field is! RecordLiteralNamedField) {
          refuse(
            field.offset,
            'positional field',
            "an item's fields are named — (item: '…', qty: '…')",
          );
          continue;
        }
        var value = _itemValue(field.fieldExpression);
        if (value != null) item[field.name.lexeme] = value;
      }
      items.add(item);
    }
    return items;
  }

  Object? _itemValue(Expression e) {
    var inner = e;
    var negate = false;
    if (inner is PrefixExpression && inner.operator.lexeme == '-') {
      negate = true;
      inner = inner.operand;
    }
    switch (inner) {
      case SimpleStringLiteral(:var value):
        return value;
      case IntegerLiteral(:var value?):
        return (negate ? -value : value).toDouble();
      case DoubleLiteral(:var value):
        return negate ? -value : value;
      default:
        refuse(
          e.offset,
          _kind(e),
          "an item's field is a string or a number literal",
        );
        return null;
    }
  }

  /// No comment survives an emit, so none may enter: a comment inside the
  /// class body is refused rather than silently shredded on the next save.
  void _refuseComments(ClassDeclaration decl) {
    var body = decl.body;
    if (body is! BlockClassBody) return;
    var start = body.leftBracket.offset;
    var end = decl.endToken.offset;
    for (
      Token? token = body.leftBracket;
      token != null && token.offset <= end;
      token = token.next
    ) {
      for (
        Token? comment = token.precedingComments;
        comment != null;
        comment = comment.next
      ) {
        if (comment.offset > start) {
          refuse(
            comment.offset,
            'comment',
            'comments inside the scene are not preserved by the editor, so '
                'they are refused rather than silently lost on the next save',
          );
        }
      }
      if (token.offset >= end) break;
    }
  }

  SceneNode? _node(
    String name,
    Expression expr,
    Map<String, List<(String, int)>> childRefs,
  ) {
    var (kind, args) = _invocation(expr) ?? (null, null);
    if (kind == null || args == null) {
      refuse(
        expr.offset,
        'expression',
        'a node is a FrameNode, TextNode, ShapeNode or ExternalNode '
            'constructor call',
      );
      return null;
    }
    var positional = <Expression>[];
    var named = <String, Expression>{};
    for (var arg in args.arguments) {
      if (arg is NamedArgument) {
        named[arg.name.lexeme] = arg.argumentExpression;
      } else {
        positional.add(arg.argumentExpression);
      }
    }
    switch (kind) {
      case 'FrameNode.repeating':
        return _repeating(name, named, positional, args, childRefs);
      case 'FrameNode':
        var node = FrameNode(name: name);
        _applyCommon(node, named);
        _take(named, 'layout', (e) {
          var v = _enum(e, 'NodeLayout', NodeLayout.values.map((v) => v.name));
          if (v != null) {
            node.layout = NodeLayout.values.byName(v);
          }
        });
        _take(
          named,
          'gap',
          (e) => node.gap = _doubleV(e, node, 'gap') ?? node.gap,
        );
        _take(
          named,
          'padding',
          (e) =>
              node.padding = SceneEdges.all(_doubleV(e, node, 'padding') ?? 0),
        );
        for (var (name, set) in <(String, SceneEdges Function(double))>[
          ('paddingLeft', (v) => node.padding.copyWith(left: v)),
          ('paddingTop', (v) => node.padding.copyWith(top: v)),
          ('paddingRight', (v) => node.padding.copyWith(right: v)),
          ('paddingBottom', (v) => node.padding.copyWith(bottom: v)),
        ]) {
          _take(named, name, (e) {
            var v = _doubleV(e, node, name);
            if (v != null) node.padding = set(v);
          });
        }
        _take(named, 'columns', (e) {
          if (e is! ListLiteral) {
            refuse(
              e.offset,
              'columns',
              'columns takes a list of sizes — '
                  '[double.infinity, 48, null]',
            );
            return;
          }
          var tracks = <double?>[];
          for (var element in e.elements) {
            if (element is! Expression) {
              refuse(
                element.offset,
                _elementKind(element),
                'a table names its columns one by one',
              );
              continue;
            }
            tracks.add(element is NullLiteral ? null : _size(element));
          }
          node.columns = tracks;
        });
        _take(named, 'cellPadding', (e) {
          node.cellPadding = SceneEdges.all(
            _doubleV(e, node, 'cellPadding') ?? 0,
          );
        });
        for (var (name, set) in <(String, SceneEdges Function(double))>[
          ('cellPaddingLeft', (v) => node.cellPadding.copyWith(left: v)),
          ('cellPaddingTop', (v) => node.cellPadding.copyWith(top: v)),
          ('cellPaddingRight', (v) => node.cellPadding.copyWith(right: v)),
          ('cellPaddingBottom', (v) => node.cellPadding.copyWith(bottom: v)),
        ]) {
          _take(named, name, (e) {
            var v = _doubleV(e, node, name);
            if (v != null) node.cellPadding = set(v);
          });
        }
        _take(named, 'mainAlign', (e) {
          var v = _enum(
            e,
            'SceneMainAxisAlignment',
            SceneMainAxisAlignment.values.map((v) => v.name),
          );
          if (v != null) {
            node.mainAlign = SceneMainAxisAlignment.values.byName(v);
          }
        });
        _take(named, 'crossAlign', (e) {
          var v = _enum(
            e,
            'SceneCrossAxisAlignment',
            SceneCrossAxisAlignment.values.map((v) => v.name),
          );
          if (v != null) {
            node.crossAlign = SceneCrossAxisAlignment.values.byName(v);
          }
        });
        _take(named, 'children', (e) {
          if (e is! ListLiteral) {
            refuse(e.offset, 'children', 'children takes a list literal');
            return;
          }
          // Inside a repeat's closure a cell IS written here: it has no one
          // row to be a field of. Everywhere else a child is placed by name.
          if (_itemScope != null) {
            node.children.addAll(_inlineCells(e, childRefs));
            return;
          }
          var refs = childRefs.putIfAbsent(name, () => []);
          for (var element in e.elements) {
            switch (element) {
              case SimpleIdentifier id when _params.containsKey(id.name):
                refuse(
                  id.offset,
                  'parameter as child',
                  '"${id.name}" is a parameter — children list nodes',
                );
              case SimpleIdentifier id:
                refs.add((id.name, id.offset));
              case Expression x when _invocation(x) != null:
                refuse(
                  element.offset,
                  'inline node',
                  'a node is declared as its own field and placed here by '
                      'name — `children: [headline]`, with '
                      '`late final headline = …` beside it',
                );
              case Expression x:
                refuse(
                  x.offset,
                  _kind(x),
                  'children lists nodes by their field names',
                );
              default:
                refuse(
                  element.offset,
                  _elementKind(element),
                  'a scene lists its children one by one — the editor cannot '
                  'read a computed list',
                );
            }
          }
        });
        _refuseRest('FrameNode', named);
        _checkPositionals(positional, 0);
        return node;
      case 'TextNode':
        var node = TextNode('', name: name);
        node.text = _contentOf(positional, args, node) ?? '';
        _applyCommon(node, named);
        _take(
          named,
          'fontSize',
          (e) => node.fontSize = _doubleV(e, node, 'fontSize') ?? node.fontSize,
        );
        _take(named, 'align', (e) {
          var v = _enum(e, 'SceneTextAlign', [
            for (var a in SceneTextAlign.values) a.name,
          ]);
          if (v != null) {
            node.align = SceneTextAlign.values.firstWhere((a) => a.name == v);
          }
        });
        _take(named, 'maxLines', (e) {
          var v = _double(e);
          if (v != null) node.maxLines = v.round();
        });
        _take(named, 'weight', (e) {
          var v = _enum(e, 'SceneFontWeight', [
            for (var i = 1; i <= 9; i++) 'w${i * 100}',
          ]);
          if (v != null) {
            node.weight =
                SceneFontWeight.values[int.parse(v.substring(1)) ~/ 100 - 1];
          }
        });
        _take(
          named,
          'color',
          (e) => node.color = _colorV(e, node, 'color') ?? node.color,
        );
        _refuseRest('TextNode', named);
        _checkPositionals(positional, 1);
        return node;
      case 'ShapeNode':
        var node = ShapeNode(name: name);
        _applyCommon(node, named);
        _take(named, 'circle', (e) => node.circle = _bool(e) ?? false);
        _refuseRest('ShapeNode', named);
        _checkPositionals(positional, 0);
        return node;
      case 'ExternalNode' || 'SceneRefNode':
        var read = _typedArgs(
          positional,
          args,
          kind == 'ExternalNode'
              ? 'an ExternalNode takes the generated arguments of the widget '
                    'it places — ExternalNode(const DrinkBadgeArgs(size: 140))'
              : 'a SceneRefNode takes the generated arguments of the scene it '
                    "instantiates — SceneRefNode(const PromoBadgeArgs(label: 'New'))",
        );
        var (target, nodeArgs) = read ?? ('', <String, Object?>{});
        if (declaredArgs[target] case var declared?) {
          for (var name in nodeArgs.keys) {
            if (declared.contains(name)) continue;
            refuse(
              positional[0].offset,
              'unknown argument',
              '$target declares no "$name" — it takes '
                  '${declared.isEmpty ? 'no arguments' : declared.join(', ')}',
            );
          }
        }
        var node = kind == 'ExternalNode'
            ? ExternalNode.read(target, name: name, args: nodeArgs)
            : SceneRefNode.read(target, name: name, args: nodeArgs);
        _applyCommon(node, named);
        _refuseRest(kind, named);
        _checkPositionals(positional, 1);
        return node;
      default:
        refuse(
          expr.offset,
          'unknown node',
          '"$kind" is not a scene node — FrameNode, TextNode, ShapeNode, '
              'ExternalNode or SceneRefNode',
        );
        return null;
    }
  }

  /// `FrameNode.repeating(over: lines, row: (line) => [ … ], …)`.
  ///
  /// Read in one pass rather than routed through the plain frame reader,
  /// because the closure has to be OPEN while its cells are read — that is
  /// what makes `line.item` mean something there and nowhere else.
  SceneNode? _repeating(
    String name,
    Map<String, Expression> named,
    List<Expression> positional,
    ArgumentList args,
    Map<String, List<(String, int)>> childRefs,
  ) {
    var node = FrameNode(name: name);
    String? list;
    _take(named, 'over', (e) {
      if (e is! SimpleIdentifier) {
        refuse(e.offset, _kind(e), 'over names a list parameter');
        return;
      }
      var decl = _params[e.name];
      if (decl == null || decl.kind != SceneParamKind.list) {
        refuse(
          e.offset,
          'over',
          decl == null
              ? '"${e.name}" is not a parameter of this scene'
              : '"${e.name}" is a ${decl.typeName} — a repeat draws one row '
                    'per item of a list parameter',
        );
        return;
      }
      list = e.name;
    });
    if (list == null) {
      if (!named.containsKey('over')) {
        refuse(
          args.offset,
          'over',
          'a repeat says what it draws — `over: lines`',
        );
      }
      return null;
    }
    var rowArg = named.remove('row');
    if (rowArg == null) {
      refuse(
        args.offset,
        'row',
        'a repeat says how to draw one item — `row: (line) => [ … ]`',
      );
      return null;
    }
    if (rowArg is! FunctionExpression) {
      refuse(rowArg.offset, _kind(rowArg), 'row is `(line) => [ … ]`');
      return null;
    }
    var formals = rowArg.parameters?.parameters ?? const <FormalParameter>[];
    var item = formals.length == 1 ? formals.single.name : null;
    if (item == null) {
      refuse(
        rowArg.offset,
        'row',
        'row takes one parameter — the item it is drawing',
      );
      return null;
    }
    var body = rowArg.body;
    if (body is! ExpressionFunctionBody || body.expression is! ListLiteral) {
      refuse(
        rowArg.offset,
        'row',
        "row returns the row's cells — `(line) => [TextNode(line.item)]`",
      );
      return null;
    }
    var outer = _itemScope;
    _itemScope = (param: item.lexeme, list: list!);
    // Common properties are read INSIDE the scope too: a row's own fill or
    // border may read the item like any cell.
    _applyCommon(node, named);
    _take(named, 'layout', (e) {
      var v = _enum(e, 'NodeLayout', NodeLayout.values.map((v) => v.name));
      if (v != null) node.layout = NodeLayout.values.byName(v);
    });
    _take(named, 'gap', (e) => node.gap = _doubleV(e, node, 'gap') ?? node.gap);
    _take(
      named,
      'padding',
      (e) => node.padding = SceneEdges.all(_doubleV(e, node, 'padding') ?? 0),
    );
    for (var (side, set) in <(String, SceneEdges Function(double))>[
      ('paddingLeft', (v) => node.padding.copyWith(left: v)),
      ('paddingTop', (v) => node.padding.copyWith(top: v)),
      ('paddingRight', (v) => node.padding.copyWith(right: v)),
      ('paddingBottom', (v) => node.padding.copyWith(bottom: v)),
    ]) {
      _take(named, side, (e) {
        var v = _doubleV(e, node, side);
        if (v != null) node.padding = set(v);
      });
    }
    _take(named, 'mainAlign', (e) {
      var v = _enum(e, 'SceneMainAxisAlignment', [
        for (var a in SceneMainAxisAlignment.values) a.name,
      ]);
      if (v != null) {
        node.mainAlign = SceneMainAxisAlignment.values.byName(v);
      }
    });
    _take(named, 'crossAlign', (e) {
      var v = _enum(e, 'SceneCrossAxisAlignment', [
        for (var a in SceneCrossAxisAlignment.values) a.name,
      ]);
      if (v != null) {
        node.crossAlign = SceneCrossAxisAlignment.values.byName(v);
      }
    });
    node.children.addAll(
      _inlineCells(body.expression as ListLiteral, childRefs),
    );
    _itemScope = outer;
    _refuseRest('FrameNode.repeating', named);
    _checkPositionals(positional, 0);
    recordRepeat(node, list!);
    return node;
  }

  /// The cells of a repeated row, each written inline. Named from the
  /// sequence rather than from the file, because the file gives them none.
  List<SceneNode> _inlineCells(
    ListLiteral list,
    Map<String, List<(String, int)>> childRefs,
  ) {
    var out = <SceneNode>[];
    for (var element in list.elements) {
      if (element is! Expression) {
        refuse(
          element.offset,
          _elementKind(element),
          'a row lists its cells one by one',
        );
        continue;
      }
      if (element is SimpleIdentifier) {
        refuse(
          element.offset,
          'named cell',
          'a repeated row writes its cells inline — they are not fields, '
              'because there is no one row for them to belong to',
        );
        continue;
      }
      var cell = _node('cell${++_cellSeq}', element, childRefs);
      if (cell != null) out.add(cell);
    }
    return out;
  }

  void _checkPositionals(List<Expression> positional, int count) {
    if (positional.length > count) {
      refuse(
        positional[count].offset,
        'positional argument',
        'this node takes $count positional argument(s)',
      );
    }
  }

  void _applyCommon(SceneNode n, Map<String, Expression> named) {
    _take(named, 'x', (e) => n.x = _doubleV(e, n, 'x') ?? 0);
    _take(named, 'y', (e) => n.y = _doubleV(e, n, 'y') ?? 0);
    _take(named, 'width', (e) => n.width = _sizeV(e, n, 'width'));
    _take(named, 'height', (e) => n.height = _sizeV(e, n, 'height'));
    _take(named, 'fill', (e) => n.fill = _colorV(e, n, 'fill'));
    _take(
      named,
      'borderColor',
      (e) => n.borderColor = _colorV(e, n, 'borderColor'),
    );
    _take(
      named,
      'borderWidth',
      (e) => n.borderWidth = _doubleV(e, n, 'borderWidth') ?? 1,
    );
    _take(named, 'corner', (e) => n.corner = _doubleV(e, n, 'corner') ?? 0);
    _take(named, 'opacity', (e) => n.opacity = _doubleV(e, n, 'opacity') ?? 1);
    _take(named, 'visible', (e) => n.visible = _boolV(e, n, 'visible') ?? true);
  }

  void _take(
    Map<String, Expression> named,
    String key,
    void Function(Expression) apply,
  ) {
    var e = named.remove(key);
    if (e != null) apply(e);
  }

  void _refuseRest(String node, Map<String, Expression> named) {
    for (var entry in named.entries) {
      refuse(
        entry.value.offset,
        'unknown property',
        '$node has no property "${entry.key}"',
      );
    }
  }

  String? _contentOf(
    List<Expression> positional,
    ArgumentList args,
    TextNode node,
  ) {
    if (positional.isEmpty) {
      refuse(
        args.offset,
        'missing argument',
        'a string literal is required here',
      );
      return null;
    }
    return _stringV(positional[0], node, 'text');
  }

  /// `const DrinkBadgeArgs(size: 140)` — an external node's whole identity
  /// and arguments, as one typed constructor call.
  ///
  /// Three cheap things make it readable without resolving anything: the
  /// class name gives the entry (`…Args` stripped), the named arguments
  /// give the values, and the app's declaration of that widget — which the
  /// generator wrote this class from — gives their types. An argument the
  /// widget does not declare therefore fails twice: it does not compile,
  /// and it is refused here with a line number.
  (String, Map<String, Object?>)? _typedArgs(
    List<Expression> positional,
    ArgumentList args,
    String missing,
  ) {
    if (positional.isEmpty) {
      refuse(args.offset, 'missing argument', missing);
      return null;
    }
    var e = positional[0];
    var call = _invocation(e);
    if (call == null || !call.$1.endsWith('Args') || call.$1.length < 5) {
      refuse(e.offset, _kind(e), missing);
      return null;
    }
    var entry = call.$1.substring(0, call.$1.length - 'Args'.length);
    if (!isValidNodeName(entry)) {
      refuse(e.offset, call.$1, missing);
      return null;
    }
    var out = <String, Object?>{};
    for (var arg in call.$2.arguments) {
      if (arg is! NamedArgument) {
        refuse(
          arg.offset,
          _kind(arg.argumentExpression),
          'every argument is named — ${call.$1}(size: 140)',
        );
        continue;
      }
      out[arg.name.lexeme] = _literal(arg.argumentExpression);
    }
    return (entry, out);
  }

  // -- value parsers, each refusing with the construct it actually found.
  // -- The V variants additionally accept a declared parameter's name,
  // -- binding the property to the typed hole and yielding its default.

  /// A parameter reference at a value position, or null when [e] is not
  /// one (the plain parser then runs). A declared parameter of the wrong
  /// kind is refused here, with both types named.
  Object? _paramRef(
    Expression e,
    SceneParamKind kind,
    SceneNode n,
    String prop,
  ) {
    if (e is PrefixedIdentifier) return _itemRef(e, kind, n, prop);
    if (e is! SimpleIdentifier) return null;
    var decl = _params[e.name];
    if (decl == null) return null;
    if (decl.kind != kind) {
      var wanted = switch (kind) {
        SceneParamKind.string => 'String',
        SceneParamKind.number => 'double',
        SceneParamKind.color => 'SceneColor',
        SceneParamKind.bool => 'bool',
        SceneParamKind.list => 'List<Map<String, Object>>',
      };
      refuse(
        e.offset,
        'parameter type',
        '"${e.name}" is a ${decl.typeName} parameter — this property takes '
            'a $wanted',
      );
      return _refused;
    }
    n.bindings[prop] = ParamRef(e.name);
    return decl.defaultValue;
  }

  /// `lines.item` — one field of the item a repeat is drawing. The value
  /// it yields is the FIRST item's, which is what the file holds and what
  /// the editor shows; the rest are drawn as copies at render time.
  Object? _itemRef(
    PrefixedIdentifier e,
    SceneParamKind kind,
    SceneNode n,
    String prop,
  ) {
    var scope = _itemScope;
    if (scope == null || e.prefix.name != scope.param) return null;
    var decl = _params[scope.list];
    if (decl == null || decl.kind != SceneParamKind.list) return null;
    var field = e.identifier.name;
    var items = decl.items;
    if (items.isEmpty || !items.first.containsKey(field)) {
      refuse(
        e.offset,
        'unknown field',
        items.isEmpty
            ? '"${scope.list}" has no items, so there is no "$field" to read'
            : '"${scope.list}" items carry '
                  '${items.first.keys.map((k) => '"$k"').join(', ')} — '
                  'not "$field"',
      );
      return _refused;
    }
    var value = items.first[field]!;
    var converted = switch (kind) {
      // A number reads as the text it becomes, which is what a quantity in
      // a table cell is.
      SceneParamKind.string => value is String ? value : _num(value as double),
      SceneParamKind.number => value is double ? value : null,
      _ => null,
    };
    if (converted == null) {
      refuse(
        e.offset,
        'field type',
        '"${e.prefix.name}.$field" is a ${value is String ? 'string' : 'number'}'
            ' — this property takes a '
            '${kind == SceneParamKind.number ? 'number' : 'value of another kind'}',
      );
      return _refused;
    }
    // Recorded against the LIST, not the closure's parameter: the parameter
    // is a local name and the binding has to outlive it.
    n.bindings[prop] = ItemRef(scope.list, field);
    return converted;
  }

  static final _refused = Object();

  /// A size: `double.infinity` for fill, otherwise a number or a parameter.
  double? _sizeV(Expression e, SceneNode n, String prop) {
    if (_infinity(e)) return double.infinity;
    return _doubleV(e, n, prop);
  }

  /// A size with no property behind it — a table's column track, which
  /// belongs to the frame rather than to any one node.
  double? _size(Expression e) => _infinity(e) ? double.infinity : _double(e);

  bool _infinity(Expression e) =>
      e is PrefixedIdentifier &&
      e.prefix.name == 'double' &&
      e.identifier.name == 'infinity';

  double? _doubleV(Expression e, SceneNode n, String prop) {
    var v = _paramRef(e, SceneParamKind.number, n, prop);
    if (identical(v, _refused)) return null;
    if (v != null) return v as double;
    return _double(e);
  }

  bool? _boolV(Expression e, SceneNode n, String prop) {
    var v = _paramRef(e, SceneParamKind.bool, n, prop);
    if (identical(v, _refused)) return null;
    if (v != null) return v as bool;
    return _bool(e);
  }

  String? _stringV(Expression e, SceneNode n, String prop) {
    var v = _paramRef(e, SceneParamKind.string, n, prop);
    if (identical(v, _refused)) return null;
    if (v != null) return v as String;
    return _string(e);
  }

  SceneColor? _colorV(Expression e, SceneNode n, String prop) {
    var v = _paramRef(e, SceneParamKind.color, n, prop);
    if (identical(v, _refused)) return null;
    if (v != null) return v as SceneColor;
    return _colorOf(e);
  }

  (String, ArgumentList)? _invocation(Expression e) => switch (e) {
    MethodInvocation(:var methodName, :var target, :var argumentList)
        when target == null =>
      (methodName.name, argumentList),
    // `FrameNode.repeating(…)` — a static, because the rule it takes is
    // generic in the item type and a constructor cannot be.
    MethodInvocation(
      :var methodName,
      target: SimpleIdentifier t,
      :var argumentList,
    ) =>
      ('${t.name}.${methodName.name}', argumentList),
    InstanceCreationExpression(:var constructorName, :var argumentList)
        when constructorName.name == null =>
      (constructorName.type.name.lexeme, argumentList),
    _ => null,
  };

  double? _double(Expression e) {
    var negate = false;
    var inner = e;
    if (inner is PrefixExpression && inner.operator.lexeme == '-') {
      negate = true;
      inner = inner.operand;
    }
    var value = switch (inner) {
      IntegerLiteral(:var value) => value?.toDouble(),
      DoubleLiteral(:var value) => value,
      _ => null,
    };
    if (value == null) {
      refuse(e.offset, _kind(e), 'expected a number literal');
      return null;
    }
    return negate ? -value : value;
  }

  String? _string(Expression e) {
    if (e is SimpleStringLiteral) return e.value;
    refuse(
      e.offset,
      _kind(e),
      'expected a single string literal — the editor cannot evaluate '
      '${_kind(e) == 'interpolation' ? 'an interpolation' : 'this'}',
    );
    return null;
  }

  bool? _bool(Expression e) {
    if (e is BooleanLiteral) return e.value;
    refuse(e.offset, _kind(e), 'expected true or false');
    return null;
  }

  SceneColor? _colorOf(Expression e) {
    if (_invocation(e) case ('SceneColor', var args)
        when args.arguments.length == 1) {
      var v = args.arguments.single.argumentExpression;
      if (v is IntegerLiteral && v.value != null) return SceneColor(v.value!);
    }
    refuse(
      e.offset,
      _kind(e),
      'expected a color, spelled SceneColor(0xAARRGGBB)',
    );
    return null;
  }

  String? _enum(Expression e, String prefix, Iterable<String> values) {
    if (e is PrefixedIdentifier &&
        e.prefix.name == prefix &&
        values.contains(e.identifier.name)) {
      return e.identifier.name;
    }
    refuse(
      e.offset,
      _kind(e),
      'expected $prefix.<${values.take(4).join('|')}…> — nothing else is '
      'on the allowlist',
    );
    return null;
  }

  Object? _literal(Expression e) {
    var inner = e;
    var negate = false;
    if (e is PrefixExpression && e.operator.lexeme == '-') {
      negate = true;
      inner = e.operand;
    }
    return switch (inner) {
      IntegerLiteral(:var value) =>
        value == null ? null : (negate ? -value : value),
      DoubleLiteral(:var value) => negate ? -value : value,
      BooleanLiteral(:var value) => value,
      SimpleStringLiteral(:var value) => value,
      _ when _invocation(inner)?.$1 == 'SceneColor' => _colorOf(inner),
      _ => () {
        refuse(
          e.offset,
          _kind(e),
          'expected a number, string, bool or SceneColor(0x…) literal',
        );
        return null;
      }(),
    };
  }

  /// Names what the hand actually wrote, so the refusal teaches.
  String _kind(Expression e) => switch (e) {
    ConditionalExpression() => 'conditional',
    BinaryExpression() => 'arithmetic',
    MethodInvocation() => 'method call',
    StringInterpolation() => 'interpolation',
    AdjacentStrings() => 'adjacent strings',
    SimpleIdentifier() => 'identifier',
    PrefixedIdentifier() => 'identifier',
    _ => e.runtimeType.toString(),
  };

  String _elementKind(CollectionElement e) => switch (e) {
    ForElement() => 'for element',
    IfElement() => 'if element',
    SpreadElement() => 'spread',
    _ => e.runtimeType.toString(),
  };
}
