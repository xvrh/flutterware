import '../catalog/devices.dart';

/// What `?device=` means when nothing was chosen: scenarios frame as a phone
/// by default — the "default form factor". An explicit [fitDeviceId] is how
/// you ask for the bare test surface instead.
const defaultScenarioDeviceId = 'iphone-13';

/// The scenarios reading of a raw `?device=` parameter.
///
/// Absent defaults to [defaultScenarioDeviceId]; [fitDeviceId] resolves to no
/// device at all (the bare 800×600 test surface); anything else is itself.
/// Both the panel and the `run` action read through this, so the two cannot
/// disagree about what an unspecified device means.
String? resolveScenarioDevice(String? param) => switch (param) {
  null => defaultScenarioDeviceId,
  fitDeviceId => null,
  var id => id,
};

/// One run's axis assignment, exactly as the address carries it:
/// `?device=iphone-se&language=fr&text-scale=1.3&brightness=dark&bold-text=true`.
///
/// Plain Dart, plain strings — this is the vocabulary a person types into an
/// address bar and an agent passes to the `run` action, kept unresolved so a
/// recorded assignment reads back as what was asked. The one resolution —
/// device id to numbers — happens in [harnessArgs], against the same
/// [catalogDevices] table the catalog frames with, so `iphone-se` means the
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

  /// A [CatalogDevice] id, or null for the tester's default surface. Already
  /// resolved — see [resolveScenarioDevice] for what an absent `?device=`
  /// means.
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

  ScenarioAxes copyWith({String? device}) => ScenarioAxes(
    device: device ?? this.device,
    language: language,
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
  Map<String, String> harnessArgs() {
    var resolved = device == null ? null : deviceById(device!);
    return {
      if (resolved != null) ...{
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
