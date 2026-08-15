/// Reading generated Dart the way the compiler will, rather than the way a
/// `contains` does.
///
/// A generator that quotes a string wrongly still produces a file holding the
/// characters a test looked for — `name: r'What's new'` contains `What's new`.
/// What it does not produce is a file that parses, and that is the property
/// worth asserting: one entry whose name carries an apostrophe took a whole
/// 133-entry catalog down, because the harness is one file for the package.
///
/// Framework-neutral on purpose — the callers are split between `package:test`
/// and `flutter_test`, and a syntax error surfaces as the thrown diagnostic
/// either way.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// [source] as its syntax tree, throwing the compiler's own diagnostic when it
/// does not parse.
CompilationUnit parseGenerated(String source) =>
    parseString(content: source).unit;

/// Every string literal in [source], as the *values* a program would see.
///
/// The values and not the quoting: whether the emitter reached for `'…'`,
/// `"…"` or `r'…'` is its business, and a test pinned to one of them fails the
/// day escaping legitimately changes shape.
List<String> generatedStrings(String source) {
  var found = <String>[];
  parseGenerated(source).accept(_StringCollector((value) => found.add(value)));
  return found;
}

/// Every `<name>: '…'` argument in [source], by the value it carries.
List<String> generatedArguments(String source, String name) {
  var found = <String>[];
  parseGenerated(source).accept(_ArgumentCollector(name, found.add));
  return found;
}

class _StringCollector extends RecursiveAstVisitor<void> {
  _StringCollector(this.found);

  final void Function(String) found;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    found(node.value);
    super.visitSimpleStringLiteral(node);
  }
}

class _ArgumentCollector extends RecursiveAstVisitor<void> {
  _ArgumentCollector(this.name, this.found);

  final String name;
  final void Function(String) found;

  @override
  void visitNamedArgument(NamedArgument node) {
    var value = node.argumentExpression;
    if (node.name.lexeme == name && value is StringLiteral) {
      if (value.stringValue case var literal?) found(literal);
    }
    super.visitNamedArgument(node);
  }
}
