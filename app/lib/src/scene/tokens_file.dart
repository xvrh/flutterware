// The app's declaration of the values its scenes share, read without
// resolving anything.
//
// The same shape as the externals file, for the same reason: the editor
// never compiles the app, so a token's name, type and value are told to it
// here, in one list the app writes once — and everything downstream follows.
// The generated `SceneTokens` class a scene file spells `tokens.brand`
// against, the value the canvas renders for it, the picker the inspector
// offers, and the refusal for a token nobody declared.
//
// The tool only ever READS this file. That is what makes a token different
// from a parameter: a parameter's default moves when a bound property is
// edited, because the file is the tool's; a token is shared by every scene
// of the package and written by hand, so a property edited off its token
// detaches instead.
//
// A token typed anything but the four value types is OPAQUE: the editor
// records its name and its type and never its value — `Token<ButtonStyle>
// ('cta', FilledButton.styleFrom(…))` is the app's object, reachable only
// by an external widget's argument, and only the app that compiled this
// file can hand it over. The file's own imports are kept for the generated
// class, which has to spell `ButtonStyle` too.
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutterware/scene_authoring.dart';

import 'scene_file.dart';

/// The symbol the declaration list must be called.
const sceneTokensSymbol = 'sceneTokens';

/// Where a package declares its tokens — beside its externals.
const sceneTokensFileName = 'scene_tokens.dart';

/// What the generated class is called, and therefore the TYPE a scene's
/// tokens formal is recognised by: `class Banner({final SceneTokens tokens =
/// const SceneTokens()})`. The formal's name is the author's own.
const sceneTokensClassName = 'SceneTokens';

/// What a read of a declaration file produced.
class TokensParse {
  TokensParse(this.tokens, this.refusals, [this.imports = const []]);

  final List<SceneTokenDecl> tokens;
  final List<SceneRefusal> refusals;

  /// The file's imports other than the authoring one, verbatim — what an
  /// opaque token's type is spelled with, so the generated class imports the
  /// same.
  final List<String> imports;

  bool get ok => refusals.isEmpty;
}

/// The same declarations, as the tool describes them — for a demo or a test
/// that already holds the real objects.
List<SceneTokenDecl> describeTokens(List<Token<Object>> tokens) => [
  for (var t in tokens)
    SceneTokenDecl(
      t.name,
      switch (t.value) {
        String() => SceneParamKind.string,
        bool() => SceneParamKind.bool,
        SceneColor() => SceneParamKind.color,
        num() => SceneParamKind.number,
        var v => throw ArgumentError(
          'a token is a String, double, bool or SceneColor — '
          '"${t.name}" is a ${v.runtimeType}',
        ),
      },
      _number(t.value),
      modes: {for (var e in t.modes.entries) e.key: _number(e.value)},
    ),
];

Object _number(Object v) => v is num ? v.toDouble() : v;

/// The kinds a token may have, by the type argument the declaration spells.
const _tokenKinds = {
  'double': SceneParamKind.number,
  'String': SceneParamKind.string,
  'bool': SceneParamKind.bool,
  'SceneColor': SceneParamKind.color,
};

/// Reads `final sceneTokens = [Token<SceneColor>('brand', SceneColor(…)), …]`.
///
/// Everything outside that shape is refused with a line number rather than
/// skipped, the externals rule: a token silently half-read is a scene that
/// silently loses a colour.
TokensParse parseTokensFile(String source) {
  var refusals = <SceneRefusal>[];
  var lines = source.split('\n');
  void refuse(int offset, String construct, String message) {
    var line = 1;
    var seen = 0;
    for (var l in lines) {
      if (offset <= seen + l.length) break;
      seen += l.length + 1;
      line++;
    }
    refusals.add(SceneRefusal(offset, line, construct, message));
  }

  var result = parseString(content: source, throwIfDiagnostics: false);
  for (var error in result.errors) {
    refuse(error.offset, 'syntax error', error.message);
  }
  if (refusals.isNotEmpty) return TokensParse(const [], refusals);
  var imports = declarationImports(result.unit, source);

  ListLiteral? list;
  for (var decl in result.unit.declarations) {
    if (decl is! TopLevelVariableDeclaration) continue;
    for (var v in decl.variables.variables) {
      if (v.name.lexeme != sceneTokensSymbol) continue;
      if (v.initializer case ListLiteral l) {
        list = l;
      } else {
        refuse(
          v.offset,
          'declaration',
          '$sceneTokensSymbol is a list literal of Token<…>(…)',
        );
      }
    }
  }
  if (list == null) {
    if (refusals.isEmpty) {
      refuse(
        0,
        'no declarations',
        'a token file holds `final $sceneTokensSymbol = '
            "[Token<SceneColor>('brand', SceneColor(0xFF…)), …]`",
      );
    }
    return TokensParse(const [], refusals);
  }

  var tokens = <SceneTokenDecl>[];
  var names = <String>{};
  for (var element in list.elements) {
    if (element is! Expression) {
      refuse(element.offset, 'element', 'expected a Token<…>(…)');
      continue;
    }
    var decl = _token(element, refuse);
    if (decl == null) continue;
    if (!names.add(decl.name)) {
      refuse(
        element.offset,
        'duplicate name',
        '"${decl.name}" is declared twice',
      );
      continue;
    }
    tokens.add(decl);
  }
  return TokensParse(tokens, refusals, imports);
}

