import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

/// One launchable `main()`, from the config or from the scan.
class EntrypointRef {
  EntrypointRef({
    required this.path,
    required this.name,
    required this.declared,
    this.description,
    this.flavor,
    this.knobs = const [],
  });

  /// Package-relative, `/`-separated — `lib/main_staging.dart`.
  final String path;

  /// What to call it. The declared name, or the file's own when the scan
  /// found it.
  final String name;

  /// The one line the config gave it. Null for a scanned entry point: a
  /// description is something somebody wrote, never something guessed from a
  /// file name.
  final String? description;

  /// True when `tool/flutterware.dart` named it. A discovered entry point is
  /// still launchable; the difference is that nobody vouched for it, and it
  /// carries no knobs.
  final bool declared;

  /// The `--flavor` this entry point is built with, when the project has them.
  /// A flavoured project cannot be run without one — see [Entrypoint.flavor].
  final String? flavor;

  final List<LaunchKnob> knobs;

  @override
  String toString() => '$name ($path)';
}

/// The entry points [config] declares for one package, decoded from the
/// manifest's raw maps.
///
/// Empty when the package declared none, which is what makes [scanEntrypoints]
/// the fallback rather than a merge: a project that named two entry points
/// meant those two, and quietly adding the six other files with a `main()` in
/// them would make the list say something the config did not.
List<EntrypointRef> declaredEntrypoints(Map<String, Object?> config) => [
  for (var entry in (config['entrypoints'] as List? ?? const []))
    if (entry is Map)
      if (entry['path'] case String path)
        EntrypointRef(
          path: path,
          name: entry['name'] as String? ?? _nameFor(path),
          description: entry['description'] as String?,
          flavor: entry['flavor'] as String?,
          declared: true,
          knobs: _knobsOf(entry['knobs']),
        ),
];

List<LaunchKnob> _knobsOf(Object? raw) => [
  for (var knob in (raw as List? ?? const []))
    if (knob is Map)
      if (knob['define'] case String define)
        LaunchKnob(
          define,
          label: knob['label'] as String?,
          description: knob['description'] as String?,
          defaultValue: knob['default'] as String?,
          options: [
            for (var option in (knob['options'] as List? ?? const []))
              if (option is String) option,
          ],
          from: switch (knob['from']) {
            String name => KnobSource.byName(name),
            _ => null,
          },
        ),
];

/// Every `lib/*.dart` of [packageRoot] that declares a top-level `main()`.
///
/// **Parsed, never resolved or compiled** — the posture the catalog and the
/// scenario scanner already take. A `void main()` is as syntactically visible
/// as a `@Demo` annotation, and finding one costs a parse rather than a build.
///
/// Deliberately not recursive. A `main()` under `lib/src/` is somebody's
/// helper or a generated harness, not a thing to offer in a launch menu, and a
/// recursive scan of a large package turns a short list into a haystack.
/// Anything below the top level has to be declared.
List<EntrypointRef> scanEntrypoints(String packageRoot) {
  var lib = Directory(p.join(packageRoot, 'lib'));
  if (!lib.existsSync()) return const [];
  var found = <EntrypointRef>[];
  var files = [
    for (var entity in lib.listSync())
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
  for (var file in files) {
    String source;
    try {
      source = file.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    // A substring prefilter before parsing, as the other two scanners do: most
    // files in a lib/ have no `main` in them at all.
    if (!source.contains('main')) continue;
    if (!_hasMain(source)) continue;
    var path = 'lib/${p.basename(file.path)}';
    found.add(EntrypointRef(path: path, name: _nameFor(path), declared: false));
  }
  return found;
}

bool _hasMain(String source) {
  try {
    var parsed = parseString(content: source, throwIfDiagnostics: false);
    for (var declaration in parsed.unit.declarations) {
      if (declaration is FunctionDeclaration &&
          declaration.name.lexeme == 'main') {
        return true;
      }
    }
  } on Object {
    // A file that will not parse cannot be launched either; the build would
    // say so far more usefully than a scan can.
  }
  return false;
}

/// `lib/main_staging.dart` → `main_staging`. Not prettified into `Staging`:
/// guessing a display name from a file name produces confident nonsense on the
/// first project that does not follow the convention, and the config is where
/// a real name belongs.
String _nameFor(String path) {
  var base = p.basename(path);
  return base.endsWith('.dart')
      ? base.substring(0, base.length - '.dart'.length)
      : base;
}
