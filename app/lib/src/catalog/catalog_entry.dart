import 'package:json_annotation/json_annotation.dart';

part 'catalog_entry.g.dart';

/// One addressable catalog entry.
///
/// Discovery does not exist yet, so these are supplied by hand — see
/// `stub_entries.dart`. The shape is what a syntactic scan will produce: a
/// path, a symbol, and the annotation's source text, never its meaning.
@JsonSerializable()
class CatalogEntry {
  const CatalogEntry({
    required this.path,
    required this.symbol,
    required this.annotation,
    required this.name,
    this.group,
    this.declaredId,
    this.formFactor,
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> json) =>
      _$CatalogEntryFromJson(json);

  /// Project-relative path of the declaring file. Relative, never absolute:
  /// an absolute path would make a generated file machine-specific.
  final String path;

  /// The annotated top-level function.
  final String symbol;

  /// The annotation's source text with the `@` stripped — `Demo(name: 'x')`.
  /// Emitted verbatim into generated code and evaluated as Dart; nothing here
  /// interprets it.
  final String annotation;

  /// Display name, from a literal `name:` argument, else the symbol.
  final String name;

  /// One tree level between the directory and the leaf.
  ///
  /// Declared by `group:`, or derived from the filename when a file holds more
  /// than one entry — so variants get a parent with no ceremony.
  final String? group;

  /// An `id:` on the annotation, pinning identity across renames and moves.
  final String? declaredId;

  /// The `formFactor:` enum name as written — `mobile`, `desktop`, `all` —
  /// or null when the annotation says nothing.
  ///
  /// A name, not a `FormFactor`: that enum carries a `Size` and so lives in a
  /// Flutter library, and everything on this side of the wire has to stay
  /// plain Dart for the daemon and the CLI to keep reading it.
  final String? formFactor;

  /// Identity: derived from path and symbol unless the annotation pins it.
  ///
  /// Optional rather than required because nothing holds an id yet and the
  /// derivation is unambiguous — except where several annotations sit on one
  /// declaration, which the scanner rejects rather than silently collapses.
  String get id => declaredId ?? '$path#$symbol';

  CatalogEntry withGroup(String group) => CatalogEntry(
    path: path,
    symbol: symbol,
    annotation: annotation,
    name: name,
    group: group,
    declaredId: declaredId,
    formFactor: formFactor,
  );

  Map<String, dynamic> toJson() => _$CatalogEntryToJson(this);
}
