import 'package:flutterware/comparison_report.dart';

/// One thing a reader has said they do not want to see.
///
/// A **conjunction** from the start, though v1.5 only ever builds rules of one
/// constraint. That is the seam the staging rests on: clicking the `system`
/// chip and authoring *db events out of `cache.dart`* produce the same record
/// with a different number of constraints, so the second is a longer rule
/// rather than a different feature. Design:
/// `docs/superpowers/specs/2026-08-30-comparison-ui-pass-design.md` §3, §3a.
class ComparisonRule {
  const ComparisonRule(this.constraints);

  /// One constraint, the common case, spelled so a caller does not build a
  /// list for it.
  ComparisonRule.on(String facet, String value)
    : constraints = [RuleConstraint(facet, value)];

  /// ANDed. An empty list would match everything, which is why nothing here
  /// constructs one.
  final List<RuleConstraint> constraints;

  bool matches(ChannelDelta delta) =>
      constraints.isNotEmpty &&
      constraints.every((constraint) => constraint.matches(delta));

  /// How a chip spells it: `system`, `db · cache.dart`.
  String get label => constraints.map((c) => c.value).join(' · ');

  bool get isSingle => constraints.length == 1;

  bool sameAs(ComparisonRule other) =>
      constraints.length == other.constraints.length &&
      constraints.every(
        (mine) => other.constraints.any(
          (theirs) => theirs.facet == mine.facet && theirs.value == mine.value,
        ),
      );
}

/// One facet of a delta, pinned to one value.
class RuleConstraint {
  const RuleConstraint(this.facet, this.value);

  /// `channel`, `subchannel`, `property` or `origin` — the facets the model
  /// records. See the events design note §9.
  final String facet;
  final String value;

  bool matches(ChannelDelta delta) => switch (facet) {
    'channel' => delta.channel == value,
    'subchannel' => delta.subchannel == value,
    'property' => delta.property == value,
    'origin' => delta.origin == value,
    _ => false,
  };
}

/// The rules in force, and what they do to a comparison.
///
/// **It decides what a list shows, never what a comparison found.** Nothing
/// here reaches the artifact: `index.json` is written whole, so a `tool/`
/// script reads the same verdict whatever anybody had toggled.
extension type RuleSet(List<ComparisonRule> rules) {
  bool get isEmpty => rules.isEmpty;

  bool hides(ChannelDelta delta) => rules.any((rule) => rule.matches(delta));

  /// The deltas of [item] a reader has not excluded.
  List<ChannelDelta> visible(ComparedItem item) => [
    for (var delta in item.deltas)
      if (!hides(delta)) delta,
  ];

  /// Whether every one of [item]'s deltas is excluded.
  ///
  /// A finding with **no** deltas at all is never hidden: `added`, `removed`
  /// and `broke` say something no channel does, and a rule about channels has
  /// no opinion about them. Hiding those on a channel rule would be the filter
  /// deciding what the comparison found, which is the one thing it may not do.
  bool hidesAll(ComparedItem item) {
    var any = false;
    for (var delta in item.deltas) {
      any = true;
      if (!hides(delta)) return false;
    }
    return any;
  }

  /// Whether a rule on [facet] = [value] is in force.
  bool has(String facet, String value) => rules.any(
    (rule) =>
        rule.isSingle &&
        rule.constraints.single.facet == facet &&
        rule.constraints.single.value == value,
  );
}
