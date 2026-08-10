import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// A tuned value: a number or a colour, and nothing else.
///
/// The same two kinds the runtime has, for the same reason — a third here would
/// be a third editor in the panel.
sealed class MotionLiteral {
  const MotionLiteral();

  /// The Dart source for this value, as the file spells it.
  String get source;
}

class MotionNumber extends MotionLiteral {
  const MotionNumber(this.value);

  final double value;

  /// Whole numbers as `1`, not `1.0`.
  ///
  /// Not cosmetic: `Seg<double>(from: 0, to: 1)` is what a person writes and
  /// what the formatter leaves alone, so an emitter that produced `0.0` would
  /// rewrite every hand-written file the first time it touched one — a diff
  /// nobody asked for, on a line whose value did not change.
  @override
  String get source => value == value.roundToDouble() && value.abs() < 1e15
      ? '${value.toInt()}'
      : '$value';

  @override
  bool operator ==(Object other) =>
      other is MotionNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class MotionColor extends MotionLiteral {
  const MotionColor(this.argb);

  final int argb;

  @override
  String get source =>
      'Color(0x${argb.toRadixString(16).toUpperCase().padLeft(8, '0')})';

  @override
  bool operator ==(Object other) => other is MotionColor && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;
}

/// One tweened span of one property, as the file holds it.
class MotionSpan {
  MotionSpan({
    required this.startMs,
    required this.endMs,
    required this.from,
    required this.to,
    this.curve,
  });

  final int startMs;
  final int endMs;
  final MotionLiteral from;
  final MotionLiteral to;

  /// A `Curves.<name>`, or null for the default. Only a `Curves` member is
  /// understood; anything else makes the file unwritable rather than silently
  /// re-emitted as something else.
  final String? curve;

  int get durationMs => endMs - startMs;

  MotionSpan copyWith({
    int? startMs,
    int? endMs,
    MotionLiteral? from,
    MotionLiteral? to,
    String? curve,
  }) => MotionSpan(
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    from: from ?? this.from,
    to: to ?? this.to,
    curve: curve ?? this.curve,
  );

  bool get isColor => from is MotionColor;
}

/// One property of one target, and whatever a person wrote above it.
class MotionPropertyValues {
  MotionPropertyValues({
    required this.name,
    required this.spans,
    this.comments = const [],
    this.blankBefore = false,
  });

  final String name;
  final List<MotionSpan> spans;

  /// Whether an empty line sat above this entry.
  ///
  /// Kept for the same reason as [comments], and it is not fussiness: a values
  /// file with every blank line removed is one wall of numbers, and the first
  /// rewrite would produce exactly that diff over a file nobody had edited.
  final bool blankBefore;

  /// The comment lines immediately above this entry, verbatim.
  ///
  /// Carried through a rewrite because they are the only place the *reason* for
  /// a number can live. A tool that dropped them would teach people not to
  /// write them, and the file would become exactly the unreadable blob the
  /// design says it must not be.
  final List<String> comments;
}

class MotionTargetValues {
  MotionTargetValues({
    required this.name,
    required this.properties,
    this.comments = const [],
    this.blankBefore = false,
  });

  final String name;
  final List<MotionPropertyValues> properties;
  final List<String> comments;
  final bool blankBefore;

  MotionPropertyValues? property(String name) {
    for (var property in properties) {
      if (property.name == name) return property;
    }
    return null;
  }
}

/// A parsed `<screen>.motion.dart`, and the range of it the editor may replace.
///
/// **The editor rewrites the `MotionValues(...)` expression and nothing else.**
/// Imports, the doc comment above the const, anything else in the file — all
/// outside [expressionStart]..[expressionEnd] and never touched. That is a
/// stronger guarantee than "we own this file", and it costs one offset pair.
class MotionValuesFile {
  MotionValuesFile({
    required this.constName,
    required this.durationMs,
    required this.targets,
    required this.expressionStart,
    required this.expressionEnd,
    required this.source,
  });

