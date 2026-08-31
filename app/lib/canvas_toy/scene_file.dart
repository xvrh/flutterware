// Disposable spike: the scene file grammar, its parser and its emitter — the
// tier-2 round-trip bet measured on the touched model instead of a predicted
// one.
//
// THE GRAMMAR, on a page. A scene file is:
//   - a `//@flutterware:scene=…` marker in its first line
//   - file-level comments and imports (before the class body; not parsed)
//   - exactly one class declaration, holding exactly one field:
//     `final root = Frame(…);`
//   - a node is a constructor invocation: Frame, Text, Shape or Ext, with a
//     positional name (Text and Ext take one more positional), and named
//     arguments from that node's fixed vocabulary
//   - values are: int/double literals (optionally negated), single string
//     literals with no interpolation, bool literals, `Color(0x…)`,
//     allowlisted enum references, `children: [ … ]` of nodes, and
//     `args: {'k': literal}` maps
//   - nothing else: no comments inside the class body, no loops, no
//     conditionals, no method calls, no arithmetic, no identifiers off the
//     allowlist. Refused with a line number, never dropped — parse-drop plus
//     emit-regenerate is a shredder (measured on the deleted drawing plugin).
//
// Invariants the tests hold:
//   - parse(emit(model)) succeeds and re-emits identically (model identity)
//   - emit ∘ parse is the identity on canonical files
//   - every hostile construct is refused with an offset and a name, and
//     nothing ever throws.
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dart_style/dart_style.dart';
import 'package:flutter/material.dart';

import 'model.dart';

const sceneFileMarker = '//@flutterware:scene=0.1';

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
  SceneParse(this.doc, this.className, this.refusals);

  final SceneDocument? doc;
  final String? className;
  final List<SceneRefusal> refusals;

  bool get ok => doc != null;
}

// ---------------------------------------------------------------------------
// Emit
// ---------------------------------------------------------------------------

final _formatter = DartFormatter(
  languageVersion: DartFormatter.latestLanguageVersion,
);

String emitSceneFile(SceneDocument doc, {String className = 'SceneFile'}) {
  var out = StringBuffer('''
$sceneFileMarker
// Owned by the flutterware scene editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar; anything outside it is
// refused with a line number rather than silently dropped.

import 'package:flutter/material.dart';

class $className {
  final root = ''');
  _emitNode(out, doc.root);
  out.writeln(';');
  out.writeln('}');
  return _formatter.format(out.toString());
}

void _emitNode(StringBuffer out, SceneNode n) {
  switch (n) {
    case FrameNode f:
      out.write('Frame(${_str(f.name)}');
      _common(out, f);
      if (f.layout != NodeLayout.absolute) {
        out.write(', layout: NodeLayout.${f.layout.name}');
      }
      if (f.gap != 8) out.write(', gap: ${_num(f.gap)}');
      if (f.padding != 0) out.write(', padding: ${_num(f.padding)}');
      if (f.mainAlign != MainAxisAlignment.start) {
        out.write(', mainAlign: MainAxisAlignment.${f.mainAlign.name}');
      }
      if (f.crossAlign != CrossAxisAlignment.center) {
        out.write(', crossAlign: CrossAxisAlignment.${f.crossAlign.name}');
      }
      if (f.children.isNotEmpty) {
        out.write(', children: [');
        for (var c in f.children) {
          _emitNode(out, c);
          out.write(', ');
        }
        out.write(']');
      }
      out.write(')');
    case TextNode t:
      out.write('Text(${_str(t.name)}, ${_str(t.text)}');
      _common(out, t);
      if (t.fontSize != 16) out.write(', fontSize: ${_num(t.fontSize)}');
      if (t.weight != FontWeight.w400) {
        out.write(', weight: FontWeight.w${t.weight.value}');
      }
      if (t.color != const Color(0xFF1A1A1A)) {
        out.write(', color: ${_color(t.color)}');
      }
      out.write(')');
    case ShapeNode s:
      out.write('Shape(${_str(s.name)}');
      _common(out, s);
      if (s.circle) out.write(', circle: true');
      out.write(')');
    case ExternalNode e:
      out.write('Ext(${_str(e.name)}, ${_str(e.entry)}');
      _common(out, e);
      if (e.args.isNotEmpty) {
        out.write(', args: {');
        for (var entry in e.args.entries) {
          out.write('${_str(entry.key)}: ${_argValue(entry.value)}, ');
        }
        out.write('}');
      }
      out.write(')');
  }
}