/// A declaration file's imports other than the authoring one, as written.
List<String> declarationImports(CompilationUnit unit, String source) => [
  for (var d in unit.directives)
    if (d is ImportDirective && d.uri.stringValue != sceneAuthoringUri)
      source.substring(d.offset, d.end),
];

SceneTokenDecl? _token(
  Expression e,
  void Function(int, String, String) refuse,
) {
  String? typeName;
  ArgumentList? args;
  switch (e) {
    case InstanceCreationExpression(:var constructorName, :var argumentList)
        when constructorName.type.name.lexeme == 'Token':
      typeName = _typeArgument(constructorName.type.typeArguments);
      args = argumentList;
    case MethodInvocation(
          :var methodName,
          :var typeArguments,
          :var argumentList,
        )
        when methodName.name == 'Token':
      typeName = _typeArgument(typeArguments);
      args = argumentList;
    default:
  }
  if (args == null) {
    refuse(e.offset, 'element', 'expected a Token<…>(…)');
    return null;
  }
  if (typeName == null) {
    refuse(
      e.offset,
      'token type',
      'a token is typed by its type argument — '
          "Token<SceneColor>('brand', SceneColor(0xFF…)) for a value the "
          "editor renders, Token<ButtonStyle>('cta', …) for one it only names",
    );
    return null;
  }
  var positional = [
    for (var a in args.arguments)
      if (a is! NamedArgument) a,
  ];
  var named = [
    for (var a in args.arguments)
      if (a is NamedArgument) a,
  ];
  if (positional.length != 2 || named.any((a) => a.name.lexeme != 'modes')) {
    refuse(
      e.offset,
      'arguments',
      "a token is Token<double>('radius', 16) — a name and its value, "
          "then modes: {'dark': …} if it differs by mode",
    );
    return null;
  }
  var nameArg = positional[0].argumentExpression;
  if (nameArg is! SimpleStringLiteral || !isValidNodeName(nameArg.value)) {
    refuse(nameArg.offset, 'token name', 'a token name is an identifier');
    return null;
  }
  var kind = _tokenKinds[typeName];
  // Not a value type: the app's own object. Named, typed, never read.
  if (kind == null) {
    if (named.isNotEmpty) {
      refuse(
        named.first.offset,
        'modes',
        "a $typeName token is the app's own object and has no modes here — "
            'the app picks one where it builds it',
      );
      return null;
    }
    return SceneTokenDecl.opaque(nameArg.value, typeName);
  }
  var value = _value(positional[1].argumentExpression, kind);
  if (value == null) {
    refuse(
      positional[1].offset,
      'token value',
      "a $typeName token's value is a $typeName literal",
    );
    return null;
  }
  var modes = <String, Object>{};
  for (var arg in named) {
    var map = arg.argumentExpression;
    if (map is! SetOrMapLiteral) {
      refuse(map.offset, 'modes', "modes is a map — modes: {'dark': …}");
      return null;
    }
    for (var entry in map.elements) {
      if (entry is! MapLiteralEntry) {
        refuse(entry.offset, 'modes', "modes is a map — modes: {'dark': …}");
        return null;
      }
      var key = entry.key;
      if (key is! SimpleStringLiteral || !isValidNodeName(key.value)) {
        refuse(key.offset, 'mode name', 'a mode name is an identifier');
        return null;
      }
      var v = _value(entry.value, kind);
      if (v == null) {
        refuse(
          entry.value.offset,
          'mode value',
          "a $typeName token's value is a $typeName literal in every mode",
        );
        return null;
      }
      modes[key.value] = v;
    }
  }
  return SceneTokenDecl(nameArg.value, kind, value, modes: modes);
}

Object? _value(Expression e, SceneParamKind kind) {
  var inner = e;
  var negate = false;
  if (inner is PrefixExpression && inner.operator.lexeme == '-') {
    negate = true;
    inner = inner.operand;
  }
  switch ((kind, inner)) {
    case (SceneParamKind.string, SimpleStringLiteral(:var value)):
      return value;
    case (SceneParamKind.bool, BooleanLiteral(:var value)):
      return value;
    case (SceneParamKind.number, IntegerLiteral(:var value?)):
      return (negate ? -value : value).toDouble();
    case (SceneParamKind.number, DoubleLiteral(:var value)):
      return negate ? -value : value;
    case (SceneParamKind.color, _):
      ArgumentList? args;
      switch (inner) {
        case InstanceCreationExpression(:var constructorName, :var argumentList)
            when constructorName.type.name.lexeme == 'SceneColor':
          args = argumentList;
        case MethodInvocation(:var methodName, :var argumentList)
            when methodName.name == 'SceneColor':
          args = argumentList;
        default:
      }
      if (args != null && args.arguments.length == 1) {
        if (args.arguments.single.argumentExpression case IntegerLiteral(
          :var value?,
        )) {
          return SceneColor(value);
        }
      }
      return null;
    default:
      return null;
  }
}

String? _typeArgument(TypeArgumentList? types) =>
    types != null && types.arguments.length == 1
    ? types.arguments.single.toSource()
    : null;
