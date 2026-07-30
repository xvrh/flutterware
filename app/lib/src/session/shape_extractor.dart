import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

/// Reads the shape of every action's result straight out of the source.
///
/// **Build-time only.** This resolves a package with the analyzer, which costs
/// seconds and pulls in a compiler — `tool/generate_capabilities.dart` runs it
/// and writes the answers into `action_shapes.generated.dart`, which is what
/// `fw` and the MCP server read. Nothing on a request path imports this.
///
/// How it works, and the one thing that was not obvious: an action declares
/// `returns: CatalogEntriesResult`, and a bare class name in an expression
/// position is a **`TypeLiteral`**, not a `SimpleIdentifier`. The class element
/// hangs off `literal.type.element`. Everything else is walking fields.
class ShapeExtractor {
  ShapeExtractor({required this.packageRoots, String? sdkPath})
    : sdkPath = sdkPath ?? findDartSdk();

  /// The packages whose sources are read — resolution needs whole packages,
  /// not just the files named.
  ///
  /// Plural because the result classes are not all in one: the plugins declare
  /// their own, and `Artifact` — the most returned of all — lives in
  /// `package:flutterware` beside the other pure-data plugin types.
  final List<String> packageRoots;

  /// Where the Dart SDK is.
  ///
  /// Passed rather than inferred, because the analyzer infers it from
  /// `Platform.resolvedExecutable` and under `flutter test` that is
  /// `flutter_tester` — from which it deduces the Flutter root and then fails
  /// looking for a file that lives somewhere else entirely. Null lets it try
  /// anyway, which is right when nothing better is known.
  final String? sdkPath;

