import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import 'import_walker.dart' show vmEnvironment;

/// What an [EnumLookup] found for one type name, or why it found nothing.
///
/// Never both: a lookup that cannot say with certainty which declaration a name
/// refers to reports the problem rather than picking. The caller's move on a
/// problem is to leave the knob out and say so — `KnobKind`'s own rule, that a
/// knob rendered as the wrong control is worse than one the panel admits it
/// cannot show.
class EnumValues {
  const EnumValues.found(this.values, this.declaredIn) : problem = null;

  const EnumValues.problem(this.problem) : values = const [], declaredIn = null;

  /// The constants, in declaration order — `['dev', 'staging', 'prod']`.
  ///
  /// Names only. A value with arguments (`low(1)`) is still just `low` here,
  /// because the name is all a picker offers and all the wrapper needs to write.
  final List<String> values;

  /// Absolute path of the file declaring the enum. Null when [problem] is set.
  final String? declaredIn;

  /// Why there are no [values], in a sentence that says what to do.
  final String? problem;

  bool get found => problem == null;
}

/// Finds an `enum`'s constants by parsing, without resolving the program.
///
/// **Why not the analyzer.** Asking for a resolved unit answers this perfectly
/// and costs 5.5s on an entry point that imports Flutter, 9.9s on this GUI's own
/// (measured 2026-08-12, `2026-08-12-run-knobs-design.md` § E4). A launch form
/// cannot pay that, and neither can a catalog scan that has deliberately stayed
/// syntactic.
///
/// **The bound is what makes it honest.** The search covers the file itself and
/// the *exported namespace* of each of its direct imports — `export` followed
/// transitively, because a barrel (`export 'src/backend.dart';`) is what people
/// actually write, but `import` chains never. A name that is not there is
/// reported as not found rather than hunted for, so the cost of a lookup is
/// bounded by the file's own import list.
///
/// Shared deliberately: entry-point knobs and catalog demos ask the identical
/// question of the identical AST, and
/// `docs/superpowers/specs/2026-07-27-knobs-static-and-runtime.md` left it open
/// for demos before entry points existed. Two answers would be two behaviours
/// for one word.
class EnumLookup {
  EnumLookup({this.packageConfig, this.selfPackage, this.selfPackageRoot});

  /// Resolves `package:` URIs. Without one, only relative imports and
  /// [selfPackage] are followed, and everything else reports honestly.
  final PackageConfig? packageConfig;

  /// The name of the package being scanned, so `package:myapp/src/models.dart`
  /// resolves without a config at all.
  ///
  /// Worth its own field because a package importing *itself* by `package:` URI
  /// is the common case in real code, and loading a `PackageConfig` is async
  /// while both scanners that need this are not.
  final String? selfPackage;

  /// [selfPackage]'s directory — the one holding its `lib/`.
  final String? selfPackageRoot;

  final _libraries = <String, _Library>{};

  /// The constants of [name], as referred to from [file].
  ///
  /// [prefix] is the import prefix the type was written with — `m` in
  /// `m.Backend`, null for a bare `Backend`. It narrows the search rather than
  /// decorating it: a prefixed name can only come from the import carrying that
  /// prefix, and an unprefixed one can never come from a prefixed import.
  EnumValues lookup({
    required String file,
    required String name,
    String? prefix,
  }) {
    var root = _libraryAt(p.normalize(p.absolute(file)));
    if (root == null) {
      return EnumValues.problem('$file could not be read');
    }

    // A declaration in the file itself shadows anything imported, so finding it
    // here is an answer rather than a candidate.
    if (prefix == null) {
      if (root.enums[name] case var values?) {
        return EnumValues.found(values, root.path);
      }
    }

    // Keyed by the file that declares it: one enum reached through both a
    // barrel and its own file is one enum, not an ambiguity. That shape is
    // common enough that treating it as a conflict would refuse ordinary code.
    var hits = <String, List<String>>{};
    for (var import in root.imports) {
      if (import.prefix != prefix) continue;
      if (!import.combinators.allows(name)) continue;
      var target = _resolve(import.uri, from: root.path);
      if (target == null) continue;
      var found = _searchExports(target, name, {});
      if (found != null) hits[found.path] = found.values;
    }

    return switch (hits.length) {
      1 => EnumValues.found(hits.values.single, hits.keys.single),
      0 => EnumValues.problem(
        'no enum $name in ${p.basename(root.path)} or its direct imports. '
        'Declare it there, or export it from a file that entry point already '
        'imports.',
      ),
      _ => EnumValues.problem(
        'enum $name is reachable from ${p.basename(root.path)} through '
        '${hits.length} different declarations '
        '(${hits.keys.map(p.basename).join(', ')}). Import one of them, or '
        'name it with a prefix.',
      ),
    };
  }

  /// The enum called [name] in [path]'s exported namespace, or null.
  ///
  /// Follows `export` and honours its combinators, so a barrel that re-exports
  /// half of a file offers exactly that half. [seen] guards the cycle a pair of
  /// mutually exporting libraries would otherwise make.
  ({String path, List<String> values})? _searchExports(
    String path,
    String name,
    Set<String> seen,
  ) {
    if (!seen.add(path)) return null;
    var library = _libraryAt(path);
    if (library == null) return null;
    if (library.enums[name] case var values?) {
      return (path: library.path, values: values);
    }
    for (var export in library.exports) {
      if (!export.combinators.allows(name)) continue;
      var target = _resolve(export.uri, from: library.path);
      if (target == null) continue;
      if (_searchExports(target, name, seen) case var found?) return found;
    }
    return null;
  }

