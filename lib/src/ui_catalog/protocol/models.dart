import 'package:built_value/built_value.dart';

export 'serializers.dart' show modelSerializers;

part 'models.g.dart';

abstract class ScreenConfiguration
    implements Built<ScreenConfiguration, ScreenConfigurationBuilder> {
  ScreenConfiguration._();
  factory ScreenConfiguration(
          [void Function(ScreenConfigurationBuilder) updates]) =
      _$ScreenConfiguration;
}