  final String constName;
  final int? durationMs;
  final List<MotionTargetValues> targets;
  final int expressionStart;
  final int expressionEnd;

  /// The whole file, as read.
  final String source;

  MotionTargetValues? target(String name) {
    for (var target in targets) {
      if (target.name == name) return target;
    }
    return null;
  }

  /// The file with [targets] replaced by [next], and everything else identical.
  String rewrite(List<MotionTargetValues> next, {int? durationMs}) =>
      source.replaceRange(
        expressionStart,
        expressionEnd,
        renderMotionValues(next, durationMs: durationMs ?? this.durationMs),
      );
}

/// Why a values file could not be read.
///
/// Returned rather than thrown, and **the editor must refuse to write when it
/// is set**. The whole safety property is that a file this cannot fully
/// understand is a file it will not rewrite: a `from:` computed from a constant,
/// a curve that is not a `Curves` member, a target key built from a variable —
/// each of those is somebody's deliberate work, and re-emitting the parts we did
/// understand would delete it.
class MotionFileProblem {
  MotionFileProblem(this.message, {this.line});

  final String message;
  final int? line;

  @override
  String toString() => line == null ? message : 'line $line: $message';
}

class MotionFileResult {
  MotionFileResult({this.file, this.problems = const []});

  final MotionValuesFile? file;
  final List<MotionFileProblem> problems;

