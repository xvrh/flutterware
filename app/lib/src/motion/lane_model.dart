/// The guest's answer, parsed once.
///
/// `ext.flutterware.motion.list` returns JSON and the panel used to read it
/// where it drew it — `(target['properties'] as List).cast<Map<String,
/// dynamic>>()` at three depths, repeated per widget. That survived a read-only
/// lane list. It does not survive an inspector, which needs to find one segment
/// by name and show four of its fields, nor a selection that has to outlive the
/// poll that replaces the object it points at.
///
/// Nothing here decides anything. The states are the runtime's, parroted;
/// the only computed values are the ones a lane cannot draw without —
/// a target's aggregate span, and which offers are still addable.
library;

import 'dart:math' as math;
import 'dart:ui' show Color, Rect;

import 'package:collection/collection.dart';

/// What a lane means, decided by the guest and repeated here.
///
/// Computed by `_stateOf` in `lib/src/motion/guest.dart`, because `offered`
/// counts as wiring for a tuned property and does not create a lane for an
/// untuned one — and re-deriving that per consumer got it wrong once, on the
/// first live run.
enum MotionLaneState {
  /// Tuned, and something applies it.
  wired,

  /// Tuned, and nothing reads or offers it. Prunable.
  dead,

  /// Applied but never tuned. This is the creation path.
  untuned;

  static MotionLaneState parse(Object? raw) => switch (raw) {
    'dead' => dead,
    'untuned' => untuned,
    _ => wired,
  };
}

/// A value as the guest encodes it: a number as itself, a colour as ARGB under
/// a key that says so. Two kinds is the whole value model.
sealed class MotionValueView {
  const MotionValueView();

  static MotionValueView? parse(Object? raw) => switch (raw) {
    num value => MotionNumberView(value.toDouble()),
    {'color': int argb} => MotionColorView(argb),
    _ => null,
  };

  /// What the panel prints for it.
  String get label;
}

class MotionNumberView extends MotionValueView {
  const MotionNumberView(this.value);

  final double value;

  @override
  String get label => value.toStringAsFixed(2);

  @override
  bool operator ==(Object other) =>
      other is MotionNumberView && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class MotionColorView extends MotionValueView {
  const MotionColorView(this.argb);

  final int argb;

  Color get color => Color(argb);

  @override
  String get label =>
      '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  @override
  bool operator ==(Object other) =>
      other is MotionColorView && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;
}

class MotionSegmentView {
  const MotionSegmentView({
    required this.startMs,
    required this.endMs,
    this.from,
    this.to,
    this.curve,
  });

  final int startMs;
  final int endMs;
  final MotionValueView? from;
  final MotionValueView? to;

  /// A `Curves.<name>`, or null where the file wrote none. Only a name the
  /// runtime could put back survives the round trip.
  final String? curve;

  int get durationMs => endMs - startMs;

  static MotionSegmentView parse(Map<String, dynamic> raw) => MotionSegmentView(
    startMs: (raw['startMs'] as num?)?.toInt() ?? 0,
    endMs: (raw['endMs'] as num?)?.toInt() ?? 0,
    from: MotionValueView.parse(raw['from']),
    to: MotionValueView.parse(raw['to']),
    curve: raw['curve'] as String?,
  );
}

class MotionPropertyView {
  const MotionPropertyView({
    required this.name,
    required this.state,
    this.value,
    this.segments = const [],
  });

  final String name;
  final MotionLaneState state;

  /// What it is worth at the playhead, which is not derivable from [segments]
  /// here: the guest evaluated it, curves and all.
  final MotionValueView? value;

  final List<MotionSegmentView> segments;

  static MotionPropertyView parse(Map<String, dynamic> raw) =>
      MotionPropertyView(
        name: '${raw['name']}',
        state: MotionLaneState.parse(raw['state']),
        value: MotionValueView.parse(raw['value']),
        segments: [
          for (var segment in (raw['segments'] as List? ?? const []))
            MotionSegmentView.parse((segment as Map).cast<String, dynamic>()),
        ],
      );
}

class MotionTargetView {
  const MotionTargetView({
    required this.name,
    required this.named,
    this.extent,
    this.offered = const [],
    this.properties = const [],
  });

  final String name;

  /// Where this target is on the guest's screen, or null when nothing has
  /// pointed at it.
  ///
  /// Null is the ordinary case, not an error: a target is not a widget, so only
  /// the ones wrapped in a `MotionExtent` — or in a `MotionBox`, which wraps one
  /// itself — have anywhere to be.
  final Rect? extent;

  /// Whether the last build asked for it. False means the tuning is there and
  /// nothing points at it any more.
  final bool named;

  final List<String> offered;
  final List<MotionPropertyView> properties;