void _common(StringBuffer out, SceneNode n) {
  if (n.x != 0) out.write(', x: ${_num(n.x)}');
  if (n.y != 0) out.write(', y: ${_num(n.y)}');
  if (n.width case var w?) out.write(', width: ${_num(w)}');
  if (n.height case var h?) out.write(', height: ${_num(h)}');
  if (n.fill case var f?) out.write(', fill: ${_color(f)}');
  if (n.cornerRadius != 0) out.write(', corner: ${_num(n.cornerRadius)}');
  if (n.opacity != 1) out.write(', opacity: ${_num(n.opacity)}');
}

/// Canonical number spelling: an integral double is an int literal, anything
/// else is Dart's own round-trippable `toString`. One spelling per value is
/// what makes emit ∘ parse an identity.
String _num(double v) =>
    v == v.roundToDouble() && v.abs() < 1e15 ? '${v.round()}' : '$v';

String _color(Color c) =>
    'Color(0x${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()})';

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
  _ => _str('$v'),
};

// ---------------------------------------------------------------------------
// Parse
// ---------------------------------------------------------------------------

SceneParse parseSceneFile(String source) {
  var p = _Parser(source);
  var doc = p.parse();
  return SceneParse(p.refusals.isEmpty ? doc : null, p.className, p.refusals);
}

class _Parser {
  _Parser(this.source);

