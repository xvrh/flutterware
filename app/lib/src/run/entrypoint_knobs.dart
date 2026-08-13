import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';

import '../utils/enum_lookup.dart';
import '../utils/parameter_knobs.dart';

/// What an entry point's `main` declares it can be launched with.
class EntrypointKnobs {
  const EntrypointKnobs({
    this.knobs = const [],
    this.imports = const [],
    this.problems = const [],
    this.required = const [],
  });

  /// One per optional parameter, in signature order — which is the order the
  /// form renders, and the order somebody chose when they wrote it.
  final List<ParameterKnob> knobs;

  /// The entry point's own imports, as the generated wrapper must write them:
  /// `package:` URIs, prefixes kept.
  ///
  /// Here rather than in the generator because both come from the same parse,
  /// and because a wrapper that names a value must import whatever declares it
  /// — `2026-08-12-run-knobs-design.md` § K4.
  final List<String> imports;

  /// Parameters that could not be drawn, said out loud. A knob missing with no
  /// explanation looks like a broken tool.
  final List<String> problems;

  /// Named parameters `main` declares `required`, which make it unlaunchable.
  ///
  /// **Not knobs, and not skippable either.** A knob is optional by definition:
  /// the wrapper writes the ones somebody set and leaves the rest to their
  /// defaults, and a parameter with no default has none to leave it to. Nothing
  /// here can invent a value, so the launch is refused by name.
  ///
  /// Carried rather than merely counted because the refusal has to say *which*
  /// one. Before this the parameter was skipped silently and the wrapper took
  /// its no-knobs branch, whose `entry.main as FutureOr<void> Function()` cast
  /// cannot hold a function with a required parameter — so the app died at
  /// startup on a cast error with nothing pointing at the signature.
  final List<String> required;
}

/// Reads [entrypoint]'s `main` — names, types, defaults, and the imports a
/// wrapper calling it will need.
///
/// **Parsed, never resolved.** The same posture as the catalog scanner, and for
/// the measured reason: resolving one unit of a real project costs 17.3s
/// against 478ms to parse the whole package (`CatalogScanner`), and 5.5s on an
/// entry point that imports Flutter (`2026-08-12-run-knobs-design.md` § E4).
///
/// Per entry point rather than per package, which is the whole point: a
/// signature cannot be wrong about what its own `main` accepts, so nothing here
/// has to guess which knobs belong to which `main`. The define scan it replaces
/// could only answer per package, and put four constants belonging to
/// `main_catalog_dev.dart` on `main_dev.dart`'s launch form.
EntrypointKnobs scanEntrypointKnobs({
  required String packageRoot,
  required String entrypoint,
}) {
  var file = p.join(packageRoot, entrypoint);
  CompilationUnit unit;
  try {
    unit = parseString(
      content: File(file).readAsStringSync(),
      throwIfDiagnostics: false,
    ).unit;
  } on Object {
    // Absent or unparseable: the build will say so, in better words than a scan
    // can, and an entry point with no readable signature simply offers nothing.
    return const EntrypointKnobs();
  }

  FunctionDeclaration? main;
  for (var declaration in unit.declarations.whereType<FunctionDeclaration>()) {
    if (declaration.name.lexeme == 'main') main = declaration;
  }
  if (main == null) return const EntrypointKnobs();

  var problems = <String>[];
  var knobs = knobsFromParameters(
    main.functionExpression.parameters,
    file: file,
    lookup: EnumLookup(
      selfPackage: _packageNameOf(packageRoot),
      selfPackageRoot: packageRoot,
    ),
    onSkipped: (parameter, reason) =>
        problems.add('`$parameter` has no control: $reason'),
  );

  return EntrypointKnobs(
    knobs: knobs,
    imports: _importsOf(unit, packageRoot: packageRoot, entrypoint: entrypoint),
    problems: problems,
    required: [
      for (var parameter
          in main.functionExpression.parameters?.parameters ??
              const <FormalParameter>[])
        if (parameter.isRequired)
          if (parameter.name?.lexeme case var name? when name.isNotEmpty) name,
    ],
  );
}

/// [unit]'s imports, rewritten so they mean the same thing from anywhere.
///
/// A relative import is relative to the file holding it, and the wrapper does
/// not sit beside that file — it sits in `.dart_tool/flutterware/run/`, where
/// `import 'src/config.dart'` resolves against the wrong directory and fails to
/// compile. Measured, and it is the real layout rather than a hypothetical.
///
/// Every entry point is under `lib/` (the wrapper already requires it), so each
/// relative import has a `package:` spelling that means the same thing from
/// everywhere. `dart:` and `package:` imports are already absolute and pass
/// through untouched.
List<String> _importsOf(
  CompilationUnit unit, {
  required String packageRoot,
  required String entrypoint,
}) {
  var package = _packageNameOf(packageRoot);
  var directory = p.posix.dirname(entrypoint);
  var imports = <String>[];
  for (var directive in unit.directives.whereType<ImportDirective>()) {
    var uri = directive.uri.stringValue;
    if (uri == null) continue;
    String? resolved;
    if (uri.startsWith('dart:') || uri.startsWith('package:')) {
      resolved = uri;
    } else if (package != null) {
      var absolute = p.posix.normalize(p.posix.join(directory, uri));
      if (p.posix.isWithin('lib', absolute)) {
        resolved =
            'package:$package/${p.posix.relative(absolute, from: 'lib')}';
      }
    }
    // A relative import that climbs out of `lib/` has no `package:` spelling,
    // so there is nothing honest to write. Dropped rather than guessed: the
    // wrapper only fails to compile if a knob's type needed it, and then the
    // error names the type.
    if (resolved == null) continue;
    var prefix = directive.prefix?.name;
    imports.add("import '$resolved'${prefix == null ? '' : ' as $prefix'};");
  }
  return imports;
}

String? _packageNameOf(String packageRoot) {
  try {
    return Pubspec.parse(
      File(p.join(packageRoot, 'pubspec.yaml')).readAsStringSync(),
    ).name;
  } on Object {
    return null;
  }
}