  /// The properties a `MotionBox` offers that no lane covers yet.
  ///
  /// The box sweeps its whole frozen set every build, so an element that only
  /// fades reports eight offered properties and one lane. The other seven are
  /// what "add a property" can mean here.
  List<String> get addable => [
    for (var offer in offered)
      if (properties.none((property) => property.name == offer)) offer,
  ];

  /// Where this target's tuning starts and ends, or null when nothing is tuned.
  /// The aggregate bar on the group row is exactly this.
  (int, int)? get span {
    var segments = [for (var property in properties) ...property.segments];
    if (segments.isEmpty) return null;
    return (
      segments.map((s) => s.startMs).reduce(math.min),
      segments.map((s) => s.endMs).reduce(math.max),
    );
  }

  /// A target is worth what its best property is worth — except that never
  /// having been named outranks everything, since nothing below it can be
  /// applied by a build that did not happen.
  MotionLaneState get state {
    if (!named) return MotionLaneState.dead;
    if (properties.any((p) => p.state == MotionLaneState.wired)) {
      return MotionLaneState.wired;
    }
    if (properties.any((p) => p.state == MotionLaneState.dead)) {
      return MotionLaneState.dead;
    }
    return MotionLaneState.untuned;
  }

  static MotionTargetView parse(Map<String, dynamic> raw) => MotionTargetView(
    name: '${raw['name']}',
    named: raw['named'] == true,
    extent: switch (raw['extent']) {
      {'x': num x, 'y': num y, 'width': num width, 'height': num height} =>
        Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          width.toDouble(),
          height.toDouble(),
        ),
      _ => null,
    },
    offered: (raw['offered'] as List? ?? const []).cast<String>(),
    properties: [
      for (var property in (raw['properties'] as List? ?? const []))
        MotionPropertyView.parse((property as Map).cast<String, dynamic>()),
    ],
  );
}

/// Which body a scope is building — the guest's `MotionHost`, parroted.
///
/// A second declaration rather than an import of the runtime's, for the reason
/// the whole file exists: this model is what the panel draws from, and it must
/// parse an answer from a guest whose `flutterware` is not necessarily this
/// one. An unknown name reads as [real], which is what a guest too old to have
/// a stage is.
enum MotionHostView {
  real,
  draft;

  static MotionHostView parse(Object? raw) => raw == 'draft' ? draft : real;

  String get label => switch (this) {
    real => 'Real',
    draft => 'Draft',
  };

  /// What the extension wants back.
  String get wire => name;
}

class MotionScopeView {
  const MotionScopeView({
    required this.id,
    required this.durationMs,
    required this.positionMs,
    required this.progress,
    required this.playing,
    this.host = MotionHostView.real,
    this.hosts = const [],
    this.targets = const [],
  });

  final String id;
  final int durationMs;
  final int positionMs;
  final double progress;
  final bool playing;

  /// Which body the scope is building, and which it could build.
  ///
  /// A scope with one host is the ordinary case and the panel draws no switch
  /// for it — a control whose every use is a refusal is worse than none.
  final MotionHostView host;
  final List<MotionHostView> hosts;

  final List<MotionTargetView> targets;

  static MotionScopeView? parse(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    return MotionScopeView(
      id: '${raw['id']}',
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
      positionMs: (raw['ms'] as num?)?.toInt() ?? 0,
      progress: (raw['progress'] as num?)?.toDouble() ?? 0,
      playing: raw['playing'] == true,
      host: MotionHostView.parse(raw['host']),
      hosts: [
        for (var host in (raw['hosts'] as List? ?? const []))
          MotionHostView.parse(host),
      ],
      targets: [
        for (var target in (raw['targets'] as List? ?? const []))
          MotionTargetView.parse((target as Map).cast<String, dynamic>()),
      ],
    );
  }

  MotionTargetView? target(String name) =>
      targets.firstWhereOrNull((target) => target.name == name);

  MotionPropertyView? property(String target, String property) => this
      .target(target)
      ?.properties
      .firstWhereOrNull((candidate) => candidate.name == property);

  /// The segment a selection points at, or null once a refresh has taken it
  /// away — a lane deleted, a property pruned, a whole target renamed.
  MotionSegmentView? resolve(MotionSelection selection) => property(
    selection.target,
    selection.property,
  )?.segments.elementAtOrNull(selection.index);
}

/// Which segment the inspector is showing.
///
/// Three coordinates rather than a reference: the model is rebuilt from the
/// guest on every poll, so holding the object would pin a stale one. An address
/// is what survives a refresh, and [MotionScopeView.resolve] says when it no
/// longer resolves rather than showing the old values.
class MotionSelection {
  const MotionSelection(this.target, this.property, this.index);

  final String target;
  final String property;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is MotionSelection &&
      other.target == target &&
      other.property == property &&
      other.index == index;

  @override
  int get hashCode => Object.hash(target, property, index);

  @override
  String toString() => 'MotionSelection($target.$property#$index)';
}
