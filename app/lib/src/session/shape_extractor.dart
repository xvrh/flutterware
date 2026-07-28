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
  ShapeExtractor({required this.packageRoot, String? sdkPath})
    : sdkPath = sdkPath ?? findDartSdk();

  /// The package whose plugin sources are read — resolution needs the whole
  /// package, not just the files named.
  final String packageRoot;

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
      includedPaths: [packageRoot],
      sdkPath: sdkPath,
    );
    var shapes = <String, ResultShape>{};

    for (var source in sources) {
      var resolved = await collection
          .contextFor(source)
          .currentSession
          .getResolvedUnit(source);
      if (resolved is! ResolvedUnitResult) {
        throw StateError('could not resolve $source: $resolved');
      }

      var finder = _ReturnsFinder();
      resolved.unit.accept(finder);
      for (var type in finder.returnTypes) {
        _shapeOf(type, shapes, seen: {});
      }
    }
    return shapes;
  }

  /// Adds [type]'s shape to [shapes], and every nested one it reaches.
  ResultShape? _shapeOf(
    ClassElement type,
    Map<String, ResultShape> shapes, {
    required Set<String> seen,
  }) {
    var name = type.name;
    if (name == null) return null;
    if (shapes.containsKey(name)) return shapes[name];
    // The same rule at the top of the tree as inside it. Without this check
    // here, `Artifact` — whose `toJson` is hand-written and turns an `Address`
    // into a string — published `address: Address`, which is the exact lie the
    // rule exists to prevent.
    if (!_isJsonSerializable(type)) return null;
    // A class that contains itself is legal; a shape tree that does is not.
    if (!seen.add(name)) return null;

    var fields = <ResultField>[];
    for (var field in type.fields) {
      if (field.isStatic || field.isPrivate) continue;
      var nested = _walkable(field.type);
      fields.add(
        ResultField(
          _wireName(field),
          field.type.getDisplayString().replaceAll('?', ''),
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
  /// **Only `@JsonSerializable` classes qualify.** There the keys are generated
  /// from the fields, so reading the fields describes what is actually sent.
  /// A class with a hand-written `toJson` may map a field to anything —
  /// `Artifact` turns an `Address` into a string — and walking its fields would
  /// publish a shape nobody sends, which is worse than publishing none.
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
