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

  factory AccessibilityConfig({double? textScale, bool? boldText}) =>
      AccessibilityConfig._fromBuilder((b) => b
        ..textScale = textScale ?? 1.0
        ..boldText = boldText ?? false);

  double get textScale;
  bool get boldText;
}
