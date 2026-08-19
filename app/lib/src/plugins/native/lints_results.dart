import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'lints_results.g.dart';

/// `status` — every rule the SDK knows, classified against every
/// `analysis_options.yaml` in the repo.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class LintsStatusResult implements PluginResult {
  LintsStatusResult({
    this.dartVersion,
    required this.catalogAvailable,
    required this.universe,
    required this.files,
    required this.rules,
    this.unknownNames = const [],
    this.pricing,
  });

  /// The project SDK's Dart version — the tag the rule catalog was fetched at.
  final String? dartVersion;

  /// False when no catalog could be loaded (first run offline): the local
  /// buckets still stand, but nothing can be called unevaluated.
  final bool catalogAvailable;

  /// How many rules the catalog offers this SDK (stable + experimental).
  final int universe;

  final List<LintsFileSummary> files;
  final List<LintsRuleEntry> rules;

  /// Configured names the catalog does not know — typos or removed rules.
  final List<String> unknownNames;

  final LintsPricingSummary? pricing;

  @override
  Map<String, Object?> toJson() => _$LintsStatusResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class LintsFileSummary {
  LintsFileSummary({
    required this.path,
    required this.includeChain,
    required this.inheritsNothing,
    this.includeErrors = const [],
    required this.configured,
    required this.enabled,
  });

  final String path;
  final List<String> includeChain;

  /// True for a file with no `include:` — it severs inheritance, so every rule
  /// an ancestor enabled is off underneath it.
  final bool inheritsNothing;

  final List<String> includeErrors;

  /// Rules this file configures itself.
  final int configured;

  /// Rules effectively on under this file.
  final int enabled;

  Map<String, Object?> toJson() => _$LintsFileSummaryToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class LintsRuleEntry {
  LintsRuleEntry({
    required this.name,
    required this.bucket,
    this.since,
    this.state,
    this.fix,
    this.description,
    this.enabledVia,
    this.comment,
    this.files = const [],
    this.incompatible = const [],
    this.price,
  });

  final String name;

  /// `enabled`, `dismissed`, `mentioned` or `unevaluated`.
  final String bucket;

  final String? since;
  final String? state;
  final String? fix;
  final String? description;

  /// For enabled rules: the file in the chain that turned it on.
  final String? enabledVia;

  /// For dismissed rules: the comment next to the `false`, when there is one.
  final String? comment;

  /// Options files that mention or decide this rule.
  final List<String> files;

  final List<String> incompatible;

  /// Diagnostics this rule would add today — from the last pricing run, only
  /// for unevaluated rules, absent until one ran.
  final int? price;

  Map<String, Object?> toJson() => _$LintsRuleEntryToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class LintsPricingSummary {
  LintsPricingSummary({
    required this.at,
    required this.elapsedMs,
    required this.freeWins,
    required this.stale,
  });

  final String at;
  final int elapsedMs;

  /// Unevaluated rules that would add zero diagnostics today.
  final int freeWins;

  /// True when the unevaluated set changed since this run — prices still
  /// shown, but a re-run would cover the current candidates.
  final bool stale;

  Map<String, Object?> toJson() => _$LintsPricingSummaryToJson(this);
}

/// `price` — one analyzer run, every unevaluated rule priced.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class LintsPriceResult implements PluginResult {
  LintsPriceResult({
    required this.candidates,
    required this.freeWins,
    required this.elapsedMs,
    required this.counts,
  });

  final int candidates;
  final int freeWins;
  final int elapsedMs;

  /// Rule → diagnostics it would add today. Zero is the interesting value.
  final Map<String, int> counts;

  @override
  Map<String, Object?> toJson() => _$LintsPriceResultToJson(this);
}
