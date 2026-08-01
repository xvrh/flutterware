import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import 'authoring.dart';
import 'catalog_entry.dart';

/// How a scan went: what it found, and what it noticed but did not act on.
class ScanResult {
  ScanResult({required this.entries, required this.diagnostics});

  final List<CatalogEntry> entries;

  final List<ScanDiagnostic> diagnostics;

  /// A scan with an error is not a usable catalog: an entry would be missing or
  /// unreachable, which is worse than refusing.
  bool get ok => diagnostics.every((d) => !d.isError);
}

class ScanDiagnostic {
  ScanDiagnostic.error(this.message, {this.location}) : isError = true;
  ScanDiagnostic.warning(this.message, {this.location}) : isError = false;

  final String message;
  final String? location;
  final bool isError;

  @override
  String toString() => location == null ? message : '$location: $message';
}

/// Finds catalog entries by **parsing** the project, never by resolving or
/// compiling it.
///
/// Resolution costs 17.3s for a single unit on a real project against 478ms to
/// parse the whole package, and buys nothing here: nobody — not us, not
/// Flutter's own previewer — interprets a preview annotation statically. The
/// annotation's source text is carried through to the guest and evaluated as
/// Dart there. See `2026-07-26-widget-previews-integration-findings.md`.
class CatalogScanner {
  CatalogScanner({
    required this.projectRoot,
    this.roots = const [defaultCatalogDirectory],
    this.previewAnnotations = defaultPreviewAnnotations,
  });

  /// Entry paths are recorded relative to this, so a generated file is the same
  /// on every machine.
  final String projectRoot;

  /// Directories to scan, relative to [projectRoot].
  final List<String> roots;

  /// Recognition is by **registration**, not by inference. The class-hierarchy
  /// closure that would let a project's own `Tablet extends Preview` be detected
  /// automatically was cut: name-filtering already discards the noise it was
  /// meant to filter, and an unregistered annotation shows up immediately as a
  /// missing entry.
  final List<String> previewAnnotations;

  ScanResult scan() {
    var entries = <CatalogEntry>[];
    var diagnostics = <ScanDiagnostic>[];
    var multiPreviews = <String, String>{};

    for (var file in _dartFiles()) {
      var source = file.readAsStringSync();
      // A substring prefilter before parsing: 20ms across 180 files, against
      // 478ms to parse them. `MultiPreview` joins the annotations rather than
      // riding along with them, because the class that extends it is routinely
      // declared in a file that holds no entries of its own.
      if (!previewAnnotations.any((a) => source.contains('@$a')) &&
          !source.contains('MultiPreview')) {
        continue;
      }
      _scanFile(file, source, entries, diagnostics, multiPreviews);
    }

    _deriveGroups(entries);
    _rejectDuplicateIds(entries, diagnostics);
    _reportMultiPreviews(multiPreviews, diagnostics);
    entries.sort((a, b) => a.id.compareTo(b.id));
    return ScanResult(entries: entries, diagnostics: diagnostics);
  }

  /// What the roots look like from outside, without reading or parsing
  /// anything: every `.dart` file and when it was last written.
  ///
  /// A stand-in for "is a rescan worth it". Listing is a millisecond where the
  /// scan behind it reads and parses, and a daemon that rescanned on every
  /// request just in case somebody added a demo would put that on the reload
  /// loop, which is the one thing that has to stay quick.
  String fingerprint() {
    var files = [
      for (var file in _dartFiles())
        '${file.path}:${file.statSync().modified.microsecondsSinceEpoch}',
    ]..sort();
    return files.join('\n');
  }

