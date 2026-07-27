/// One addressable catalog entry.
///
/// Discovery does not exist yet, so these are supplied by hand — see
/// `tool/catalog/stub_entries.dart`. The shape is what a syntactic scan will
/// produce: a path, a symbol, and the annotation's source text, never its
/// meaning.
class CatalogEntry {
  const CatalogEntry({
    required this.path,
    required this.symbol,
    required this.annotation,
    required this.name,
  });

  /// Project-relative path of the declaring file. Relative, never absolute:
  /// an absolute path would make a generated file machine-specific.
  final String path;

  /// The annotated top-level function.
  final String symbol;

  /// The annotation's source text with the `@` stripped — `Demo(name: 'x')`.
  /// Emitted verbatim into generated code and evaluated as Dart; nothing here
  /// interprets it.
  final String annotation;

  /// Display name. A real scan reads this from a literal `name:` argument.
  final String name;

  /// Identity: derived from path and symbol unless the annotation pins it.
  String get id => '$path#$symbol';
}
