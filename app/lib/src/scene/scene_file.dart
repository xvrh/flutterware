// Disposable spike: the scene file grammar, its parser and its emitter — the
// tier-2 round-trip bet measured on the touched model instead of a predicted
// one.
//
// THE GRAMMAR, on a page. A scene file is:
//   - a `//@flutterware:scene=…` marker in its first line
//   - file-level comments and imports (before the class; not parsed)
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
//   - `children: [ … ]` lists nodes BY FIELD NAME — every node is declared
//     as its own field and placed exactly once (forward references are fine;
//     `late` is what makes sibling references legal Dart)
//   - values are: int/double literals (optionally negated), single string
//     literals with no interpolation, bool literals, `Color(0x…)`,
//     allowlisted enum references, `args: {'k': literal}` maps, and — where
//     the types agree — A PARAMETER'S NAME, which binds the property to the
//     typed hole
//   - a parameter may also be a LIST — `final List<Map<String, Object>>
//     lines = const [{'item': '…', 'qty': 12}]` — whose items are string
//     and number fields. A node with `repeat: lines` is drawn once per
//     item, and a property inside it reads a field by the dotted name
//     `lines.item`, which is legal only inside that repeat
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

const sceneFileMarker = '//@flutterware:scene=0.7';

/// The one library a scene file imports. Its vocabulary IS the model's own
/// class names — `FrameNode`, `TextNode`, `SceneColor` — because a spelling
/// that differs from the type is a spelling the compiler cannot check.
const sceneAuthoringImport =
    "import 'package:flutterware/scene_authoring.dart';";

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
  ]);

  final SceneDocument? doc;
  final String? className;
  final List<SceneRefusal> refusals;

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
    for (var c in n.children) {
      field(c);
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

String _paramDefault(SceneParamDecl p) => switch (p.kind) {
  SceneParamKind.string => _str(p.defaultValue as String),
  SceneParamKind.number => _num(p.defaultValue as double),
  SceneParamKind.color => 'const ${_color(p.defaultValue as SceneColor)}',
  SceneParamKind.list => 'const [${p.items.map(_item).join(', ')}]',
};

String _item(SceneItem item) =>
    '{${[for (var e in item.entries) '${_str(e.key)}: ${_argValue(e.value)}'].join(', ')}}';

void _emitNode(StringBuffer out, SceneNode n, Map<String, SceneParamDecl> ps) {
  var props = <String>[];

  /// A parameter reference survives a save only while the property still
  /// holds the parameter's default — an edited value bakes in and the
  /// stale reference is dropped, never the edit. For an item reference the
  /// default is the FIRST item's field, which is the rule the whole
  /// repeater rests on.
  String? ref(String key, Object? current) {
    var name = n.paramRefs[key];
    if (name == null) return null;
    var dot = name.indexOf('.');
    if (dot < 0) {
      var p = ps[name];
      if (p == null || p.defaultValue != current) return null;
      return name;
    }
    var list = ps[name.substring(0, dot)];
    if (list == null || list.kind != SceneParamKind.list) return null;
    var items = list.items;
    if (items.isEmpty) return null;
    var field = items.first[name.substring(dot + 1)];
    return field != null && _sameValue(current, field) ? name : null;
  }

  void add(String key, Object? current, String Function() spell) {
    props.add('$key: ${ref(key, current) ?? spell()}');
  }

  void common() {
    if (n.x != 0 || n.paramRefs.containsKey('x')) {
      add('x', n.x, () => _num(n.x));
    }
    if (n.y != 0 || n.paramRefs.containsKey('y')) {
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
    if (n.repeat case var list?) props.add('repeat: $list');
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
      if (f.children.isNotEmpty) {
        props.add('children: [${f.children.map((c) => c.name).join(', ')}]');
      }
      out.write('FrameNode(${props.join(', ')})');
    case TextNode t:
      props.add(ref('text', t.text) ?? _str(t.text));
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
      if (!isValidNodeName(e.entry)) {
        throw ArgumentError('"${e.entry}" is not a registration entry name');
      }
      props.add(_str(e.entry));
      common();
      if (e.args.isNotEmpty) {
        props.add(
          'args: {${[for (var entry in e.args.entries) '${_str(entry.key)}: ${_argValue(entry.value)}'].join(', ')}}',
        );
      }
      out.write('ExternalNode(${props.join(', ')})');
    case SceneRefNode r:
      if (!isValidNodeName(r.sceneClassName)) {
        throw ArgumentError('"${r.sceneClassName}" is not a scene class name');
      }
      props.add(_str(r.sceneClassName));
      common();
      if (r.args.isNotEmpty) {
        props.add(
          'args: {${[for (var entry in r.args.entries) '${_str(entry.key)}: ${_argValue(entry.value)}'].join(', ')}}',
        );
      }
      out.write('SceneRefNode(${props.join(', ')})');
  }
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

/// Whether a property still holds what an item's field would put there —
/// the same widening [setSceneProperty] does, so a number filling a text
/// slot compares as the text it becomes.
bool _sameValue(Object? current, Object field) {
  if (current == field) return true;
  return current is String && field is double && current == _num(field);
}

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

SceneParse parseSceneFile(String source) {
  var p = _Parser(source);
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
  );
}

class _Parser {
  _Parser(this.source);

  final String source;
  final refusals = <SceneRefusal>[];
  String? className;

  /// Classes carrying `extends SceneMotion<…>` — parsed after the scene.
  final motionClasses = <ClassDeclaration>[];

  late final _lines = source.split('\n');

  /// Declared parameters, filled from the class header before any field is
  /// parsed.
  final _params = <String, SceneParamDecl>{};

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
    // Phase 3: an item reference reads the row being drawn, so it only
    // means something inside the repeat that draws it. Outside one it names
    // nothing at render time, and a value that resolves to nothing is
    // exactly the silent gap this parser exists to refuse.
    void checkItemRefs(SceneNode n, Set<String> scope) {
      var inner = n.repeat == null ? scope : {...scope, n.repeat!};
      for (var ref in n.paramRefs.entries) {
        var dot = ref.value.indexOf('.');
        if (dot < 0) continue;
        var list = ref.value.substring(0, dot);
        if (inner.contains(list)) continue;
        refuse(
          declared[n.name] ?? found!.offset,
          'item reference',
          '"${ref.value}" reads one item of "$list", so "${n.name}" must be '
              'inside a node with `repeat: $list`',
        );
      }
      for (var c in n.children) {
        checkItemRefs(c, inner);
      }
    }

    checkItemRefs(root, const {});

    var doc = SceneDocument(root);
    doc.params.addAll(_params.values);
    return doc;
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
          'a default is a string, number or SceneColor(0x…) literal',
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

  /// A list parameter's mockup: items, each a map of string keys to string
  /// or number values. Nothing else — an item's fields fill properties, and
  /// those are the two kinds a property takes from one.
  List<SceneItem> _items(ListLiteral list) {
    var items = <SceneItem>[];
    for (var element in list.elements) {
      if (element is! SetOrMapLiteral) {
        refuse(
          element.offset,
          element is Expression ? _kind(element) : _elementKind(element),
          "an item is a map literal — {'item': 'Espresso beans', 'qty': 12}",
        );
        continue;
      }
      var item = <String, Object>{};
      for (var entry in element.elements) {
        if (entry is! MapLiteralEntry) {
          refuse(entry.offset, _elementKind(entry), 'expected a literal entry');
          continue;
        }
        var key = _string(entry.key);
        var value = _itemValue(entry.value);
        if (key != null && value != null) item[key] = value;
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
        var target =
            _entryName(
              positional,
              args,
              kind == 'ExternalNode'
                  ? 'an ExternalNode names its registration entry — '
                        "ExternalNode('DrinkBadge', …)"
                  : 'a SceneRefNode names the scene class it instantiates — '
                        "SceneRefNode('PromoBadge', …)",
            ) ??
            '';
        var node = kind == 'ExternalNode'
            ? ExternalNode(target, name: name)
            : SceneRefNode(target, name: name);
        var nodeArgs = node is ExternalNode
            ? node.args
            : (node as SceneRefNode).args;
        _applyCommon(node, named);
        _take(named, 'args', (e) {
          if (e is! SetOrMapLiteral) {
            refuse(e.offset, 'args', 'args takes a map literal');
            return;
          }
          for (var element in e.elements) {
            if (element is! MapLiteralEntry) {
              refuse(
                element.offset,
                _elementKind(element),
                'expected a literal entry',
              );
              continue;
            }
            var key = _string(element.key);
            var value = _literal(element.value);
            if (key != null) nodeArgs[key] = value;
          }
        });
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
    _take(named, 'repeat', (e) {
      if (e is! SimpleIdentifier) {
        refuse(e.offset, _kind(e), 'repeat names a list parameter');
        return;
      }
      var decl = _params[e.name];
      if (decl == null || decl.kind != SceneParamKind.list) {
        refuse(
          e.offset,
          'repeat',
          decl == null
              ? '"${e.name}" is not a parameter of this scene'
              : '"${e.name}" is a ${decl.typeName} — a repeat draws its node '
                    'once per item of a list parameter',
        );
        return;
      }
      n.repeat = e.name;
    });
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

  /// An Ext's entry is spelled as an identifier — `Ext(DrinkBadge)` — the
  /// typed reference to a registration. A quoted spelling is accepted and
  /// converges to the identifier on the next emit.
  String? _entryName(
    List<Expression> positional,
    ArgumentList args,
    String missing,
  ) {
    if (positional.isEmpty) {
      refuse(args.offset, 'missing argument', missing);
      return null;
    }
    var e = positional[0];
    if (e is SimpleIdentifier && !_params.containsKey(e.name)) return e.name;
    if (e is SimpleStringLiteral && isValidNodeName(e.value)) return e.value;
    refuse(
      e.offset,
      _kind(e),
      'expected a registration entry name, spelled as an identifier',
    );
    return null;
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
    n.paramRefs[prop] = e.name;
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
    var decl = _params[e.prefix.name];
    if (decl == null || decl.kind != SceneParamKind.list) return null;
    var field = e.identifier.name;
    var items = decl.items;
    if (items.isEmpty || !items.first.containsKey(field)) {
      refuse(
        e.offset,
        'unknown field',
        items.isEmpty
            ? '"${e.prefix.name}" has no items, so there is no "$field" to read'
            : '"${e.prefix.name}" items carry '
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
    n.paramRefs[prop] = '${e.prefix.name}.$field';
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
