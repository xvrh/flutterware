import '../catalog/devices.dart';

/// The form factor a scenario runs as when nothing at all chose one: no
/// `?device=`, and no profile on its folder either. A phone, because that is
/// the default form factor — an explicit [fitDeviceId] is how you ask for the
/// bare test surface instead.
///
/// **The last word, not the first.** A folder's `flutter_test_config.dart` is
/// asked before this, in the harness, where the profile is known — which is
/// why an unspecified device travels as null all the way down rather than
/// being resolved here.
const defaultScenarioDeviceId = 'iphone-13';

/// What names one point of a matrix on disk — `iphone-16-fr`, or `default`
/// where the point named nothing.
///
/// Deliberately the same rule as the standalone capture path's
/// `ScenarioAssignment.slug`: the two lanes write the same directory names for
/// the same assignment, so a project that starts with `flutter test` and moves
/// to `fw run` does not have to relearn its own output tree.
String axisSlug(ScenarioAxes axes) {
  var parts = [?axes.device, ?axes.language];
  return parts.isEmpty ? 'default' : parts.join('-');
}

/// One run's axis assignment, exactly as the address carries it:
/// `?device=iphone-se&language=fr&text-scale=1.3&brightness=dark&bold-text=true`.
///
/// Plain Dart, plain strings — this is the vocabulary a person types into an
/// address bar and an agent passes to the `run` action, kept unresolved so a
/// recorded assignment reads back as what was asked. The one resolution —
/// device id to numbers — happens in [harnessArgs], against the same
/// [Devices.all] table the catalog frames with, so `iphone-se` means the
/// same screen in both plugins.
class ScenarioAxes {
  const ScenarioAxes({
    this.device,
    this.language,
    this.textScale,
    this.brightness,
    this.boldText = false,
    this.highContrast = false,
    this.invertColors = false,
  });

  /// A [Device] id, [fitDeviceId] for the bare test surface, or **null for
  /// unspecified** — the three states `?device=` has, kept apart because only
  /// the harness can tell the last one what it means: the scenario's folder
  /// profile answers first, [defaultScenarioDeviceId] only if it has nothing
  /// to say.
  final String? device;

  /// A locale tag — `fr`, `fr-CA`.
  final String? language;

  final double? textScale;

  /// `light` or `dark`.
  final String? brightness;

  // The accessibility features, off by default like on a real phone.
  final bool boldText;
  final bool highContrast;
  final bool invertColors;

  bool get isEmpty =>
      device == null &&
      language == null &&
      textScale == null &&
      brightness == null &&
      !boldText &&
      !highContrast &&
      !invertColors;

  /// Whether any accessibility setting departs from the default — what the
  /// toolbar's accessibility chip lights up on.
  bool get anyAccessibility =>
      textScale != null || boldText || highContrast || invertColors;

  ScenarioAxes copyWith({String? device, String? language}) => ScenarioAxes(
    device: device ?? this.device,
    language: language ?? this.language,
    textScale: textScale,
    brightness: brightness,
    boldText: boldText,
    highContrast: highContrast,
    invertColors: invertColors,
  );

  /// The address parameters this assignment writes — and what gets recorded
  /// on every artifact, per the rule that a screenshot is under-specified
  /// without its axes.
  Map<String, String> toParams() => {
    'device': ?device,
    'language': ?language,
    if (textScale case var scale?) 'text-scale': _compact(scale),
    'brightness': ?brightness,
    if (boldText) 'bold-text': 'true',
    if (highContrast) 'high-contrast': 'true',
    if (invertColors) 'invert-colors': 'true',
  };

  /// The flat string args the harness's `run` extension takes. Geometry is
  /// resolved here: the harness applies numbers and never learns device
  /// names.
  ///
  /// An unspecified [device] travels as such — `deviceUnspecified`, plus
  /// [unspecifiedDevice]'s geometry as the fallback — because the folder
  /// profile that gets first refusal is only legible inside the harness. A
  /// caller with no policy of its own (the runner's own tests) passes nothing
  /// and gets the bare test surface, which is what a bare `flutter test`
  /// produces.
  Map<String, String> harnessArgs({String? unspecifiedDevice}) {
    var effective = device ?? unspecifiedDevice;
    var resolved = effective == null ? null : deviceById(effective);
    return {
      if (device == null) 'deviceUnspecified': 'true',
      if (resolved != null) ...{
        'device': resolved.id,
        'width': _compact(resolved.width),
        'height': _compact(resolved.height),
        'pixelRatio': _compact(resolved.pixelRatio),
        'insetTop': _compact(resolved.insetTop),
        'insetRight': _compact(resolved.insetRight),
        'insetBottom': _compact(resolved.insetBottom),
        'insetLeft': _compact(resolved.insetLeft),
        'platform': resolved.platform.name,
      },
      'language': ?language,
      if (textScale case var scale?) 'textScale': '$scale',
      'brightness': ?brightness,
      if (boldText) 'boldText': 'true',
      if (highContrast) 'highContrast': 'true',
      if (invertColors) 'invertColors': 'true',
    };
  }

  /// `2` rather than `2.0` — these strings end up in addresses.
  static String _compact(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  bool operator ==(Object other) =>
      other is ScenarioAxes &&
      other.device == device &&
      other.language == language &&
      other.textScale == textScale &&
      other.brightness == brightness &&
      other.boldText == boldText &&
      other.highContrast == highContrast &&
      other.invertColors == invertColors;

  @override
  int get hashCode => Object.hash(
    device,
    language,
    textScale,
    brightness,
    boldText,
    highContrast,
    invertColors,
  );

  @override
  String toString() => 'ScenarioAxes(${toParams()})';
}