  /// Whether the editor may rewrite this file.
  bool get writable => file != null && problems.isEmpty;
}

/// Reads a `<screen>.motion.dart`.
///
/// [constName] names which const to read when the file holds more than one;
/// null takes the only one, and reports when there is a choice to make.
MotionFileResult readMotionValues(String source, {String? constName}) {
  var problems = <MotionFileProblem>[];
  var parsed = parseString(content: source, throwIfDiagnostics: false);
  int lineOf(int offset) => parsed.lineInfo.getLocation(offset).lineNumber;

  var visitor = _ConstVisitor();
  parsed.unit.accept(visitor);

  var candidates = constName == null
      ? visitor.found
      : [
          for (var candidate in visitor.found)
            if (candidate.$1 == constName) candidate,
        ];
  if (candidates.isEmpty) {
    return MotionFileResult(
      problems: [
        MotionFileProblem(
          constName == null
              ? 'no `MotionValues(...)` in this file'
              : 'no `MotionValues(...)` assigned to `$constName`',
        ),
      ],
    );
  }
  if (candidates.length > 1) {
    return MotionFileResult(
      problems: [
        MotionFileProblem(
          'this file holds ${candidates.length} motions '
          '(${candidates.map((c) => c.$1).join(', ')}); name one',
        ),
      ],
    );
  }

  var (name, expression) = candidates.single;
  int? durationMs;
  var targets = <MotionTargetValues>[];

  for (var argument in expression.argumentList.arguments) {
    if (argument is! NamedArgument) {
      problems.add(
        MotionFileProblem(
          'MotionValues takes named arguments only',
          line: lineOf(argument.offset),
        ),
      );
      continue;
    }
    var value = argument.argumentExpression;
    switch (argument.name.lexeme) {
      case 'duration':
        durationMs = _durationOf(value);
        if (durationMs == null) {
          problems.add(
            MotionFileProblem(
              '`duration` is not a plain `Duration(milliseconds: …)`',
              line: lineOf(value.offset),
            ),
          );
        }
      case 'targets':
        targets = _readTargets(value, source, problems, lineOf);
      case var other:
        problems.add(
          MotionFileProblem(
            'unknown argument `$other`',
            line: lineOf(argument.offset),
          ),
        );
    }
  }

  return MotionFileResult(
    file: MotionValuesFile(
      constName: name,
      durationMs: durationMs,
      targets: targets,
      expressionStart: expression.offset,
      expressionEnd: expression.end,
      source: source,
    ),
    problems: problems,
  );
}

List<MotionTargetValues> _readTargets(
  Expression expression,
  String source,
  List<MotionFileProblem> problems,
  int Function(int) lineOf,
) {
  var targets = <MotionTargetValues>[];
  if (expression is! SetOrMapLiteral) {
    problems.add(
      MotionFileProblem(
        '`targets` is not a map literal',
        line: lineOf(expression.offset),
      ),
    );
    return targets;
  }
  for (var element in expression.elements) {
    if (element is! MapLiteralEntry) {
      problems.add(
        MotionFileProblem(
          "only `'name': {…}` entries are understood here",
          line: lineOf(element.offset),
        ),
      );
      continue;
    }
    var name = _stringOf(element.key);
    if (name == null) {
      problems.add(
        MotionFileProblem(
          'a target key is not a string literal',
          line: lineOf(element.key.offset),
        ),
      );
      continue;
    }
    var (comments, blank) = _leading(element, source);
    targets.add(
      MotionTargetValues(
        name: name,
        comments: comments,
        blankBefore: blank,
        properties: _readProperties(element.value, source, problems, lineOf),
      ),
    );
  }
  return targets;
}

List<MotionPropertyValues> _readProperties(
  Expression expression,
  String source,
  List<MotionFileProblem> problems,
  int Function(int) lineOf,
) {
  var properties = <MotionPropertyValues>[];
  if (expression is! SetOrMapLiteral) {
    problems.add(
      MotionFileProblem(
        'a target is not a map literal',
        line: lineOf(expression.offset),
      ),
    );
    return properties;
  }
  for (var element in expression.elements) {
    if (element is! MapLiteralEntry) {
      problems.add(
        MotionFileProblem(
          "only `'property': [...]` entries are understood here",
          line: lineOf(element.offset),
        ),
      );
      continue;
    }
    var name = _stringOf(element.key);
    if (name == null) {
      problems.add(
        MotionFileProblem(
          'a property key is not a string literal',
          line: lineOf(element.key.offset),
        ),
      );
      continue;
    }
    var value = element.value;
    if (value is! ListLiteral) {
      problems.add(
        MotionFileProblem(
          'a property is not a list of segments',
          line: lineOf(value.offset),
        ),
      );
      continue;
    }
    var (comments, blank) = _leading(element, source);
    properties.add(
      MotionPropertyValues(
        name: name,
        comments: comments,
        blankBefore: blank,
        spans: [
          for (var item in value.elements) ?_readSpan(item, problems, lineOf),
        ],
      ),
    );
  }
  return properties;
}

MotionSpan? _readSpan(
  CollectionElement element,
  List<MotionFileProblem> problems,
  int Function(int) lineOf,
) {
  var arguments = switch (element) {
    MethodInvocation(methodName: Identifier(name: 'Seg')) =>
      element.argumentList,
    InstanceCreationExpression() =>
      element.constructorName.type.name.lexeme == 'Seg'
          ? element.argumentList
          : null,
    _ => null,
  };
  if (arguments == null) {
    problems.add(
      MotionFileProblem(
        'only `Seg(...)` entries are understood in a property',
        line: lineOf(element.offset),
      ),
    );
    return null;
  }

  int? startMs;
  int? endMs;
  MotionLiteral? from;
  MotionLiteral? to;
  String? curve;

  for (var argument in arguments.arguments) {
    if (argument is! NamedArgument) continue;
    var value = argument.argumentExpression;
    var line = lineOf(value.offset);
    switch (argument.name.lexeme) {
      case 'start':
        startMs = _durationOf(value);
        if (startMs == null) {
          problems.add(
            MotionFileProblem('`start` is not a Duration', line: line),
          );
        }
      case 'end':
        endMs = _durationOf(value);
        if (endMs == null) {
          problems.add(
            MotionFileProblem('`end` is not a Duration', line: line),
          );
        }
      case 'from':
        from = _literalOf(value);
        if (from == null) {
          problems.add(
            MotionFileProblem('`from` is not a number or a Color', line: line),
          );
        }
      case 'to':
        to = _literalOf(value);
        if (to == null) {
          problems.add(
            MotionFileProblem('`to` is not a number or a Color', line: line),
          );
        }
      case 'curve':
        // A prefixed identifier only, so `Curves.easeOut` is understood and a
        // hand-rolled `Cubic(...)` or a shared constant is not — and the file
        // stays unwritable rather than being re-emitted as something else.
        if (value case PrefixedIdentifier(prefix: Identifier(name: 'Curves'))) {
          curve = value.identifier.name;
        } else {
          problems.add(
            MotionFileProblem(
              '`curve` is not a `Curves.<name>`; this file can be read but '
              'not rewritten without losing it',
              line: line,
            ),
          );
        }
    }
  }

  if (startMs == null || endMs == null || from == null || to == null) {
    return null;
  }
  return MotionSpan(
    startMs: startMs,
    endMs: endMs,
    from: from,
    to: to,
    curve: curve,
  );
}

/// Milliseconds from `Duration.zero` or `Duration(milliseconds: n)`.
int? _durationOf(Expression expression) {
  if (expression case PrefixedIdentifier(
    prefix: Identifier(name: 'Duration'),
    identifier: Identifier(name: 'zero'),
  )) {
    return 0;
  }
  var arguments = switch (expression) {
    MethodInvocation(methodName: Identifier(name: 'Duration')) =>
      expression.argumentList,
    InstanceCreationExpression() =>
      expression.constructorName.type.name.lexeme == 'Duration'
          ? expression.argumentList
          : null,
    _ => null,
  };
  if (arguments == null) return null;
  var total = 0;
  for (var argument in arguments.arguments) {
    if (argument is! NamedArgument) return null;
    var value = argument.argumentExpression;
    if (value is! IntegerLiteral) return null;
    var amount = value.value;
    if (amount == null) return null;
    // Only the units a motion is written in. Anything else is legal Dart and
    // not something this should quietly re-emit as milliseconds.
    switch (argument.name.lexeme) {
      case 'milliseconds':
        total += amount;
      case 'seconds':
        total += amount * 1000;
      default:
        return null;
    }
  }
  return total;
}

MotionLiteral? _literalOf(Expression expression) {
  if (expression case IntegerLiteral(:var value?)) {
    return MotionNumber(value.toDouble());
  }
  if (expression case DoubleLiteral(:var value)) return MotionNumber(value);
  if (expression is PrefixExpression && expression.operator.lexeme == '-') {
    return switch (_literalOf(expression.operand)) {
      MotionNumber(:var value) => MotionNumber(-value),
      _ => null,
    };
  }
  var arguments = switch (expression) {
    MethodInvocation(methodName: Identifier(name: 'Color')) =>
      expression.argumentList,
    InstanceCreationExpression() =>
      expression.constructorName.type.name.lexeme == 'Color'
          ? expression.argumentList
          : null,
    _ => null,
  };
  if (arguments == null) return null;
  if (arguments.arguments.firstOrNull case IntegerLiteral(:var value?)) {
    return MotionColor(value);
  }
  return null;
}

String? _stringOf(Expression expression) =>
    expression is StringLiteral ? expression.stringValue : null;

/// The comment lines directly above [node], and whether a blank line sat above
/// those.
///
/// Read off the source rather than the token stream because a comment is not an
/// AST node — the analyzer hangs it off the following token, and only for
/// documentation comments.
///
/// **A blank line ends the run and is reported, not skipped.** A comment
/// separated from an entry belongs to the gap rather than to the entry, and the
/// gap itself is worth keeping: a values file with every blank line removed is
/// one wall of numbers.
(List<String>, bool) _leading(AstNode node, String source) {
  var lines = <String>[];
  var cursor = source.lastIndexOf('\n', node.offset - 1) + 1;
  while (cursor > 0) {
    var previousEnd = cursor - 1;
    var previousStart = previousEnd == 0
        ? 0
        : source.lastIndexOf('\n', previousEnd - 1) + 1;
    var line = source.substring(previousStart, previousEnd).trim();
    if (line.isEmpty) return (lines, true);
    if (!line.startsWith('//')) return (lines, false);
    lines.insert(0, line);
    cursor = previousStart;
  }
  return (lines, false);
}

class _ConstVisitor extends RecursiveAstVisitor<void> {
  final found = <(String, ArgumentedExpression)>[];

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    var initializer = node.initializer;
    var call = switch (initializer) {
      MethodInvocation(methodName: Identifier(name: 'MotionValues')) =>
        _Argumented(
          initializer.argumentList,
          initializer.offset,
          initializer.end,
        ),
      InstanceCreationExpression()
          when initializer.constructorName.type.name.lexeme == 'MotionValues' =>
        _Argumented(
          initializer.argumentList,
          initializer.offset,
          initializer.end,
        ),
      _ => null,
    };
    if (call != null) found.add((node.name.lexeme, call));
    super.visitVariableDeclaration(node);
  }
}

