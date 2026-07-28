import 'knob.dart';

/// Every axis one shell offers, as of one build of it.
///
/// The axes themselves are [KnobDescriptor]s, which is deliberate rather than
/// lazy: that type says it is "the shape a panel renders *whatever* produced
/// it", and a picker over named options is precisely what a picker knob
/// already is. A renderer switches on [KnobKind] and does not need to know
/// which side of the process declared it.
///
/// What differs is the envelope. A knob belongs to an entry and resets with
/// it; an axis belongs to a *shell* and outlives the entry on screen, so the
/// two are reported separately.
class AxisReport {
  const AxisReport({
    required this.entryId,
    required this.shellId,
    required this.axes,
  });

  factory AxisReport.fromJson(Map<String, Object?> json) => AxisReport(
    entryId: json['entry'] as String?,
    shellId: json['shell'] as String?,
    axes: [
      for (var axis in json['axes'] as List? ?? const [])
        KnobDescriptor.fromJson((axis as Map).cast<String, Object?>()),
    ],
  );

  static const empty = AxisReport(entryId: null, shellId: null, axes: []);

  /// Which entry was on screen when these were declared.
  ///
  /// The host retries a read until this names the entry it switched to, the
  /// same distinction [KnobReport.entryId] draws and for the same reason: an
  /// axis is recorded by the *build* of the shell, so a read landing between
  /// the reload and the frame describes the shell that was there before.
  final String? entryId;

  /// Which shell declared these, or null for an entry whose wrapper is not a
  /// shell — which has no axes.
  ///
  /// The name a shell gives itself, not a path: it is what the host files
  /// selections under, so it survives the file being moved or renamed.
  final String? shellId;

  final List<KnobDescriptor> axes;

  Map<String, Object?> toJson() => {
    'entry': entryId,
    'shell': shellId,
    'axes': [for (var axis in axes) axis.toJson()],
  };
}