  /// The `dart-sdk` directory above whatever is running us.
  ///
  /// Works from `dart run` (`<dart-sdk>/bin/dart`) and from `flutter test`
  /// (`<flutter>/bin/cache/artifacts/engine/<host>/flutter_tester`) — in both
  /// cases a `dart-sdk` directory sits on the way up.
  static String? findDartSdk() {
    var directory = File(Platform.resolvedExecutable).parent;
    while (true) {
      var candidate = Directory(p.join(directory.path, 'dart-sdk'));
      if (candidate.existsSync()) return candidate.path;
      var parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  /// Shapes for every result class reachable from an action's `returns:`, by
  /// class name.
  ///
  /// Keyed by name rather than by action, because a shape belongs to the type:
  /// two actions returning the same class describe it once, and the runtime
  /// looks it up with `PluginAction.returnsName`.
  Future<Map<String, ResultShape>> extract(List<String> sources) async {
    var collection = AnalysisContextCollection(
      // Normalised: the analyzer rejects a path with a `..` in it, and the
      // sibling package is most naturally written as one.
      includedPaths: [for (var root in packageRoots) p.normalize(root)],
      sdkPath: sdkPath,
    );
    var shapes = <String, ResultShape>{};
    var units = <ResolvedUnitResult>[];

    for (var source in sources) {
      var path = p.normalize(source);
      var resolved = await collection
          .contextFor(path)
          .currentSession
          .getResolvedUnit(path);
      if (resolved is! ResolvedUnitResult) {
        throw StateError('could not resolve $source: $resolved');
      }
      units.add(resolved);
    }

    // Two passes, and the order matters. A hand-written `toJson` is described
    // by reading its map literal, which needs the *syntax* — and the class may
    // be reached as a field of something else long before its own file comes
    // up. So every map is collected before any shape is built.
    for (var unit in units) {
      var maps = _MapLiteralFinder();
      unit.unit.accept(maps);
      _handWritten.addAll(maps.byClassName);
    }

    for (var unit in units) {
      var finder = _ReturnsFinder();
      unit.unit.accept(finder);
      for (var type in finder.returnTypes) {
        _shapeOf(type, shapes, seen: {});
      }
    }
    return shapes;
  }

  /// `toJson` map literals, by the class that wrote one.
  final _handWritten = <String, _HandWrittenJson>{};

  /// Adds [type]'s shape to [shapes], and every nested one it reaches.
  ResultShape? _shapeOf(
    ClassElement type,
    Map<String, ResultShape> shapes, {
    required Set<String> seen,
  }) {
    var name = type.name;
    if (name == null) return null;
    if (shapes.containsKey(name)) return shapes[name];
    // A class that contains itself is legal; a shape tree that does is not.
    if (!seen.add(name)) return null;

    // A hand-written `toJson` is described by what it writes rather than by
    // what the class holds. Reading the fields there would publish
    // `address: Address` for `Artifact`, which sends a string — the exact lie
    // the `@JsonSerializable` rule exists to prevent. Reading the map says
    // `address: String`, which is true.
    if (_handWritten[name] case var written? when !_isJsonSerializable(type)) {
      var entries = [
        for (var entry in written.entries)
          ResultField(
            entry.key,
            _withoutNullability(entry.type),
            optional: entry.optional,
            doc: entry.doc,
            shape: switch (entry.nested) {
              var nested? => _shapeOf(nested, shapes, seen: seen),
              null => null,
            },
          ),
      ];
      seen.remove(name);
      return shapes[name] = ResultShape(name, entries);
    }

    if (!_isJsonSerializable(type)) {
      seen.remove(name);
      return null;
    }

    var fields = <ResultField>[];
    for (var field in type.fields) {
      if (field.isStatic || field.isPrivate) continue;
      var nested = _walkable(field.type);
      fields.add(
        ResultField(
          _wireName(field),
          _withoutNullability(field.type.getDisplayString()),
          optional: field.type.nullabilitySuffix == NullabilitySuffix.question,
          doc: _summaryDoc(field),
          shape: nested == null ? null : _shapeOf(nested, shapes, seen: seen),
        ),
      );
    }

    seen.remove(name);
    return shapes[name] = ResultShape(name, fields);
  }

  /// The class behind a field's type, when we can honestly claim to know its
  /// wire shape — following `List<T>` into `T`.
  ///
  /// Two ways to qualify, and both describe what is *sent*. A
  /// `@JsonSerializable` class generates its keys from its fields, so reading
  /// the fields is honest. A class with a hand-written `toJson` is read from
  /// that method's map literal instead — `Artifact` turns an `Address` into a
  /// string, and only the map says so. A class with neither gets nothing,
  /// which is still better than a shape nobody sends.
  ClassElement? _walkable(DartType type) {
    if (type is! InterfaceType) return null;
    if (type.element.name == 'List' && type.typeArguments.isNotEmpty) {
      return _walkable(type.typeArguments.first);
    }
    var element = type.element;
    if (element is! ClassElement) return null;
    if ('${element.library.uri}'.startsWith('dart:')) return null;
    return element;
  }

  /// The trailing `?` only — `Map<String, Object?>` keeps its inner one, which
  /// `replaceAll` used to eat.
  static String _withoutNullability(String type) =>
      type.endsWith('?') ? type.substring(0, type.length - 1) : type;

  static bool _isJsonSerializable(ClassElement element) {
    for (var annotation in element.metadata.annotations) {
      if (annotation.computeConstantValue()?.type?.element?.name ==
          'JsonSerializable') {
        return true;
      }
    }
    return false;
  }

  /// `@JsonKey(name: 'x')` when present — the key that is really sent.
  static String _wireName(FieldElement field) {
    for (var annotation in field.metadata.annotations) {
      var value = annotation.computeConstantValue();
      if (value?.type?.element?.name != 'JsonKey') continue;
      if (value?.getField('name')?.toStringValue() case var name?) return name;
    }
    return field.name ?? '';
  }

  /// The first *sentence* of a field's dartdoc — what the field means, which
  /// its type cannot say.
  ///
  /// A sentence rather than a line, because dartdoc wraps at 80 and a schema
  /// that reads "Present only when `--knobs` asked for them: reading a knob
  /// costs a" is worse than one that says nothing. Anything past the first
  /// sentence belongs in the source.
  static String? _summaryDoc(FieldElement field) {
    var comment = field.documentationComment;
    if (comment == null) return null;

    var paragraph = <String>[];
    for (var line in comment.split('\n')) {
      var text = line.replaceFirst(RegExp(r'^\s*///\s?'), '').trimRight();
      // The first blank line ends the summary paragraph, as dartdoc has it.
      if (text.trim().isEmpty) {
        if (paragraph.isNotEmpty) break;
        continue;
      }
      paragraph.add(text.trim());
    }
    if (paragraph.isEmpty) return null;

    var summary = paragraph.join(' ');
    // A full stop that ends a sentence, not one inside `a.b` or an ellipsis.
    var end = RegExp(r'\.(\s|$)').firstMatch(summary);
    return end == null ? summary : summary.substring(0, end.start + 1);
  }
}

/// Collects the classes named by every `PluginAction(..., returns: X)`.
class _ReturnsFinder extends RecursiveAstVisitor<void> {
  final returnTypes = <ClassElement>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    super.visitInstanceCreationExpression(node);
    var created = node.constructorName.type.element;
    if (created is! ClassElement || created.name != 'PluginAction') return;

    for (var argument in node.argumentList.arguments) {
      if (argument is! NamedArgument) continue;
      if (argument.name.lexeme != 'returns') continue;
      // A bare class name in an expression position is a `TypeLiteral`
      // wrapping a `NamedType`, not a `SimpleIdentifier`.
      if (argument.argumentExpression case TypeLiteral literal) {
        if (literal.type.element case ClassElement element) {
          returnTypes.add(element);
        }
      }
    }
  }
}

/// One hand-written `toJson`, read as what it writes.
class _HandWrittenJson {
  _HandWrittenJson(this.entries);