  final String source;
  final refusals = <SceneRefusal>[];
  final _names = <String>{};
  String? className;
  late final _lines = source.split('\n');

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
        if (found != null) {
          refuse(
            decl.offset,
            'second class',
            'a scene file holds exactly one class',
          );
        } else {
          found = decl;
        }
      } else {
        refuse(
          decl.offset,
          'declaration',
          'only the scene class may be declared here',
        );
      }
    }
    if (found == null) {
      refuse(0, 'no class', 'a scene file holds exactly one class');
      return null;
    }
    className = found.namePart.typeName.lexeme;
    _refuseComments(found);

    FrameNode? root;
    for (var member in found.body.members) {
      if (member is FieldDeclaration &&
          member.fields.variables.length == 1 &&
          member.fields.variables.single.name.lexeme == 'root') {
        var initializer = member.fields.variables.single.initializer;
        if (initializer == null) {
          refuse(member.offset, 'no initializer', '`root` must be a Frame(…)');
          continue;
        }
        var node = _node(initializer);
        if (node is FrameNode) {
          root = node;
        } else if (node != null) {
          refuse(initializer.offset, 'root kind', '`root` must be a Frame(…)');
        }
      } else {
        refuse(
          member.offset,
          'member',
          'the scene class holds exactly one field, `root`',
        );
      }
    }
    if (root == null && refusals.isEmpty) {
      refuse(found.offset, 'no root', 'the scene class declares `final root`');
    }
    return root == null ? null : SceneDocument(root);
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

  SceneNode? _node(Expression expr) {
    var (name, args) = _invocation(expr) ?? (null, null);
    if (name == null || args == null) {
      refuse(
        expr.offset,
        'expression',
        'a node is a Frame, Text, Shape or Ext constructor call',
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
    switch (name) {
      case 'Frame':
        var node = FrameNode(_positionalString(positional, 0, args) ?? '');
        _applyCommon(node, named);
        _take(named, 'layout', (e) {
          var v = _enum(e, 'NodeLayout', NodeLayout.values.map((v) => v.name));
          if (v != null) {
            node.layout = NodeLayout.values.byName(v);
          }
        });
        _take(named, 'gap', (e) => node.gap = _double(e) ?? node.gap);
        _take(named, 'padding', (e) => node.padding = _double(e) ?? 0);
        _take(named, 'mainAlign', (e) {
          var v = _enum(
            e,
            'MainAxisAlignment',
            MainAxisAlignment.values.map((v) => v.name),
          );
          if (v != null) node.mainAlign = MainAxisAlignment.values.byName(v);
        });
        _take(named, 'crossAlign', (e) {
          var v = _enum(
            e,
            'CrossAxisAlignment',
            CrossAxisAlignment.values.map((v) => v.name),
          );
          if (v != null) node.crossAlign = CrossAxisAlignment.values.byName(v);
        });
        _take(named, 'children', (e) {
          if (e is! ListLiteral) {
            refuse(e.offset, 'children', 'children takes a list literal');
            return;
          }
          for (var element in e.elements) {
            if (element is! Expression) {
              refuse(
                element.offset,
                _elementKind(element),
                'a scene lists its children one by one — the editor cannot '
                'read a computed list',
              );
              continue;
            }
            var child = _node(element);
            if (child != null) node.children.add(child);
          }
        });
        _refuseRest('Frame', named);
        return _named(node, positional, args);
      case 'Text':
        var node = TextNode(
          _positionalString(positional, 0, args) ?? '',
          _positionalString(positional, 1, args) ?? '',
        );
        _applyCommon(node, named);
        _take(
          named,
          'fontSize',
          (e) => node.fontSize = _double(e) ?? node.fontSize,
        );
        _take(named, 'weight', (e) {
          var v = _enum(e, 'FontWeight', [
            for (var i = 1; i <= 9; i++) 'w${i * 100}',
          ]);
          if (v != null) {
            node.weight =
                FontWeight.values[int.parse(v.substring(1)) ~/ 100 - 1];
          }
        });
        _take(named, 'color', (e) => node.color = _colorOf(e) ?? node.color);
        _refuseRest('Text', named);
        return _named(node, positional, args, positionalCount: 2);
      case 'Shape':
        var node = ShapeNode(_positionalString(positional, 0, args) ?? '');
        _applyCommon(node, named);
        _take(named, 'circle', (e) => node.circle = _bool(e) ?? false);
        _refuseRest('Shape', named);
        return _named(node, positional, args);
      case 'Ext':
        var node = ExternalNode(
          _positionalString(positional, 0, args) ?? '',
          _positionalString(positional, 1, args) ?? '',
        );
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
            if (key != null) node.args[key] = value;
          }
        });
        _refuseRest('Ext', named);
        return _named(node, positional, args, positionalCount: 2);
      default:
        refuse(
          expr.offset,
          'unknown node',
          '"$name" is not a scene node — Frame, Text, Shape or Ext',
        );
        return null;
    }
  }

  /// Registers the node's name (identity must be unique) and refuses excess
  /// positional arguments.
  SceneNode _named(
    SceneNode node,
    List<Expression> positional,
    ArgumentList args, {
    int positionalCount = 1,
  }) {
    if (positional.length > positionalCount) {
      refuse(
        positional[positionalCount].offset,
        'positional argument',
        'this node takes $positionalCount positional argument(s)',
      );
    }
    if (node.name.isNotEmpty && !_names.add(node.name)) {
      refuse(
        args.offset,
        'duplicate name',
        '"${node.name}" is already the name of another node — a name is '
            "the node's identity and must be unique",
      );
    }
    return node;
  }

  void _applyCommon(SceneNode n, Map<String, Expression> named) {
    _take(named, 'x', (e) => n.x = _double(e) ?? 0);
    _take(named, 'y', (e) => n.y = _double(e) ?? 0);
    _take(named, 'width', (e) => n.width = _double(e));
    _take(named, 'height', (e) => n.height = _double(e));
    _take(named, 'fill', (e) => n.fill = _colorOf(e));
    _take(named, 'corner', (e) => n.cornerRadius = _double(e) ?? 0);
    _take(named, 'opacity', (e) => n.opacity = _double(e) ?? 1);
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

  String? _positionalString(
    List<Expression> positional,
    int i,
    ArgumentList args,
  ) {
    if (i >= positional.length) {
      refuse(args.offset, 'missing argument', 'a name string is required here');
      return null;
    }
    return _string(positional[i]);
  }

  // -- value parsers, each refusing with the construct it actually found --

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

  Color? _colorOf(Expression e) {
    if (_invocation(e) case ('Color', var args)
        when args.arguments.length == 1) {
      var v = args.arguments.single;
      if (v is IntegerLiteral && v.value != null) return Color(v.value!);
    }
    refuse(e.offset, _kind(e), 'expected a color, spelled Color(0xAARRGGBB)');
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
      _ => () {
        refuse(e.offset, _kind(e), 'expected a number, string or bool literal');
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
