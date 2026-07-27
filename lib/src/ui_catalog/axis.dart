import 'knob.dart';

/// Every axis one shell offers, as of one build of it.
///
/// The axes themselves are [KnobDescriptor]s, which is deliberate rather than
/// lazy: that type says it is "the shape a panel renders *whatever* produced
/// it", and an enum axis is a picker with a closed set of labels — precisely
/// what a picker knob already is. A renderer switches on [KnobKind] and does
/// not need to know which side of the process declared it.
///
/// What differs is the envelope. A knob belongs to an entry and is declared by
/// building it; an axis belongs to a *shell* and is declared by its signature,
/// so the two are reported separately and only one of them resets when you
/// move between entries.
class AxisReport {
  const AxisReport({required this.shellId, required this.axes});

  factory AxisReport.fromJson(Map<String, Object?> json) => AxisReport(
    shellId: json['shell'] as String?,
    axes: [
      for (var axis in json['axes'] as List? ?? const [])
        KnobDescriptor.fromJson((axis as Map).cast<String, Object?>()),
    ],
  );

  static const empty = AxisReport(shellId: null, axes: []);

  /// Which shell declared these.
  ///
  /// A report naming another shell is a report from before the switch landed,
  /// not a shell without axes — the same distinction [KnobReport.entryId]
  /// draws, and for the same reason: the host has to know whether to show
  /// nothing or to ask again.
  final String? shellId;

  final List<KnobDescriptor> axes;

  Map<String, Object?> toJson() => {
    'shell': shellId,
    'axes': [for (var axis in axes) axis.toJson()],
  };
}
