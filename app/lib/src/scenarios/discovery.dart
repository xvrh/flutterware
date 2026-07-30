import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// Where a package keeps its scenarios when the config does not say otherwise.
const defaultScenariosDirectory = 'test/scenarios';

/// One `scenario('name', …)` call, located.
class ScenarioRef {
  ScenarioRef({required this.name, required this.file, required this.line});

  final String name;

  /// Package-relative, `/`-separated — the same on every machine.
  final String file;

  final int line;

  @override
  String toString() => '$file:$line $name';
}

class ScenarioScanResult {
  ScenarioScanResult({required this.scenarios, required this.diagnostics});

  final List<ScenarioRef> scenarios;

  /// What the scan noticed but did not act on — a non-literal name it cannot
  /// list, a duplicate. The tool never guesses, but it always reports what it
  /// noticed.
  final List<String> diagnostics;
}

/// Finds scenarios by **parsing** the scenario directory, never by resolving
/// or compiling it — the catalog's discovery posture
/// (`2026-07-26-ui-catalog-entry-model.md`), applied to the third source.
///
/// A `scenario('literal', …)` call is as syntactically discoverable as a
/// `@Demo` annotation: the call's name and its first argument are all the
/// report and the badges need. The runtime listing stays ground truth; a
/// disagreement is a diagnostic, not a failure.
class ScenarioScanner {
  ScenarioScanner({
    required this.packageRoot,
    this.directory = defaultScenariosDirectory,
  });

  final String packageRoot;

  /// Scenario directory relative to [packageRoot].
  final String directory;

  ScenarioScanResult scan() {
    var scenarios = <ScenarioRef>[];
    var diagnostics = <String>[];

    var root = Directory(p.join(packageRoot, directory));
    if (root.existsSync()) {
      var files = [
        for (var entity in root.listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.dart')) entity,
      ]..sort((a, b) => a.path.compareTo(b.path));
      for (var file in files) {
        var source = file.readAsStringSync();
        // A substring prefilter before parsing, as the catalog scanner does.
        if (!source.contains('scenario(')) continue;
        _scanFile(file, source, scenarios, diagnostics);
      }
    }

    _reportDuplicates(scenarios, diagnostics);
    return ScenarioScanResult(scenarios: scenarios, diagnostics: diagnostics);
  }

  void _scanFile(
    File file,
    String source,
    List<ScenarioRef> scenarios,
    List<String> diagnostics,
  ) {
    var parsed = parseString(content: source, throwIfDiagnostics: false);
    var path = p.split(p.relative(file.path, from: packageRoot)).join('/');

    var visitor = _ScenarioCallVisitor();
    parsed.unit.accept(visitor);
    for (var call in visitor.calls) {
      var line = parsed.lineInfo.getLocation(call.offset).lineNumber;
      var name = call.name;
      if (name == null) {
        diagnostics.add(
          '$path:$line: scenario name is not a string literal, so it cannot '
          'be listed without running the file',
        );
        continue;
      }
      scenarios.add(ScenarioRef(name: name, file: path, line: line));
    }
  }

  /// Two scenarios with one name are both real, but an address naming them is
  /// ambiguous. Reported per package, not rejected — the runtime listing is
  /// what would refuse.
  void _reportDuplicates(
    List<ScenarioRef> scenarios,
    List<String> diagnostics,
  ) {
    var byName = <String, List<ScenarioRef>>{};
    for (var ref in scenarios) {
      byName.putIfAbsent(ref.name, () => []).add(ref);
    }
    for (var MapEntry(key: name, value: refs) in byName.entries) {
      if (refs.length < 2) continue;
      diagnostics.add(
        'scenario "$name" is declared ${refs.length} times: '
        '${refs.map((r) => '${r.file}:${r.line}').join(', ')}',
      );
    }
  }
}

class _ScenarioCall {
  _ScenarioCall({required this.name, required this.offset});

  final String? name;
  final int offset;
}

class _ScenarioCallVisitor extends RecursiveAstVisitor<void> {
  final calls = <_ScenarioCall>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'scenario') {
      var first = node.argumentList.arguments.firstOrNull;
      calls.add(
        _ScenarioCall(
          name: first is StringLiteral ? first.stringValue : null,
          offset: node.offset,
        ),
      );
    }
    super.visitMethodInvocation(node);
  }
}
