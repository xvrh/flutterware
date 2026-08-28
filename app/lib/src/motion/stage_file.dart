import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Reading and writing `<name>.stage.dart` — the draft scene the editor owns.
///
/// This is the tier-2 round trip at its smallest: a class declaration is not
/// involved, the grammar is one `const` assignment holding constructor calls,
/// literals and enum values, and the invariant that matters is
/// `emit(parse(f)) == f` for every file this accepts.
///
/// **Refuses rather than approximates.** Anything outside the grammar comes
/// back as a [StageParseFailure] naming the offset, and the caller declines to
/// write. That is stricter than it needs to be today and exactly as strict as
/// it will need to be once a person has hand-edited one of these.
sealed class StageParseResult {
  const StageParseResult();
}

class StageParseFailure extends StageParseResult {
  const StageParseFailure(this.message, {this.offset});

  final String message;
  final int? offset;

  @override
  String toString() => offset == null ? message : '$message (at $offset)';
}

class StageFile extends StageParseResult {
  const StageFile({
    required this.name,
    required this.width,
    required this.height,
    required this.background,
    required this.elements,
  });

  /// The `const <name> = MotionStage(...)` identifier.
  final String name;
  final double width;
  final double height;

  /// Source as written — `Color(0xFFF6F7F9)` — because a colour has one
  /// spelling in this file and re-deriving it would churn the diff.
  final String? background;

  final List<StageElementModel> elements;

  StageFile withElement(StageElementModel element) => StageFile(
    name: name,
    width: width,
    height: height,
    background: background,
    elements: [...elements, element],
  );

  bool hasTarget(String target) => elements.any((e) => e.target == target);
}

class StageElementModel {
  const StageElementModel({
    required this.target,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.kind = 'box',
    this.label,
    this.tint,
    this.radius,
  });

  final String target;
  final String kind;
  final double x;
  final double y;
  final double width;
  final double height;
  final String? label;

  /// Source as written, as with [StageFile.background].
  final String? tint;
  final double? radius;
}

/// Parses a stage file, or says why it could not.
StageParseResult parseStageFile(String source) {
  var parsed = parseString(content: source, throwIfDiagnostics: false);
  if (parsed.errors.isNotEmpty) {
    var first = parsed.errors.first;
    return StageParseFailure(
      'the file does not parse as Dart: ${first.message}',
      offset: first.offset,
    );
  }

  var finder = _StageFinder();
  parsed.unit.accept(finder);
  var declaration = finder.found;
  if (declaration == null) {
    return const StageParseFailure(
      'no `const <name> = MotionStage(...)` in this file',
    );
  }

  var arguments = _callArguments(declaration.initializer, 'MotionStage');
  if (arguments == null) {
    return const StageParseFailure('the initializer is not a MotionStage(...)');
  }
  var width = _number(arguments['width']);
  var height = _number(arguments['height']);
  if (width == null || height == null) {
    return const StageParseFailure(
      'MotionStage needs literal `width` and `height`',
    );
  }

  var elementsNode = arguments['elements'];
  if (elementsNode is! ListLiteral) {
    return const StageParseFailure('`elements` is not a list literal');
  }

  var elements = <StageElementModel>[];
  for (var item in elementsNode.elements) {
    var fields = item is Expression
        ? _callArguments(item, 'StageElement')
        : null;
    if (fields == null) {
      return StageParseFailure(
        'every element must be a StageElement(...) — found '
        '`${item.toSource()}`',
        offset: item.offset,
      );
    }
    var parsedElement = _element(fields, item.offset);
    switch (parsedElement) {
      case StageParseFailure failure:
        return failure;
      case StageElementModel model:
        elements.add(model);
    }
  }

  return StageFile(
    name: declaration.name.lexeme,
    width: width,
    height: height,
    background: arguments['background']?.toSource(),
    elements: elements,
  );
}

Object _element(Map<String, Expression> arguments, int offset) {
  var target = _string(arguments['target']);
  if (target == null) {
    return StageParseFailure(
      'a StageElement needs a literal `target`',
      offset: offset,
    );
  }
  var x = _number(arguments['x']);
  var y = _number(arguments['y']);
  var width = _number(arguments['width']);
  var height = _number(arguments['height']);
  if (x == null || y == null || width == null || height == null) {
    return StageParseFailure(
      'StageElement `$target` needs literal x, y, width and height',
      offset: offset,
    );
  }
  var kind = switch (arguments['kind']) {
    PrefixedIdentifier id when id.prefix.name == 'StageKind' =>
      id.identifier.name,
    null => 'box',
    var other => other.toSource(),
  };
  return StageElementModel(
    target: target,
    kind: kind,
    x: x,
    y: y,
    width: width,
    height: height,
    label: _string(arguments['label']),
    tint: arguments['tint']?.toSource(),
    radius: _number(arguments['radius']),
  );
}

