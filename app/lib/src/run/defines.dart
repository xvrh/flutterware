import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// One `--dart-define` a package's own source reads, found by parsing.
class DefineRef {
  const DefineRef({
    required this.name,
    required this.kind,
    required this.file,
    this.defaultValue,
  });

  /// The define, exactly as `String.fromEnvironment` was given it.
  final String name;

  /// `String`, `int`, `bool` or `double` — the type it is read as.
  ///
  /// Worth carrying because it is the difference between a text field and a
  /// checkbox, and because a config offering `options: ['yes', 'no']` for a
  /// `bool.fromEnvironment` is offering two values that both mean false.
  final String kind;

  /// Package-relative, `/`-separated — where the read is.
  final String file;

  /// What the app uses when nobody sets this define, or null when the read
  /// gave no `defaultValue:`.
  ///
  /// A string literal is unquoted — `'http://localhost:8080'` becomes
  /// `http://localhost:8080` — because that is the value, and a
  /// `--dart-define` carrying the quotes would set something the app never
  /// meant. Everything else is the source text, which for `3`, `true`, `-1`
  /// and `1.5` is already exactly what a define would carry, and for anything
  /// stranger is at least what somebody wrote rather than a literal
  /// re-derived from an unresolved parse.
  final String? defaultValue;

  @override
  String toString() =>
      '$kind $name${defaultValue == null ? '' : ' = $defaultValue'}';
}

/// Every `--dart-define` [packageRoot]'s `lib/` reads, keyed by define name.
///
/// **Parsed, never resolved or compiled** — the posture `scanEntrypoints`, the
/// catalog and the scenario scanner all take. What makes it work here is a
/// language rule rather than a convention of ours: `String.fromEnvironment`
/// takes its name as a *constant expression*, and a wrapper cannot hide it —
/// `const Knob(this.name) : value = String.fromEnvironment(name)` does not
/// compile ("the variable 'name' is not a constant"). So every project that
/// reads a define has written the literal, in that exact call, and finding it
/// costs a parse.
///
/// **Recursive, unlike the entry point scan**, and for the opposite reason: an
/// entry point is a thing to offer in a menu and belongs at the top level,
/// while a define is nearly always read in a `lib/src/config.dart` that nobody
/// launches. A scan that stopped at the top level would find almost none of
/// them.
///
/// Package-level, with no attempt to say which entry point reaches which
/// define: an unresolved parse cannot follow imports, and a per-entry-point
/// answer derived from one would be a guess wearing precision.
///
/// Later reads of the same name win nothing — the first is kept, so the answer
/// does not depend on directory order.
Map<String, DefineRef> scanDefines(String packageRoot) {
  var lib = Directory(p.join(packageRoot, 'lib'));
  if (!lib.existsSync()) return const {};
  var found = <String, DefineRef>{};
  var files = [
    for (var entity in lib.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
  for (var file in files) {
    String source;
    try {
      source = file.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    // The prefilter the other scanners use. Most files in a lib/ have no
    // define in them at all, and a substring search is far cheaper than a
    // parse.
    if (!source.contains('fromEnvironment')) continue;
    var relative = p
        .relative(file.path, from: packageRoot)
        .replaceAll(r'\', '/');
    try {
      parseString(
        content: source,
        throwIfDiagnostics: false,
      ).unit.accept(_DefineVisitor(relative, found));
    } on Object {
      // A file that will not parse cannot be built either, and the compiler
      // says so far better than a scan can.
    }
  }
  return found;
}

/// Both spellings the parser produces for the same call.
///
/// Without resolution `String.fromEnvironment('X')` is a **method invocation**
/// on a target that happens to be a type name, while `const
/// String.fromEnvironment('X')` is an **instance creation** whose type is the
/// prefixed name `String.fromEnvironment`. Handling only the second finds the
/// rarer of the two: the `const` is implicit in `const x = …`, which is how
/// almost every define is actually written.
class _DefineVisitor extends RecursiveAstVisitor<void> {
  _DefineVisitor(this.file, this.found);

  final String file;
  final Map<String, DefineRef> found;

  static const _kinds = {'String', 'int', 'bool', 'double'};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'fromEnvironment') {
      if (node.target case SimpleIdentifier(
        :var name,
      ) when _kinds.contains(name)) {
        _record(name, node.argumentList);
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    var type = node.constructorName.type;
    if (type.name.lexeme == 'fromEnvironment') {
      var kind = type.importPrefix?.name.lexeme;
      if (kind != null && _kinds.contains(kind)) {
        _record(kind, node.argumentList);
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  void _record(String kind, ArgumentList arguments) {
    String? name;
    String? defaultValue;
    for (var argument in arguments.arguments) {
      switch (argument) {
        // A name that is not a plain string literal is a name we cannot read,
        // and the language will not accept it either — it has to be constant.
        case SimpleStringLiteral(:var value) when name == null:
          name = value;
        case NamedArgument(:var name, :var argumentExpression)
            when name.lexeme == 'defaultValue':
          defaultValue = switch (argumentExpression) {
            SimpleStringLiteral(:var value) => value,
            var other => '$other',
          };
        default:
          break;
      }
    }
    if (name == null || name.isEmpty) return;
    // `dart.vm.product`, `dart.library.io` and the rest are the VM's own,
    // answered by the compiler rather than passed on a command line. Offering
    // one as a knob would offer a control that cannot be set. Found for real:
    // this repo reads `dart.vm.product` in two packages.
    if (name.startsWith('dart.')) return;
    found.putIfAbsent(
      name,
      () => DefineRef(
        name: name!,
        kind: kind,
        file: file,
        defaultValue: defaultValue,
      ),
    );
  }
}