  final List<_JsonEntry> entries;
}

class _JsonEntry {
  _JsonEntry({
    required this.key,
    required this.type,
    required this.optional,
    this.doc,
    this.nested,
  });

  final String key;
  final String type;

  /// True when the entry sits behind an `if` in the literal — which is what
  /// `if (path != null) 'path': path` means on the wire.
  final bool optional;
  final String? doc;
  final ClassElement? nested;
}

/// Collects `Map<String, Object?> toJson() => {…}` bodies, by class.
///
/// Only a **map literal** counts. A `toJson` that builds its map some other way
/// is not described rather than guessed at, which is the same standard the
/// `@JsonSerializable` rule applies: publish what is provably sent, or publish
/// nothing.
///
/// Reached through `MethodDeclaration` and the element model rather than
/// through `ClassDeclaration`, whose shape the analyzer rearranged — a method
/// knows which class it belongs to, and asking it is both shorter and stable
/// across that.
class _MapLiteralFinder extends RecursiveAstVisitor<void> {
  final byClassName = <String, _HandWrittenJson>{};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    super.visitMethodDeclaration(node);
    if (node.name.lexeme != 'toJson') return;
    var owner = node.declaredFragment?.element.enclosingElement;
    if (owner is! ClassElement) return;
    var name = owner.name;
    if (name == null) return;

    var literal = _literalOf(node.body);
    if (literal == null) return;

    var entries = <_JsonEntry>[];
    for (var element in literal.elements) {
      var entry = _entryOf(element, optional: false);
      if (entry != null) entries.add(entry);
    }
    if (entries.isNotEmpty) byClassName[name] = _HandWrittenJson(entries);
  }

  /// The map literal a `toJson` returns, from either body form.
  static SetOrMapLiteral? _literalOf(FunctionBody body) => switch (body) {
    ExpressionFunctionBody(expression: SetOrMapLiteral literal) => literal,
    BlockFunctionBody(:var block) => switch (block.statements) {
      [ReturnStatement(expression: SetOrMapLiteral literal)] => literal,
      _ => null,
    },
    _ => null,
  };

  static _JsonEntry? _entryOf(
    CollectionElement element, {
    required bool optional,
  }) => switch (element) {
    // `if (path != null) 'path': path` — the condition is what makes the key
    // optional, and the entry under it is the one that gets written.
    IfElement(:var thenElement) => _entryOf(thenElement, optional: true),
    MapLiteralEntry(key: SimpleStringLiteral key, :var value) => _JsonEntry(
      key: key.value,
      type: value.staticType?.getDisplayString() ?? 'Object',
      optional:
          optional ||
          value.staticType?.nullabilitySuffix == NullabilitySuffix.question,
      doc: _docOf(value),
      nested: _walkableType(value.staticType),
    ),
    _ => null,
  };

  /// The dartdoc of the field the value reads, when it reads one.
  ///
  /// `'kind': kind` names a field directly; `'address': address.toString()`
  /// names one and then converts it. Both should carry the field's own
  /// documentation, since that is what the reader wants explained.
  static String? _docOf(Expression value) {
    var finder = _FirstFieldFinder();
    value.accept(finder);
    var field = finder.field;
    return field == null ? null : ShapeExtractor._summaryDoc(field);
  }

  static ClassElement? _walkableType(DartType? type) {
    if (type is! InterfaceType) return null;
    if (type.element.name == 'List' && type.typeArguments.isNotEmpty) {
      return _walkableType(type.typeArguments.first);
    }
    var element = type.element;
    if (element is! ClassElement) return null;
    if ('${element.library.uri}'.startsWith('dart:')) return null;
    return element;
  }
}

/// The first identifier in an expression that resolves to a field.
class _FirstFieldFinder extends RecursiveAstVisitor<void> {
  FieldElement? field;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (field != null) return;
    var element = node.element;
    if (element is FieldElement) {
      field = element;
      return;
    }
    // A field read resolves to its implicit getter, not to the field.
    if (element is GetterElement) {
      var variable = element.variable;
      if (variable is FieldElement) field = variable;
    }
  }
}