/// The named arguments of `Name(...)`, whichever way the parser saw it.
///
/// **Without resolution, `MotionStage(...)` is a `MethodInvocation`** — the
/// parser cannot tell a constructor call from a function call, and only a
/// leading `const` or `new` makes it an `InstanceCreationExpression`. Both
/// spellings are in this file's grammar and both mean the same thing, so every
/// call goes through here. Cost one red test to find, and it is the same shape
/// `values_file.dart` already carries for `Seg`.
Map<String, Expression>? _callArguments(Expression? node, String name) {
  var arguments = switch (node) {
    MethodInvocation(methodName: Identifier(name: var called))
        when called == name =>
      node.argumentList,
    InstanceCreationExpression() =>
      node.constructorName.type.name.lexeme == name ? node.argumentList : null,
    _ => null,
  };
  if (arguments == null) return null;
  return {
    for (var argument in arguments.arguments)
      if (argument is NamedArgument)
        argument.name.lexeme: argument.argumentExpression,
  };
}

double? _number(Expression? node) => switch (node) {
  IntegerLiteral(:var value?) => value.toDouble(),
  DoubleLiteral(:var value) => value,
  PrefixExpression(operator: var op, operand: var operand)
      when op.lexeme == '-' =>
    switch (_number(operand)) {
      var value? => -value,
      _ => null,
    },
  _ => null,
};

String? _string(Expression? node) => switch (node) {
  SimpleStringLiteral(:var value) => value,
  _ => null,
};

class _StageFinder extends RecursiveAstVisitor<void> {
  VariableDeclaration? found;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (found != null) return;
    if (_callArguments(node.initializer, 'MotionStage') != null) {
      found = node;
    }
    super.visitVariableDeclaration(node);
  }
}

/// Emits a whole stage file.
///
/// Whole-file emit, which is safe here for the reason it is safe for the values
/// file: the tool owns this file and nothing of yours is in it.
String emitStageFile(StageFile stage, {String? header}) {
  var buffer = StringBuffer();
  // Only when a colour is actually written. A generated file that carries an
  // unused import earns a lint the moment it is created, and the person who
  // has to delete it did not write it.
  var needsColor =
      stage.background != null || stage.elements.any((e) => e.tint != null);
  if (needsColor) {
    buffer.writeln("import 'package:flutter/material.dart' show Color;");
  }
  buffer.writeln("import 'package:flutterware/motion.dart';");
  buffer.writeln();
  if (header != null) {
    for (var line in header.trimRight().split('\n')) {
      buffer.writeln(line.isEmpty ? '///' : '/// $line');
    }
  }
  buffer.writeln('const ${stage.name} = MotionStage(');
  buffer.writeln('  width: ${_emitNumber(stage.width)},');
  buffer.writeln('  height: ${_emitNumber(stage.height)},');
  if (stage.background case var background?) {
    buffer.writeln('  background: $background,');
  }
  buffer.writeln('  elements: [');
  for (var element in stage.elements) {
    buffer.writeln('    StageElement(');
    buffer.writeln("      target: '${element.target}',");
    if (element.kind != 'box') {
      buffer.writeln('      kind: StageKind.${element.kind},');
    }
    if (element.label case var label?) {
      buffer.writeln("      label: '$label',");
    }
    buffer.writeln('      x: ${_emitNumber(element.x)},');
    buffer.writeln('      y: ${_emitNumber(element.y)},');
    buffer.writeln('      width: ${_emitNumber(element.width)},');
    buffer.writeln('      height: ${_emitNumber(element.height)},');
    if (element.tint case var tint?) {
      buffer.writeln('      tint: $tint,');
    }
    if (element.radius case var radius?) {
      buffer.writeln('      radius: ${_emitNumber(radius)},');
    }
    buffer.writeln('    ),');
  }
  buffer.writeln('  ],');
  buffer.writeln(');');
  return buffer.toString();
}

/// Whole numbers as `28`, not `28.0` — the same rule the values file keeps, and
/// for the same reason: an emitter that churned every literal would rewrite a
/// hand-written file on first touch.
String _emitNumber(double value) =>
    value == value.roundToDouble() && value.abs() < 1e15
    ? '${value.toInt()}'
    : '$value';
