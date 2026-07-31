import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutterware/motion.dart';
import 'package:path/path.dart' as p;

/// Where a package keeps the screens its motions live in, when the config does
/// not say otherwise.
///
/// `lib`, not a directory of our own, because a motion is not a thing you keep
/// somewhere — it is a screen that happens to move. The substring prefilter is
/// what keeps scanning a whole package cheap.
const defaultMotionDirectory = 'lib';

/// One `m.target('name')` in a scope's builder, and what the code does with it.
class MotionTargetRef {
  MotionTargetRef({
    required this.name,
    required this.line,
    this.properties = const [],
    this.boxed = false,
  });

  final String name;
  final int line;

  /// Vocabulary properties read against this target at a call site, sorted.
  ///
  /// Names outside the vocabulary are dropped rather than reported: a local
  /// holding a target is an ordinary object, and `title.name` is not somebody
  /// mistyping a property.
  final List<String> properties;

  /// Whether a `MotionBox` was handed this target.
  ///
  /// Recorded because otherwise the scan flatly disagrees with the runtime on
  /// the most common way to use the API: a box applies eight properties and
  /// reads none at the call site, so a target wearing one looks unwired to a
  /// parser and is fully wired to the guest.
  final bool boxed;

  @override
  String toString() =>
      '$name:$line${boxed ? ' [box]' : ''}'
      '${properties.isEmpty ? '' : ' ${properties.join(',')}'}';
}

/// One `MotionScope(...)`, located.
class MotionRef {
  MotionRef({
    required this.values,
    required this.file,
    required this.line,
    this.targets = const [],
  });

  /// The identifier passed to `motion:` — `inboxMotion` — which is also the
  /// name the address uses. Null when it was not a plain identifier, in which
  /// case the scope is still listed and the diagnostics say why it is thin.
  final String? values;

  /// Package-relative, `/`-separated — the same on every machine.
  final String file;

  final int line;

  final List<MotionTargetRef> targets;

  @override
  String toString() => '$file:$line ${values ?? '<expression>'}';
}

class MotionScanResult {
  MotionScanResult({required this.motions, required this.diagnostics});

  final List<MotionRef> motions;

  /// What the scan noticed and did not act on. The runtime listing is ground
  /// truth; a disagreement is a diagnostic, never a failure.
  final List<String> diagnostics;
}

/// Finds motions by **parsing**, never by resolving or compiling — the
/// catalog's discovery posture applied to a third source.
///
/// A `MotionScope(motion: x, builder: (m) { … })` is as syntactically
/// discoverable as a `@Demo` annotation, and everything a badge or `fw list`
/// needs is inside one closure: the targets are `m.target('literal')` against
/// the builder's own parameter, and the reads are `<local>.<property>` against
/// a local bound to one. Nothing here crosses a file boundary, so there is
/// nothing to resolve.
///
/// **Provisional by construction.** It cannot know what a helper widget reads,
/// and it does not try; a live guest answers that. What it buys is a list that
/// exists before anything is compiled.
class MotionScanner {
  MotionScanner({
    required this.packageRoot,
    this.directory = defaultMotionDirectory,
  });

  final String packageRoot;

  /// Scanned directory, relative to [packageRoot].
  final String directory;

  MotionScanResult scan() {
    var motions = <MotionRef>[];
    var diagnostics = <String>[];

    var root = Directory(p.join(packageRoot, directory));
    if (root.existsSync()) {
      var files = [
        for (var entity in root.listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.dart')) entity,
      ]..sort((a, b) => a.path.compareTo(b.path));
      for (var file in files) {
        var source = file.readAsStringSync();
        if (!source.contains('MotionScope')) continue;
        _scanFile(file, source, motions, diagnostics);
      }
    }

    _reportDuplicates(motions, diagnostics);
    return MotionScanResult(motions: motions, diagnostics: diagnostics);
  }

  void _scanFile(
    File file,
    String source,
    List<MotionRef> motions,
    List<String> diagnostics,
  ) {
    var parsed = parseString(content: source, throwIfDiagnostics: false);
    var path = p.split(p.relative(file.path, from: packageRoot)).join('/');

    var visitor = _MotionScopeVisitor();
    parsed.unit.accept(visitor);

    for (var scope in visitor.scopes) {
      var line = parsed.lineInfo.getLocation(scope.offset).lineNumber;
      if (scope.values == null) {
        diagnostics.add(
          '$path:$line: `motion:` is not a plain identifier, so the values '
          'file cannot be named without resolving it',
        );
      }
      for (var offset in scope.unnamedTargets) {
        diagnostics.add(
          '$path:${parsed.lineInfo.getLocation(offset).lineNumber}: '
          'target name is not a string literal, so it cannot be listed '
          'without running the file',
        );
      }
      motions.add(
        MotionRef(
          values: scope.values,
          file: path,
          line: line,
          targets: [
            for (var target in scope.targets.values)
              MotionTargetRef(
                name: target.name,
                line: parsed.lineInfo.getLocation(target.offset).lineNumber,
                properties: target.properties.toList()..sort(),
                boxed: target.boxed,
              ),
          ]..sort((a, b) => a.line.compareTo(b.line)),
        ),
      );
    }
  }

  /// Two scopes on one values const are both real, and an address naming one
  /// is ambiguous. Reported, never rejected — as scenarios does with names.
  void _reportDuplicates(List<MotionRef> motions, List<String> diagnostics) {
    var byValues = <String, List<MotionRef>>{};
    for (var ref in motions) {
      if (ref.values case var name?) {
        byValues.putIfAbsent(name, () => []).add(ref);
      }
    }
    for (var MapEntry(key: name, value: refs) in byValues.entries) {
      if (refs.length < 2) continue;
      diagnostics.add(
        'motion "$name" is scoped ${refs.length} times: '
        '${refs.map((r) => '${r.file}:${r.line}').join(', ')}',
      );
    }
  }
}

class _Target {
  _Target({required this.name, required this.offset});

