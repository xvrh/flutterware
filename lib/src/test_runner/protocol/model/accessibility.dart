import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'accessibility.g.dart';

abstract class AccessibilityConfig
    implements Built<AccessibilityConfig, AccessibilityConfigBuilder> {
  static Serializer<AccessibilityConfig> get serializer =>
      _$accessibilityConfigSerializer;

  static final defaultValue = AccessibilityConfig();

  AccessibilityConfig._();
  factory AccessibilityConfig._fromBuilder(
          [void Function(AccessibilityConfigBuilder) updates]) =
      _$AccessibilityConfig;

  factory AccessibilityConfig(
          {double? textScale,
          bool? boldText,
          bool? accessibleNavigation,
          bool? disableAnimations,
          bool? highContrast,
          bool? invertColors,
          bool? reduceMotion,
          bool? onOffSwitchLabels}) =>
      AccessibilityConfig._fromBuilder((b) => b
        ..textScale = textScale ?? 1.0
        ..boldText = boldText ?? false
        ..accessibleNavigation = accessibleNavigation ?? false
        ..disableAnimations = disableAnimations ?? false
        ..highContrast = highContrast ?? false
        ..invertColors = invertColors ?? false
        ..reduceMotion = reduceMotion ?? false
        ..onOffSwitchLabels = onOffSwitchLabels ?? false);

  double get textScale;
  bool get boldText;
  bool get accessibleNavigation;
  bool get disableAnimations;
  bool get highContrast;
  bool get invertColors;
  bool get reduceMotion;
  bool get onOffSwitchLabels;
}
