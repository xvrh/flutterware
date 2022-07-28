import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'locale.g.dart';

abstract class SerializableLocale
    implements Built<SerializableLocale, SerializableLocaleBuilder> {
  static Serializer<SerializableLocale> get serializer =>
      _$serializableLocaleSerializer;

  SerializableLocale._();
  factory SerializableLocale._fromBuilder(
          [void Function(SerializableLocaleBuilder) updates]) =
      _$SerializableLocale;
  factory SerializableLocale(String language, [String? country]) =>
      SerializableLocale._fromBuilder((b) => b
        ..language = language
        ..country = country);

  String get language;
  String? get country;

  String get displayString {
    return [language, if (country != null) country!].join('_');
  }
}
