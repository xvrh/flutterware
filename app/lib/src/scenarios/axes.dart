import '../catalog/devices.dart';

/// One run's axis assignment, exactly as the address carries it:
/// `?device=iphone-se&language=fr&text-scale=1.3&brightness=dark`.
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
  });

  /// A [CatalogDevice] id, or null for the tester's default surface.
  final String? device;

  /// A locale tag — `fr`, `fr-CA`.
  final String? language;

  final double? textScale;

  /// `light` or `dark`.
  final String? brightness;

  bool get isEmpty =>
      device == null &&
      language == null &&
      textScale == null &&
      brightness == null;

  /// The address parameters this assignment writes — and what gets recorded
  /// on every artifact, per the rule that a screenshot is under-specified
  /// without its axes.
  Map<String, String> toParams() => {
    'device': ?device,
    'language': ?language,
    if (textScale case var scale?) 'text-scale': _compact(scale),
    'brightness': ?brightness,
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
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(device, language, textScale, brightness);

  @override
  String toString() => 'ScenarioAxes(${toParams()})';
}