/// The `MotionValues(...)` call and where it sits, whichever node kind it
/// parsed as — unresolved, a constructor call is a method invocation.
abstract class ArgumentedExpression {
  ArgumentList get argumentList;
  int get offset;
  int get end;
}

class _Argumented implements ArgumentedExpression {
  _Argumented(this.argumentList, this.offset, this.end);

  @override
  final ArgumentList argumentList;
  @override
  final int offset;
  @override
  final int end;
}

/// Where the numbers for a screen live: `lib/home.dart` keeps them in
/// `lib/home.motion.dart`.
///
/// A convention rather than a lookup, and it is the only one. The editor has to
/// know where to write before anything has been compiled, and a path it derives
/// is a path it cannot get half-right later in a session.
String motionValuesPath(String screenFile) {
  var dot = screenFile.lastIndexOf('.');
  var slash = screenFile.lastIndexOf('/');
  var base = dot > slash ? screenFile.substring(0, dot) : screenFile;
  return '$base.motion.dart';
}

// ---------------------------------------------------------------- the emitter

/// The `MotionValues(...)` expression, formatted the way the sanctioned
/// formatter would leave it.
///
/// Matched by construction rather than by running a formatter: `dart_style`
/// resolves a language version per file and CI checks
/// `tool/prepare_submit.dart`, so an emitter that formatted independently would
/// disagree with CI on somebody's machine. The round-trip test — re-emit the
/// repo's own values files and compare byte for byte — is what keeps this
/// honest.
String renderMotionValues(List<MotionTargetValues> targets, {int? durationMs}) {
  var out = StringBuffer('MotionValues(\n');
  if (durationMs != null) {
    out.writeln('  duration: ${_duration(durationMs)},');
  }
  out.writeln('  targets: {');
  for (var target in targets) {
    if (target.blankBefore) out.writeln();
    for (var comment in target.comments) {
      out.writeln('    $comment');
    }
    out.writeln("    '${target.name}': {");
    for (var property in target.properties) {
      if (property.blankBefore) out.writeln();
      for (var comment in property.comments) {
        out.writeln('      $comment');
      }
      out.writeln("      '${property.name}': [");
      for (var span in property.spans) {
        out
          ..writeln('        Seg<${span.isColor ? 'Color' : 'double'}>(')
          ..writeln('          start: ${_duration(span.startMs)},')
          ..writeln('          end: ${_duration(span.endMs)},')
          ..writeln('          from: ${span.from.source},')
          ..writeln('          to: ${span.to.source},');
        if (span.curve case var curve?) {
          out.writeln('          curve: Curves.$curve,');
        }
        out.writeln('        ),');
      }
      out.writeln('      ],');
    }
    out.writeln('    },');
  }
  out
    ..writeln('  },')
    ..write(')');
  return out.toString();
}

String _duration(int ms) =>
    ms == 0 ? 'Duration.zero' : 'Duration(milliseconds: $ms)';