  /// A directive's URI as an absolute file path, or null for anything this
  /// cannot follow — `dart:` libraries, and `package:` URIs with no config to
  /// resolve them.
  String? _resolve(String uri, {required String from}) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      var parsed = Uri.parse(uri);
      if (parsed.pathSegments.firstOrNull == selfPackage &&
          selfPackageRoot != null) {
        return p.normalize(
          p.joinAll([selfPackageRoot!, 'lib', ...parsed.pathSegments.skip(1)]),
        );
      }
      var resolved = packageConfig?.resolve(parsed);
      return resolved == null ? null : p.normalize(resolved.toFilePath());
    }
    return p.normalize(p.join(p.dirname(from), uri));
  }

  _Library? _libraryAt(String path) {
    if (_libraries[path] case var cached?) return cached;
    var unit = _parse(path);
    if (unit == null) return null;

    var library = _Library(path);
    _collect(unit, library);
    // A `part` is the same library, so its declarations are this library's.
    // Worth the extra reads: generator output routinely lands in one.
    for (var directive in unit.directives.whereType<PartDirective>()) {
      var target = _uriOf(directive);
      if (target == null) continue;
      var partPath = _resolve(target, from: path);
      if (partPath == null) continue;
      var part = _parse(partPath);
      if (part != null) _collect(part, library, directivesToo: false);
    }
    return _libraries[path] = library;
  }

  void _collect(
    CompilationUnit unit,
    _Library into, {
    bool directivesToo = true,
  }) {
    for (var declaration in unit.declarations.whereType<EnumDeclaration>()) {
      // `namePart` / `body.constants` rather than `name` / `constants`: the
      // analyzer moved both behind those in 13.x, and a primary constructor is
      // now one of the shapes a name part can take.
      into.enums[declaration.namePart.typeName.lexeme] = [
        for (var constant in declaration.body.constants)
          // Dropped rather than offered: the parser recovers `enum X { a,,, }`
          // into constants with empty names, and a picker with blank options is
          // worse than a shorter one. Measured — recovery is why a broken file
          // still answers at all.
          if (constant.name.lexeme.isNotEmpty) constant.name.lexeme,
      ];
    }
    if (!directivesToo) return;
    for (var directive in unit.directives) {
      var uri = _uriOf(directive);
      if (uri == null) continue;
      switch (directive) {
        case ImportDirective():
          into.imports.add(
            _Directive(
              uri,
              prefix: directive.prefix?.name,
              combinators: _Combinators.of(directive.combinators),
            ),
          );
        case ExportDirective():
          into.exports.add(
            _Directive(
              uri,
              combinators: _Combinators.of(directive.combinators),
            ),
          );
        default:
          break;
      }
    }
  }

  /// The URI a directive names, resolving a conditional one the way the VM
  /// target would — the rule [ImportWalker] already follows, kept identical so
  /// two walks of the same program cannot disagree about which branch is real.
  String? _uriOf(Directive directive) {
    if (directive is! NamespaceDirective) {
      return directive is PartDirective ? directive.uri.stringValue : null;
    }
    for (var configuration in directive.configurations) {
      var expected = configuration.value?.stringValue ?? 'true';
      if (vmEnvironment['${configuration.name}'] == expected) {
        return configuration.uri.stringValue ?? directive.uri.stringValue;
      }
    }
    return directive.uri.stringValue;
  }

  CompilationUnit? _parse(String path) {
    try {
      return parseString(
        content: File(path).readAsStringSync(),
        throwIfDiagnostics: false,
      ).unit;
    } on Object {
      // Absent, or a file that will not parse — which cannot be built either,
      // and the compiler says so better than a scan can.
      return null;
    }
  }
}

class _Library {
  _Library(this.path);

  final String path;
  final enums = <String, List<String>>{};
  final imports = <_Directive>[];
  final exports = <_Directive>[];
}

class _Directive {
  _Directive(this.uri, {this.prefix, required this.combinators});

  final String uri;
  final String? prefix;
  final _Combinators combinators;
}

/// A directive's `show` / `hide`.
///
/// Honoured rather than ignored, and cheaply — they are syntax. Ignoring them
/// would be safe for correctness but not for temper: a name hidden on one route
/// and shown on another would look like two declarations and be refused as
/// ambiguous, in a program that compiles perfectly.
class _Combinators {
  _Combinators(this.shown, this.hidden);

  factory _Combinators.of(List<Combinator> combinators) {
    Set<String>? shown;
    var hidden = <String>{};
    for (var combinator in combinators) {
      switch (combinator) {
        case ShowCombinator():
          (shown ??= {}).addAll(combinator.shownNames.map((name) => name.name));
        case HideCombinator():
          hidden.addAll(combinator.hiddenNames.map((name) => name.name));
      }
    }
    return _Combinators(shown, hidden);
  }

  final Set<String>? shown;
  final Set<String> hidden;

  bool allows(String name) =>
      (shown?.contains(name) ?? true) && !hidden.contains(name);
}
