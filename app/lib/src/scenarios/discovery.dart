import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../utils/list_files.dart';

/// Where discovery looks when the config does not say otherwise: all of
/// `test/`. A scenario is an ordinary widget test, and `flutter test` does not
/// care which folder a test sits in — so neither does the scan. The substring
/// prefilter is what keeps the wider walk cheap.
const defaultScenariosScanRoot = 'test';

/// Where `new` writes when the config does not say otherwise — the convention,
/// not a fence. Discovery looks at all of [defaultScenariosScanRoot]; this is
/// only the answer to "where should the next file go".
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
/// `@Preview` annotation: the call's name and its first argument are all the
/// report and the badges need. The runtime listing stays ground truth; a
/// disagreement is a diagnostic, not a failure.
class ScenarioScanner {
  ScenarioScanner({
    required this.packageRoot,
    this.directory = defaultScenariosScanRoot,
  });

  final String packageRoot;

  /// The directory the scan walks, relative to [packageRoot].
  final String directory;

  ScenarioScanResult scan() {
    var scenarios = <ScenarioRef>[];
    var diagnostics = <String>[];

    var root = p.join(packageRoot, directory);
    if (Directory(root).existsSync()) {
      // Listed the way git lists — see `list_files.dart`. A recursive
      // `listSync` follows symlinks by default, which is how a scan of a
      // modest directory ends up reading whatever a link inside it points at.
      var files = [
        for (var file in listFilesInDirectory(root))
          if (file.path.endsWith('.dart')) file,
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

  /// Two scenarios with one name are both real, and the name is only
  /// ambiguous **within a file**.
  ///
  /// A name repeated across files costs nothing: the file is part of a
  /// scenario's address (`<package>/<file…>/<scenario>`), `run --scenario=`
  /// refuses without one, and the harness writes its artifacts under
  /// `<file>/<name>`. All three tell two `Overview`s in two files apart on
  /// their own, so warning about them was a rule nothing in the tool actually
  /// held — a suite that names the same screen once per feature file was
  /// reading a warning it could do nothing useful about.
  ///
  /// Repeated *in one file* is the case where those three have nothing left to
  /// choose by. Reported, not rejected: the run honours a name matching twice
  /// by running both, which is the honest reading of a request that names only
  /// what the panel displays.
  void _reportDuplicates(
    List<ScenarioRef> scenarios,
    List<String> diagnostics,
  ) {
    var byName = <(String, String), List<ScenarioRef>>{};
    for (var ref in scenarios) {
      byName.putIfAbsent((ref.file, ref.name), () => []).add(ref);
    }
    for (var MapEntry(key: (file, name), value: refs) in byName.entries) {
      if (refs.length < 2) continue;
      diagnostics.add(
        '$file: scenario "$name" is declared ${refs.length} times '
        '(lines ${refs.map((r) => r.line).join(', ')}) — running or opening '
        'one of them addresses them all.',
      );
    }
  }
}

/// The deepest directory every file in [files] sits under, `/`-separated like
/// the paths themselves, or `''` when they share none (or there are none).
///
/// What the list pane drops from its labels: a prefix every row shares says
/// nothing. Computed from the files found rather than read off the
/// configuration, so a suite kept conventionally under `test/scenarios/`
/// displays exactly as it did when that was the fence, and one spread across
/// `test/` shows the part that differs.
String commonScenarioDirectory(Iterable<String> files) {
  List<String>? common;
  for (var file in files) {
    var directory = p.url.dirname(file);
    var segments = directory == '.' ? <String>[] : p.url.split(directory);
    if (common == null) {
      common = segments;
      continue;
    }
    var length = 0;
    while (length < common.length &&
        length < segments.length &&
        common[length] == segments[length]) {
      length++;
    }
    common = common.sublist(0, length);
  }
  return common == null || common.isEmpty ? '' : p.url.joinAll(common);
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
