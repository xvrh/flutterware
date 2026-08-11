/// One control a catalog entry offers, and the value it currently has.
///
/// Deliberately plain Dart with no Flutter in it, and deliberately in the
/// published package rather than in the app: this is the shape a panel renders
/// *whatever produced it*. Today that is the guest, which learns the knobs by
/// running the demo and reports them over the VM service. A declaration read
/// straight off a demo's parameter list would produce the same descriptors
/// without running anything — see
/// `docs/superpowers/specs/2026-07-27-knobs-static-and-runtime.md`. The panel
/// should not be able to tell the difference.
library;

/// What kind of control a knob is, which is what a panel switches on.
///
/// Kinds a producer cannot describe are left out of a report rather than
/// guessed at: a knob rendered as the wrong control is worse than a knob the
/// panel admits it cannot show.
enum KnobKind {
  string,
  boolean,
  integer,
  number,

  /// A choice between named options. Only the labels cross the wire — the
  /// values behind them are whatever the demo said they are, and only the demo
  /// can turn a label back into one.
  picker;

  static KnobKind? byName(String name) {
    for (var kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

class KnobDescriptor {
  const KnobDescriptor({
    required this.name,
    required this.kind,
    required this.value,
    required this.defaultValue,
    this.min,
    this.max,
    this.step,
    this.description,
    this.options = const [],
  });

  factory KnobDescriptor.fromJson(Map<String, Object?> json) => KnobDescriptor(
    name: json['name']! as String,
    kind: KnobKind.byName(json['kind'] as String? ?? '') ?? KnobKind.string,
    value: json['value'],
    defaultValue: json['default'],
    min: json['min'] as num?,
    max: json['max'] as num?,
    step: json['step'] as num?,
    description: json['description'] as String?,
    options: [
      for (var option in json['options'] as List? ?? const []) option as String,
    ],
  );

  /// Unique within an entry, and how a value is addressed.
  final String name;

  final KnobKind kind;

  /// What the entry is currently being rendered with.
  final Object? value;

  /// What it renders with when nothing has been set — the value written in the
  /// demo, which is also what it shows outside the catalog.
  final Object? defaultValue;

  /// Bounds for [KnobKind.integer] and [KnobKind.number], when the demo gave
  /// any. A knob with both is a slider; a knob with neither is a field.
  final num? min;
  final num? max;

  /// The granularity a slider moves in, when the producer declared one. Absent
  /// means continuous — a devbar variable declares this, a catalog demo does
  /// not.
  final num? step;

  /// What this knob is for, when the producer said. Shown beside the control.
  final String? description;

  /// The labels of a [KnobKind.picker], in the order the demo declared them.
  final List<String> options;

  bool get isDefault => value == defaultValue;

  /// The same knob showing [value], for a panel that wants to draw the value a
  /// user is choosing before the guest has confirmed it.
  KnobDescriptor withValue(Object? value) => KnobDescriptor(
    name: name,
    kind: kind,
    value: value,
    defaultValue: defaultValue,
    min: min,
    max: max,
    step: step,
    description: description,
    options: options,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    'value': value,
    'default': defaultValue,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (step != null) 'step': step,
    if (description != null) 'description': description,
    if (options.isNotEmpty) 'options': options,
  };
}

/// Every knob one entry offers, as of one build of it.
class KnobReport {
  const KnobReport({
    required this.entryId,
    required this.knobs,
    this.declared = 0,
    this.revision = 0,
  });

  factory KnobReport.fromJson(Map<String, Object?> json) => KnobReport(
    entryId: json['entry'] as String?,
    declared: json['declared'] as int? ?? 0,
    revision: json['revision'] as int? ?? 0,
    knobs: [
      for (var knob in json['parameters'] as List? ?? const [])
        KnobDescriptor.fromJson((knob as Map).cast<String, Object?>()),
    ],
  );

  static const empty = KnobReport(entryId: null, knobs: []);

  /// Which entry declared these. A report for another entry is a report from
  /// before the switch landed, not an empty catalog — the difference matters
  /// to a panel deciding whether to show nothing or to ask again.
  final String? entryId;

  final List<KnobDescriptor> knobs;

  /// How many times knobs have been declared, which changes when a demo's
  /// build takes a different path and offers a different set.
  final int declared;

  /// How many times a value has changed.
  final int revision;

  Map<String, Object?> toJson() => {
    'entry': entryId,
    'declared': declared,
    'revision': revision,
    'parameters': [for (var knob in knobs) knob.toJson()],
  };
}
