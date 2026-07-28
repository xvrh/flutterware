import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'ui_catalog_results.g.dart';

/// What the UI catalog's actions hand back.
///
/// Classes rather than hand-built maps, for three reasons that all showed up in
/// this plugin: the compiler checks a field name and does not check `'entires'`;
/// `toJson` is generated from the fields, so the wire form cannot drift from
/// the type; and the *shape* of each class is extracted statically into
/// `docs/capabilities.md`, so a field added here is documented without anyone
/// remembering to.
///
/// Nullability is load-bearing. A shape derived from sample output can only say
/// which fields happened to be present; these say which are optional, which is
/// the difference between "this package has no error" and "this package cannot
/// have one".

/// `entries` — every catalog entry, per declared package.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogEntriesResult implements PluginResult {
  CatalogEntriesResult({required this.packages});

  final List<CatalogPackageEntries> packages;

  @override
  Map<String, Object?> toJson() => _$CatalogEntriesResultToJson(this);
}

/// One package's entries, or why they could not be read.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogPackageEntries {
  CatalogPackageEntries({
    required this.path,
    this.entries = const [],
    this.diagnostics = const [],
    this.error,
  });

  /// Package path as declared in `tool/flutterware.dart`.
  final String path;

  final List<CatalogEntrySummary> entries;

  /// Discovery's complaints — a duplicate id, an uncallable target.
  final List<String> diagnostics;

  /// Set when the scan failed, in which case [entries] is empty and means
  /// nothing.
  final String? error;

  Map<String, Object?> toJson() => _$CatalogPackageEntriesToJson(this);
}

/// One entry, as every surface identifies it.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogEntrySummary {
  CatalogEntrySummary({
    required this.id,
    required this.name,
    required this.address,
    this.group,
    this.formFactor,
  });

  /// What `screenshot --entry` and `describe --entry` take.
  final String id;

  final String name;

  /// The `Address`, rendered — hand it back to `screenshot`, or later `show`.
  final String address;

  /// One tree level between the directory and the leaf, when the entry
  /// declares or derives one.
  final String? group;

  /// `mobile`, `desktop`, `all` — what the demo says it is *for*, when it says.
  final String? formFactor;

  Map<String, Object?> toJson() => _$CatalogEntrySummaryToJson(this);
}

/// `check` — what the compiler can and cannot build.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogCheckResult implements PluginResult {
  CatalogCheckResult({required this.packages});

  final List<CatalogPackageCheck> packages;

  @override
  Map<String, Object?> toJson() => _$CatalogCheckResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogPackageCheck {
  CatalogPackageCheck({
    required this.path,
    this.ok = false,
    this.servable = const [],
    this.broken = const [],
    this.error,
  });

  final String path;

  /// True when nothing is quarantined.
  final bool ok;

  /// Entry ids the compiler built.
  final List<String> servable;

  final List<CatalogBrokenEntry> broken;

  /// Set when the daemon could not be reached at all, which is not the same as
  /// "everything failed to compile".
  final String? error;

  Map<String, Object?> toJson() => _$CatalogPackageCheckToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogBrokenEntry {
  CatalogBrokenEntry({required this.id, required this.error});

  final String id;

  /// The compiler's diagnostics, verbatim.
  final String error;

  Map<String, Object?> toJson() => _$CatalogBrokenEntryToJson(this);
}

/// `describe` — one entry, and optionally the knobs it declares.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogEntryDescription implements PluginResult {
  CatalogEntryDescription({
    required this.id,
    required this.name,
    required this.package,
    required this.file,
    required this.symbol,
    required this.annotation,
    required this.address,
    this.group,
    this.formFactor,
    this.knobs,
  });

  final String id;
  final String name;

  /// Which declared package holds it.
  final String package;

  /// Project-relative path of the declaring file.
  final String file;

  /// The annotated top-level function.
  final String symbol;

  /// The annotation's source text, verbatim — `Demo(name: 'Counter')`.
  final String annotation;

  final String address;
  final String? group;
  final String? formFactor;

  /// Present only when `--knobs` asked for them: reading a knob costs a
  /// compile and a frame, so absent means "not looked at" while an empty list
  /// means "this entry declares none".
  final List<CatalogKnob>? knobs;

  @override
  Map<String, Object?> toJson() => _$CatalogEntryDescriptionToJson(this);
}

/// One control an entry offers, flattened for the wire.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogKnob {
  CatalogKnob({
    required this.name,
    required this.kind,
    this.value,
    this.defaultValue,
    this.min,
    this.max,
    this.options = const [],
  });

  final String name;

  /// `string`, `boolean`, `integer`, `number`, `picker`.
  final String kind;

  /// What it is currently set to.
  final Object? value;

  /// What the demo renders with when nothing is set — also what it shows
  /// outside the catalog.
  @JsonKey(name: 'default')
  final Object? defaultValue;

  /// Bounds, when the demo gave any. Both present is a slider.
  final num? min;
  final num? max;

  /// A picker's labels, in declaration order.
  final List<String> options;

  Map<String, Object?> toJson() => _$CatalogKnobToJson(this);
}
