import 'package:flutterware/channels.dart';
import 'package:json_annotation/json_annotation.dart';

part 'catalog_entry.g.dart';

/// One addressable catalog entry.
///
/// Produced by the syntactic scan in `discovery.dart`: a path, a symbol, and
/// the annotation's source text, never its meaning. Resolution is the guest's
/// job — the scan sees a declaration, not what it evaluates to.
@JsonSerializable()
class CatalogEntry {
  const CatalogEntry({
    required this.path,
    required this.symbol,
    required this.annotation,
    required this.name,
    this.group,
    this.declaredId,
    this.ordinal = 0,
    this.knobs = const [],
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> json) =>
      _$CatalogEntryFromJson(json);

  /// Project-relative path of the declaring file. Relative, never absolute:
  /// an absolute path would make a generated file machine-specific.
  final String path;

  /// The annotated top-level function.
  final String symbol;

  /// The controls this entry's *signature* declares, read without running it.
  ///
  /// Empty means the signature declares none, not that it went unread. An entry
  /// can still declare knobs at runtime by reading `context.uiCatalog`, and
  /// those cost a compile and a frame to learn; these cost a parse. The two
  /// coexist deliberately (`2026-07-27-knobs-static-and-runtime.md`).
  final List<KnobDescriptor> knobs;

  /// The annotation's source text with the `@` stripped — `Preview(name: 'x')`.
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
  ///
  /// Read by *name*, off whatever annotation the project registered — nothing
  /// flutterware ships declares it. A project wanting identity to survive a
  /// rename writes its own `Preview` subclass carrying an `id:`.
  final String? declaredId;

  /// Identity: derived from path and symbol unless the annotation pins it.
  ///
  /// [ordinal] disambiguates several annotations stacked on one declaration,
  /// which is one of the two ways to spell variants and would otherwise derive
  /// one id for all of them. It follows the *position*, so reordering a stack
  /// moves the ids with it — the cost of the derivation being free, and the
  /// reason `id:` is still read.
  String get id =>
      declaredId ?? (ordinal == 0 ? '$path#$symbol' : '$path#$symbol#$ordinal');

  /// Which annotation on the declaration this is, in source order.
  final int ordinal;

  /// The same entry, filed under [group].
  ///
  /// Every field is carried, and [knobs] is why this comment exists: it used to
  /// be omitted, and the only entries that go through here are the ones in a
  /// file holding more than one — so a preview lost the controls its signature
  /// declared for the sole reason that it had a sibling. Nothing said so; the
  /// panel simply had no knobs to draw.
  CatalogEntry withGroup(String group) => CatalogEntry(
    path: path,
    symbol: symbol,
    annotation: annotation,
    name: name,
    group: group,
    declaredId: declaredId,
    ordinal: ordinal,
    knobs: knobs,
  );

  Map<String, dynamic> toJson() => _$CatalogEntryToJson(this);
}
