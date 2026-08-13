import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../utils/daemon/device.dart';

/// One launchable `main()`, from the config or from the scan.
class EntrypointRef {
  EntrypointRef({
    required this.path,
    required this.name,
    required this.declared,
    this.description,
    this.flavor,
    this.platforms = const [],
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

  /// What this entry point declares it can run on, as written — shorthands
  /// unexpanded. Empty means anything.
  final List<RunPlatform> platforms;

  /// What the config says about `main`'s parameters — a computed value, a
  /// label. Never what they are: the signature is the list.
  final List<Knob> knobs;

  /// Every concrete platform this allows. Empty means no restriction.
  Set<RunPlatform> get allowedPlatforms => RunPlatform.expandAll(platforms);

  /// Whether a device reporting [platformType] and [category] is one this
  /// entry point can run on.
  ///
  /// Takes the two strings rather than a device because they are what crosses
  /// the wire from `flutter daemon`, and because both are optional there: a
  /// device that says nothing about itself is **allowed**. Hiding a connected
  /// phone over a field the daemon happened not to send would be the tool
  /// inventing a restriction nobody declared, which is worse than offering a
  /// device that turns out not to build.
  bool allowsDevice({String? platformType, String? category}) {
    var allowed = allowedPlatforms;
    if (allowed.isEmpty) return true;
    if (platformType != null) {
      var platform = RunPlatform.byName(platformType);
      // A platform we have no name for — `fuchsia`, whatever comes next — is
      // not something a declaration can have meant to include, so it is out.
      if (platform != null) return allowed.contains(platform);
      return false;
    }
    // No platform, but the daemon groups devices the same way our shorthands
    // do, so `mobile` still answers for a phone that named no platform.
    if (category != null) {
      var shorthand = RunPlatform.byName(category);
      if (shorthand != null) {
        return allowed.intersection(shorthand.expanded).isNotEmpty;
      }
    }
    return true;
  }

  @override
  String toString() => '$name ($path)';
}

/// The one place a device and an entry point's declaration are compared, so
/// the picker, the launch guard and the reported list cannot drift into three
/// slightly different rules.
extension EntrypointMatch on DaemonDevice {
  bool allowedBy(EntrypointRef entry) =>
      entry.allowsDevice(platformType: platformType, category: category);
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
          platforms: _platformsOf(entry['platforms']),
          declared: true,
          knobs: _knobsOf(entry['knobs']),
        ),
];

/// A name this build has no member for is dropped rather than refused: the
/// config imports the `flutterware` version the *project* pins, which a hosted
/// install can carry ahead of the GUI reading its manifest.
///
/// So a restriction naming only platforms we do not know becomes no
/// restriction, and the picker offers everything. That is the safe direction:
/// too many devices ends in a build failure that names the platform, while too
/// few ends in a picker with nothing in it and no way to ask why.
List<RunPlatform> _platformsOf(Object? raw) => [
  for (var name in (raw as List? ?? const []))
    if (name is String) ?RunPlatform.byName(name),
];

/// The annotations the config attached to `main`'s parameters, by name.
///
/// Same forgiving posture as [_definesOf] and `_platformsOf`: an entry this
/// build cannot read is dropped rather than refused, because the config imports
/// the `flutterware` version the *project* pins.
List<Knob> _knobsOf(Object? raw) => [
  for (var entry in (raw as List? ?? const []))
    if (entry is Map)
      if (entry['knob'] case String name)
        Knob(
          name,
          label: entry['label'] as String?,
          description: entry['description'] as String?,
          options: [
            for (var option in (entry['options'] as List? ?? const []))
              if (option is String) option,
          ],
          from: ValueSource.fromJson(entry['from']),
        ),
];

/// Every `lib/*.dart` of [packageRoot] that declares a top-level `main()`.
///
/// **Parsed, never resolved or compiled** — the posture the catalog and the
/// scenario scanner already take. A `void main()` is as syntactically visible
/// as a `@Preview` annotation, and finding one costs a parse rather than a build.
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
