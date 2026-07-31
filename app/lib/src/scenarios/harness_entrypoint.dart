import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the generated harness entrypoint lives, relative to the package.
const harnessEntrypointPath = 'build/flutterware/scenarios_harness.dart';

/// The generated `main` the runner compiles: one import per scenario file,
/// feeding the harness the map it declares from.
///
/// Scenario files live under `test/`, outside `lib/`, so they have no
/// `package:` URI — imports are relative to the entrypoint's own location,
/// exactly as the catalog's per-entry wrappers re-relativise theirs.
String generateHarnessEntrypoint(List<String> files) {
  var sorted = [...files]..sort();
  var buffer = StringBuffer()
    ..writeln('// GENERATED — flutterware scenarios harness. Do not edit.')
    ..writeln("import 'package:flutterware/src/scenarios/harness.dart'")
    ..writeln('    as harness;');
  for (var (index, file) in sorted.indexed) {
    buffer.writeln("import '../../$file' as s$index;");
  }
  buffer
    ..writeln()
    ..writeln('void main() => harness.runHarness({');
  for (var (index, file) in sorted.indexed) {
    buffer.writeln("  '$file': s$index.main,");
  }
  buffer.writeln('});');
  return buffer.toString();
}

/// Writes the entrypoint into the package and returns its absolute path.
///
/// Left alone when the content is already right: the entrypoint is a compiled
/// source, and an untouched mtime is what keeps a refresh from invalidating —
/// and recompiling — it for nothing.
String writeHarnessEntrypoint(String packageRoot, List<String> files) {
  var path = p.join(packageRoot, harnessEntrypointPath);
  var source = generateHarnessEntrypoint(files);
  var file = File(path);
  if (!file.existsSync() || file.readAsStringSync() != source) {
    file
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(source);
  }
  return path;
}