  final String name;
  final int offset;
  final properties = <String>{};
  var boxed = false;
}

class _Scope {
  _Scope({required this.offset, required this.values});

  final int offset;
  final String? values;

  /// By target name, so two `m.target('title')` calls are one entry.
  final targets = <String, _Target>{};
  final unnamedTargets = <int>[];
}

/// Finds the scopes; [_BuilderVisitor] reads inside one.
///
/// **Both node kinds, and that is not belt-and-braces.** Unresolved,
/// `MotionScope(...)` parses as a `MethodInvocation` — the analyzer only
/// rewrites it into an `InstanceCreationExpression` once it knows the name is a
/// class, which is exactly the step a syntactic scan skips. Only the `const`
/// and `new` forms arrive as constructions.
class _MotionScopeVisitor extends RecursiveAstVisitor<void> {
  final scopes = <_Scope>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'MotionScope') {
      scopes.add(_readScope(node.argumentList, node.offset));
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'MotionScope') {
      scopes.add(_readScope(node.argumentList, node.offset));
    }
    super.visitMethodInvocation(node);
  }
}

_Scope _readScope(ArgumentList arguments, int offset) {
  Expression? argument(String name) {
    for (var arg in arguments.arguments) {
      if (arg is! NamedArgument) continue;
      if (arg.name.lexeme == name) return arg.argumentExpression;
    }
    return null;
  }

  var values = argument('motion');
  var scope = _Scope(
    offset: offset,
    values: values is SimpleIdentifier ? values.name : null,
  );

  // The builder's own parameter is what `m.target(…)` is called on. Taking the
  // name from the closure rather than assuming `m` is the difference between
  // reading a convention and reading the code.
  if (argument('builder') case FunctionExpression builder) {
    var receiver = builder.parameters?.parameters.firstOrNull?.name?.lexeme;
    if (receiver != null) {
      builder.body.accept(_BuilderVisitor(scope, receiver));
    }
  }
  return scope;
}

class _BuilderVisitor extends RecursiveAstVisitor<void> {
  _BuilderVisitor(this.scope, this.receiver);

  final _Scope scope;

  /// The builder's parameter — `m` by convention, whatever it is by rule.
  final String receiver;

  /// Locals bound to a target: `var title = m.target('title')`.
  final _locals = <String, String>{};

  String? _targetNameOf(Expression? expression) {
    if (expression is! MethodInvocation) return null;
    if (expression.methodName.name != 'target') return null;
    if (expression.target case SimpleIdentifier(
      name: var on,
    ) when on == receiver) {
      // A positional argument *is* an `Expression`; `Argument` is sealed over
      // that and `NamedArgument`.
      var first = expression.argumentList.arguments.firstOrNull;
      return first is StringLiteral ? first.stringValue : null;
    }
    return null;
  }

  bool _isTargetCall(Expression? expression) =>
      expression is MethodInvocation &&
      expression.methodName.name == 'target' &&
      expression.target is SimpleIdentifier &&
      (expression.target! as SimpleIdentifier).name == receiver;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isTargetCall(node)) {
      var name = _targetNameOf(node);
      if (name == null) {
        scope.unnamedTargets.add(node.offset);
      } else {
        scope.targets.putIfAbsent(
          name,
          () => _Target(name: name, offset: node.offset),
        );
      }
    } else if (node.target == null && node.methodName.name == 'MotionBox') {
      // Unresolved, a widget constructor is a method call — see
      // [_MotionScopeVisitor].
      _recordBox(node.argumentList, node.offset);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_targetNameOf(node.initializer) case var name?) {
      _locals[node.name.lexeme] = name;
    }
    super.visitVariableDeclaration(node);
  }

  /// `title.opacity` — the ordinary read.
  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (_locals[node.prefix.name] case var target?) {
      _record(target, node.identifier.name);
    }
    super.visitPrefixedIdentifier(node);
  }

  /// `m.target('title').opacity` — the same read, written inline.
  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (_targetNameOf(node.target) case var name?) {
      _record(name, node.propertyName.name);
    }
    super.visitPropertyAccess(node);
  }

  /// `MotionBox(title, …)`, which reads nothing here and eight things at run
  /// time.
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'MotionBox') {
      _recordBox(node.argumentList, node.offset);
    }
    super.visitInstanceCreationExpression(node);
  }

  void _recordBox(ArgumentList arguments, int offset) {
    var name = switch (arguments.arguments.firstOrNull) {
      SimpleIdentifier(:var name) => _locals[name],
      Expression first => _targetNameOf(first),
      _ => null,
    };
    if (name == null) return;
    scope.targets
            .putIfAbsent(name, () => _Target(name: name, offset: offset))
            .boxed =
        true;
  }

  void _record(String target, String property) {
    if (!motionVocabularyByName.containsKey(property)) return;
    scope.targets
        .putIfAbsent(target, () => _Target(name: target, offset: 0))
        .properties
        .add(property);
  }
}
