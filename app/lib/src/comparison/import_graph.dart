import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// What each entry reads, worked out by following its imports.
///
/// Why not ask the compiler. The daemon knows exactly what it read — and
/// cannot attribute it. Its program is the *generated entrypoint*, which
/// imports a wrapper for every entry visited so far, so the source set it
/// reports is the union of all of them; the per-compile `+`/`-` diff is a
/// delta against whatever was already loaded, not a closure. Only a fresh
/// daemon per entry would give a per-entry answer, and that is a cold compile
/// each, which is the thing the skip rule exists to avoid.
///
/// So the graph is read rather than compiled, and that turns out to be the
/// better shape rather than a concession: **it needs no daemon, no guest and
/// no compile**, so the whole skip decision runs before anything is started.
/// That is what lets a comparison put every row's verdict on screen and only
/// then begin rendering the few that need it.
///
/// Measured on this repo, `examples/example`: the first entry costs **171ms**
/// and reaches 118 files — its own, the shell's, and `package:flutterware`'s,
/// which is a path dependency inside the checkout and so counts. Every entry
/// after it costs **~1ms**, because their closures overlap and each file is
/// parsed once. A 200-entry catalog is therefore under half a second of
/// deciding, against ~100ms of rendering *per entry* it decides against.
///
/// It over-approximates and is meant to. A conditional import contributes both
/// branches; a `part` contributes; an unused import still counts. A file
/// wrongly included costs one render. A file wrongly left out reports a
/// regression as clean, and nothing downstream can detect that.
class ImportGraph {
  ImportGraph._(this.root, this._packages);

  /// The checkout everything is measured against. Files outside it are the SDK
  /// and the pub cache, which cannot change without changing something inside
  /// it — a different resolution rewrites `package_config.json`.
  final String root;

  /// Package name → its `lib/` directory, for the packages that live inside
  /// [root]. A workspace's own members and its path dependencies are in here;
  /// `package:flutter` is not.
  final Map<String, String> _packages;

  final _read = <String, _FileReads>{};

  /// Reads [packageConfig] and keeps the packages that live inside [root].
  ///
  /// A missing or unreadable config yields a graph that resolves relative
  /// imports and nothing else — degraded, not fatal: a checkout that has not
  /// been resolved yet still has files, and answering "I cannot tell" for its
  /// `package:` imports means more rendering rather than wrong rendering.
  static ImportGraph read({required String root, String? packageConfig}) {
    var packages = <String, String>{};
    var canonicalRoot = p.canonicalize(root);
    if (packageConfig != null && File(packageConfig).existsSync()) {
      try {
        var json = jsonDecode(File(packageConfig).readAsStringSync());
        // Relative to the *file's own directory* — `.dart_tool/` — which is
        // why every real config's root package reads `../`.
        var configDir = p.dirname(p.canonicalize(packageConfig));
        for (var package in (json as Map)['packages'] as List) {
          var name = (package as Map)['name'] as String;
          var rootUri = package['rootUri'] as String;
          var packageUri = package['packageUri'] as String? ?? 'lib/';
          var resolved = p.canonicalize(
            p.join(configDir, p.fromUri(Uri.parse(rootUri)), packageUri),
          );
          if (p.isWithin(canonicalRoot, resolved)) packages[name] = resolved;
        }
      } on Object {
        // A half-written config during a `pub get`. Same answer as none.
      }
    }
    return ImportGraph._(canonicalRoot, packages);
  }

  /// Every file inside [root] that [file] reads, transitively, including
  /// itself — as paths relative to [root], sorted.
  ///
  /// This is what [ClosureMemo] stores, and what the skip rule hashes on both
  /// sides.
  List<String> closureOf(String file) => [
    for (var path in _walk(file))
      if (p.isWithin(root, path)) p.relative(path, from: root),
  ]..sort();

  /// Every **package** [file] reaches, transitively — the names, not the
  /// files.
  ///
  /// The other half of [closureOf], and the half it could never carry: a
  /// closure is paths inside the checkout, and a dependency lives in the pub
  /// cache, where nothing is hashed and a version bump moves the whole
  /// directory. What identifies one is its entry in `pubspec.lock`, and what
  /// says whether *this* entry cares is whether its closure names it.
  ///
  /// Over-approximates in the same direction everything else here does: both
  /// branches of a conditional import, an unused import, a package named in a
  /// file the entry merely parts in.
  Set<String> packagesOf(String file) {
    var packages = <String>{};
    for (var path in _walk(file)) {
      packages.addAll(_readsOf(path).packages);
    }
    return packages;
  }

  /// The files [file] reads, transitively, including itself — absolute and
  /// unfiltered, which is what both public walks are built on.
  Set<String> _walk(String file) {
    var start = p.canonicalize(p.isAbsolute(file) ? file : p.join(root, file));
    var seen = <String>{};
    var queue = <String>[start];
    while (queue.isNotEmpty) {
      var current = queue.removeLast();
      if (!seen.add(current)) continue;
      for (var target in _readsOf(current).targets) {
        if (!seen.contains(target)) queue.add(target);
      }
    }
    return seen;
  }