  Iterable<File> _dartFiles() sync* {
    for (var root in roots) {
      var directory = Directory(p.join(projectRoot, root));
      if (!directory.existsSync()) continue;
      for (var entity in directory.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) yield entity;
      }
    }
  }

  void _scanFile(
    File file,
    String source,
    List<CatalogEntry> entries,
    List<ScanDiagnostic> diagnostics,
    Map<String, String> multiPreviews,
  ) {
    var unit = parseString(content: source, throwIfDiagnostics: false).unit;
    var path = p.split(p.relative(file.path, from: projectRoot)).join('/');

    for (var declaration in unit.declarations) {
      if (declaration is ClassDeclaration &&
          declaration.extendsClause?.superclass.name.lexeme == 'MultiPreview') {
        multiPreviews[declaration.namePart.typeName.lexeme] = path;
      }
      switch (declaration) {
        case FunctionDeclaration():
          var annotations = _annotationsOn(declaration.metadata);
          if (annotations.isEmpty) continue;
          if (!_returnsWidget(declaration.returnType)) {
            diagnostics.add(
              ScanDiagnostic.warning(
                '${declaration.name.lexeme} is annotated but does not return '
                'Widget or WidgetBuilder',
                location: path,
              ),
            );
          }
          for (var (ordinal, annotation) in annotations.indexed) {
            _add(
              entries,
              diagnostics,
              path,
              declaration.name.lexeme,
              annotation,
              declaration.functionExpression.parameters,
              ordinal,
            );
          }

        case ClassDeclaration():
          for (var member in declaration.body.members) {
            var annotations = _annotationsOn(member.metadata);
            if (annotations.isEmpty) continue;
            var className = declaration.namePart.typeName.lexeme;
            switch (member) {
              // `Foo` names the type; `Foo.new` is the tear-off, which is what
              // the generated wrapper needs.
              case ConstructorDeclaration(:var name, :var parameters):
                for (var (ordinal, annotation) in annotations.indexed) {
                  _add(
                    entries,
                    diagnostics,
                    path,
                    '$className.${name?.lexeme ?? 'new'}',
                    annotation,
                    parameters,
                    ordinal,
                  );
                }
              case MethodDeclaration(
                isStatic: true,
                :var name,
                :var parameters,
              ):
                for (var (ordinal, annotation) in annotations.indexed) {
                  _add(
                    entries,
                    diagnostics,
                    path,
                    '$className.${name.lexeme}',
                    annotation,
                    parameters,
                    ordinal,
                  );
                }
              default:
                diagnostics.add(
                  ScanDiagnostic.warning(
                    'an annotation on a non-static member of $className is not '
                    'a catalog entry',
                    location: path,
                  ),
                );
            }
          }

        default:
          break;
      }
    }
  }

  void _add(
    List<CatalogEntry> entries,
    List<ScanDiagnostic> diagnostics,
    String path,
    String symbol,
    Annotation annotation,
    FormalParameterList? parameters,
    int ordinal,
  ) {
    // `@Preview`'s own rule: the target must be callable with no arguments.
    var required =
        parameters?.parameters.where((p) => p.isRequired) ?? const [];
    if (required.isNotEmpty) {
      diagnostics.add(
        ScanDiagnostic.error(
          '$symbol has required parameters, so it cannot be a catalog entry',
          location: path,
        ),
      );
      return;
    }

    entries.add(
      CatalogEntry(
        path: path,
        symbol: symbol,
        // Verbatim, `@` stripped. Never interpreted here.
        annotation: annotation.toSource().substring(1),
        name: _literalString(annotation, 'name') ?? symbol,
        declaredId: _literalString(annotation, 'id'),
        group: _literalString(annotation, 'group'),
        ordinal: ordinal,
      ),
    );
  }

  /// A file holding more than one entry gives its entries a group, so variants
  /// get a parent without anyone declaring one. `group:` overrides it.
  void _deriveGroups(List<CatalogEntry> entries) {
    var byFile = <String, List<CatalogEntry>>{};
    for (var entry in entries) {
      byFile.putIfAbsent(entry.path, () => []).add(entry);
    }
    for (var MapEntry(key: path, value: fileEntries) in byFile.entries) {
      if (fileEntries.length < 2) continue;
      var derived = _humanize(p.basenameWithoutExtension(path));
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.path != path || entry.group != null) continue;
        entries[i] = entry.withGroup(derived);
      }
    }
  }

  /// Two entries resolving to one id means one of them is unreachable. That is
  /// a broken tree, not something to note and carry on from — the one place
  /// this design escalates from reporting to refusing.
  ///
  /// Only a *declared* `id:` can do this now. Stacked annotations used to
  /// collide here, which made an `id:` mandatory precisely where variants are
  /// spelled; they take an ordinal instead.
  void _rejectDuplicateIds(
    List<CatalogEntry> entries,
    List<ScanDiagnostic> diagnostics,
  ) {
    var byId = <String, List<CatalogEntry>>{};
    for (var entry in entries) {
      byId.putIfAbsent(entry.id, () => []).add(entry);
    }
    for (var MapEntry(key: id, value: clashing) in byId.entries) {
      if (clashing.length < 2) continue;
      diagnostics.add(
        ScanDiagnostic.error(
          '${clashing.length} entries resolve to the same id "$id" '
          '(${clashing.map((e) => e.name).join(', ')}). '
          'Give all but one an explicit id.',
          location: clashing.first.path,
        ),
      );
    }
  }

  /// `MultiPreview` is Flutter's one-annotation-many-previews base class, and
  /// nothing here can serve it: it hands back its previews from a `previews`
  /// getter, evaluated as Dart, while every entry the catalog knows about is
  /// resolved from the source before anything runs.
  ///
  /// **Registered ones only**, which is the whole of what this can honestly
  /// answer. Registered, a `MultiPreview` reaches the generated wrapper as
  /// `Preview get fwPreview => BrightnessPreview()` and fails to compile, pointing
  /// at generated code rather than at the declaration that caused it — so
  /// refusing here, by name, is strictly better than the same failure later.
  ///
  /// Unregistered, an annotation naming one is never seen and its previews are
  /// missing with no mention of why. That is worth saying and is *not said
  /// here*: knowing the name is used would mean parsing files the prefilter
  /// skips, which is the 20ms-against-478ms property the scan is built on.
  /// Warning off the declaration alone would fire on a subclass serving
  /// Flutter's own previewer perfectly well — this scanner volunteering an
  /// opinion about a file it has no stake in, from a bare-name match.
  void _reportMultiPreviews(
    Map<String, String> multiPreviews,
    List<ScanDiagnostic> diagnostics,
  ) {
    for (var MapEntry(key: name, value: path) in multiPreviews.entries) {
      if (!previewAnnotations.contains(name)) continue;
      diagnostics.add(
        ScanDiagnostic.error(
          '$name extends MultiPreview, which declares its previews at run '
          'time — the catalog resolves entries from the source, so it cannot '
          'know what one expands to. Remove it from previewAnnotations and '
          'write one @Preview per entry.',
          location: path,
        ),
      );
    }
  }

  /// Every registered annotation on a declaration, not just the first.
  ///
  /// Stacking is one of the two supported ways to spell variants, so two
  /// `@Preview`s are two entries, told apart by their position on the
  /// declaration.
  List<Annotation> _annotationsOn(List<Annotation> metadata) => [
    for (var annotation in metadata)
      if (previewAnnotations.contains(annotation.name.name)) annotation,
  ];

  static bool _returnsWidget(TypeAnnotation? type) {
    if (type == null) return true; // Inferred; the compiler will judge it.
    var name = type is NamedType ? type.name.lexeme : type.toSource();
    return name == 'Widget' || name == 'WidgetBuilder';
  }

  /// Literal arguments are read here; anything else is left for the guest to
  /// evaluate, which is why `size: kSomething` costs nothing.
  static String? _literalString(Annotation annotation, String parameter) {
    for (var argument
        in annotation.arguments?.arguments ?? const <Argument>[]) {
      if (argument is! NamedArgument) continue;
      if (argument.name.lexeme != parameter) continue;
      var value = argument.argumentExpression;
      if (value is SimpleStringLiteral) return value.value;
    }
    return null;
  }

  static String _humanize(String fileName) {
    var words = fileName.split('_').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return fileName;
    return [
      words.first[0].toUpperCase() + words.first.substring(1),
      ...words.skip(1),
    ].join(' ');
  }
}
