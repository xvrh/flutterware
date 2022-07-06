import 'dart:typed_data';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'rectangle.dart';

part 'screen.g.dart';

abstract class NewScreen implements Built<NewScreen, NewScreenBuilder> {
  static Serializer<NewScreen> get serializer => _$newScreenSerializer;

  NewScreen._();
  factory NewScreen([void Function(NewScreenBuilder) updates]) = _$NewScreen;

  Screen get screen;
  String? get parent;
  Rectangle? get parentRectangle;
  String? get imageBase64;
  ImageFile? get imageFile;
}

abstract class ImageFile implements Built<ImageFile, ImageFileBuilder> {
  static Serializer<ImageFile> get serializer => _$imageFileSerializer;

  ImageFile._();
  factory ImageFile._fromBuilder([void Function(ImageFileBuilder) updates]) =
      _$ImageFile;

  factory ImageFile(String path, int width, int height) =>
      ImageFile._fromBuilder((b) => b
        ..path = path
        ..width = width
        ..height = height);

  String get path;
  int get width;
  int get height;
}

abstract class Screen implements Built<Screen, ScreenBuilder> {
  static Serializer<Screen> get serializer => _$screenSerializer;

  Screen._();
  factory Screen._builder([void Function(ScreenBuilder) updates]) = _$Screen;

  factory Screen(String id, String name) => Screen._builder((b) => b
    ..id = id
    ..name = name);

  String get id;
  BuiltList<TextInfo> get texts;
  BuiltList<ScreenLink> get next;
  String? get splitName;
  String get name;
  Uint8List? get imageBytes;
  ImageFile? get imageFile;
  int? get topBrightness;
  int? get bottomBrightness;
  BuiltList<String>? get supportedLocales;
}

abstract class TextInfo implements Built<TextInfo, TextInfoBuilder> {
  static Serializer<TextInfo> get serializer => _$textInfoSerializer;

  TextInfo._();
  factory TextInfo._fromBuilder([void Function(TextInfoBuilder) updates]) =
      _$TextInfo;
  factory TextInfo({
    required String translationKey,
    required String rawTranslation,
    required String text,
    required Rectangle globalRectangle,
  }) =>
      TextInfo._fromBuilder((b) => b
        ..translationKey = translationKey
        ..rawTranslation = rawTranslation
        ..text = text
        ..globalRectangle.replace(globalRectangle));

  String get translationKey;
  String get rawTranslation;
  String get text;
  Rectangle get globalRectangle;
  String? get fontFamily;
  double? get fontSize;
  int? get color;
  int? get fontWeight;
}

abstract class ScreenLink implements Built<ScreenLink, ScreenLinkBuilder> {
  static Serializer<ScreenLink> get serializer => _$screenLinkSerializer;

  ScreenLink._();
  factory ScreenLink._builder([void Function(ScreenLinkBuilder) updates]) =
      _$ScreenLink;

  factory ScreenLink(String to) => ScreenLink._builder((b) => b..to = to);

  String get to;
  Rectangle? get tapRect;
}