  /// Parsed once per file: an entry's closure overlaps its neighbours' almost
  /// entirely, so a catalog of 200 entries parses a package once rather than
  /// 200 times.
  _FileReads _readsOf(String file) =>
      _read.putIfAbsent(file, () => _parse(file));

  _FileReads _parse(String file) {
    String source;
    try {
      source = File(file).readAsStringSync();
    } on FileSystemException {
      // A path an import names that is not there. The compiler will say so;
      // this is not the place, and a missing file still belongs to the
      // closure — its *absence* is what the digest records.
      return const _FileReads(targets: [], packages: {});
    }

    CompilationUnit unit;
    try {
      unit = parseString(content: source, throwIfDiagnostics: false).unit;
    } on Object {
      // Unparseable Dart. It is still a file this entry reads, so it stays in
      // the closure through its digest; what it imports is simply unknown.
      return const _FileReads(targets: [], packages: {});
    }

    var targets = <String>[];
    var packages = <String>{};
    for (var directive in unit.directives) {
      // Imports, exports **and parts**: a part is not an import but it is
      // unquestionably read, and a change to one changes the library.
      var uri = switch (directive) {
        NamespaceDirective(:var uri) => uri.stringValue,
        PartDirective(:var uri) => uri.stringValue,
        _ => null,
      };
      if (uri != null) {
        var resolved = _resolve(uri, from: file);
        if (resolved != null) targets.add(resolved);
        if (_packageIn(uri) case var named?) packages.add(named);
      }
      // Both branches of a conditional import. Which one the compiler takes
      // depends on the platform being built for, and guessing wrong here
      // drops a real dependency.
      if (directive is NamespaceDirective) {
        for (var configuration in directive.configurations) {
          var uri = configuration.uri.stringValue;
          var resolved = _resolve(uri, from: file);
          if (resolved != null) targets.add(resolved);
          if (_packageIn(uri) case var named?) packages.add(named);
        }
      }
    }
    // The assets half, and it is not an import: a package's *pictures* are
    // reached by naming it in a string — `Image.asset(…, package: 'icons')`,
    // `AssetImage('packages/icons/x.png')`, a font family spelled
    // `packages/icons/Inter`. A bump to that package changes what an entry
    // draws while its import graph says nothing at all.
    var strings = _PackageStrings();
    unit.accept(strings);
    packages.addAll(strings.names);
    return _FileReads(targets: targets, packages: packages);
  }

  /// The package a `package:name/…` URI names, or null for anything else.
  static String? _packageIn(String? uri) {
    if (uri == null || !uri.startsWith('package:')) return null;
    var rest = uri.substring('package:'.length);
    var slash = rest.indexOf('/');
    return slash < 0 ? null : rest.substring(0, slash);
  }

  /// A directive's URI as an absolute path inside [root], or null for anything
  /// outside it — `dart:`, a pub-cache package, an unresolvable name.
  String? _resolve(String? uri, {required String from}) {
    if (uri == null || uri.isEmpty) return null;
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      var rest = uri.substring('package:'.length);
      var slash = rest.indexOf('/');
      if (slash < 0) return null;
      var lib = _packages[rest.substring(0, slash)];
      if (lib == null) return null;
      return p.canonicalize(p.join(lib, rest.substring(slash + 1)));
    }
    if (uri.contains(':')) return null;
    var resolved = p.canonicalize(p.join(p.dirname(from), p.fromUri(uri)));
    return p.isWithin(root, resolved) ? resolved : null;
  }
}

/// What one file was found to read: the files, and the packages it names.
class _FileReads {
  const _FileReads({required this.targets, required this.packages});

  final List<String> targets;
  final Set<String> packages;
}

/// The two ways a Dart file names a package it does not import.
///
/// Deliberately these two and not "every string that happens to be a package
/// name": `path`, `collection`, `clock`, `http` and `image` are all packages
/// *and* ordinary words, and matching them anywhere would put half a catalog
/// back inside every lockfile bump — which is the thing the narrowing exists
/// to stop.
class _PackageStrings extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitArgumentList(ArgumentList node) {
    // `package: 'icons'` — Flutter's own spelling, on `Image.asset`,
    // `AssetImage`, `SvgPicture.asset` and everything shaped like them.
    for (var argument in node.arguments) {
      if (argument is! NamedArgument) continue;
      if (argument.name.lexeme != 'package') continue;
      if (argument.argumentExpression case StringLiteral literal) {
        if (literal.stringValue case var value?) names.add(value);
      }
    }
    super.visitArgumentList(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    // `packages/icons/x.png` — what the bundle calls another package's asset,
    // and what a font family from one is spelled as.
    const prefix = 'packages/';
    var value = node.value;
    if (value.startsWith(prefix)) {
      var rest = value.substring(prefix.length);
      var slash = rest.indexOf('/');
      if (slash > 0) names.add(rest.substring(0, slash));
    }
    super.visitSimpleStringLiteral(node);
  }
}
