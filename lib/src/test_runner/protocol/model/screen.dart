import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'rectangle.dart';
import 'run_args.dart';

part 'screen.g.dart';

abstract class NewScreen implements Built<NewScreen, NewScreenBuilder> {
  static Serializer<NewScreen> get serializer => _$newScreenSerializer;

  NewScreen._();
  factory NewScreen([void Function(NewScreenBuilder) updates]) = _$NewScreen;

  Screen get screen;
  String? get parent;
  Rectangle? get parentRectangle;
  AnalyticEvent? get analyticEvent;
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

  factory Screen(String id, String name,
          {bool? isCollapsable, bool? isCollapsed}) =>
      Screen._builder((b) => b
        ..id = id
        ..name = name
        ..isCollapsable = isCollapsable ?? false
        ..isCollapsed = false);

  String get id;
  BuiltList<TextInfo> get texts;
  BuiltList<ScreenLink> get next;
  String? get pathName;
  String get name;
  Uint8List? get imageBytes;
  ImageFile? get imageFile;
  String? get documentationKey;
  bool get isCollapsable;
  bool get isCollapsed;
  BuiltList<Screen> get collapsedScreens;
  BrowserInfo? get browser;
  EmailInfo? get email;
  PdfInfo? get pdf;
  JsonInfo? get json;
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
  AnalyticEvent? get analytic;
}

abstract class AnalyticEvent
    implements Built<AnalyticEvent, AnalyticEventBuilder> {
  static Serializer<AnalyticEvent> get serializer => _$analyticEventSerializer;

  AnalyticEvent._();
  factory AnalyticEvent._builder(
      [void Function(AnalyticEventBuilder) updates]) = _$AnalyticEvent;

  factory AnalyticEvent(String event, {Map<String, dynamic>? args}) =>
      AnalyticEvent._builder((b) {
        b.event = event;
        if (args != null) {
          b.args.replace(args);
        }
      });

  String get event;
  BuiltMap<String, String> get args;
}

abstract class BrowserInfo implements Built<BrowserInfo, BrowserInfoBuilder> {
  static Serializer<BrowserInfo> get serializer => _$browserInfoSerializer;

  BrowserInfo._();

  factory BrowserInfo._builder([void Function(BrowserInfoBuilder) updates]) =
      _$BrowserInfo;

  factory BrowserInfo(String url,
          {required bool useSafariVC, required bool useWebView}) =>
      BrowserInfo._builder((b) => b
        ..url = url
        ..useSafariVC = useSafariVC
        ..useWebView = useWebView);

  String get url;
  bool get useSafariVC;
  bool get useWebView;
}

abstract class EmailInfo implements Built<EmailInfo, EmailInfoBuilder> {
  static Serializer<EmailInfo> get serializer => _$emailInfoSerializer;

  EmailInfo._();
  factory EmailInfo._builder([void Function(EmailInfoBuilder) updates]) =
      _$EmailInfo;
  factory EmailInfo({
    required String subject,
    required String body,
    required String sender,
    required String recipient,
  }) =>
      EmailInfo._builder((b) => b
        ..subject = subject
        ..body = body
        ..sender = sender
        ..recipient = recipient);

  String get subject;
  String get body;
  String get sender;
  String get recipient;
}

abstract class PdfInfo implements Built<PdfInfo, PdfInfoBuilder> {
  static Serializer<PdfInfo> get serializer => _$pdfInfoSerializer;

  PdfInfo._();
  factory PdfInfo._builder([void Function(PdfInfoBuilder) updates]) = _$PdfInfo;

  factory PdfInfo({
    required Uint8List bytes,
    required String fileName,
  }) =>
      PdfInfo._builder((b) => b
        ..bytesBase64 = base64Encode(bytes)
        ..fileName = fileName);

  String get bytesBase64;
  String get fileName;
}

abstract class JsonInfo implements Built<JsonInfo, JsonInfoBuilder> {
  static Serializer<JsonInfo> get serializer => _$jsonInfoSerializer;

  JsonInfo._();
  factory JsonInfo._builder([void Function(JsonInfoBuilder) updates]) =
      _$JsonInfo;

  factory JsonInfo({
    required String data,
    required String fileName,
  }) =>
      JsonInfo._builder((b) => b
        ..data = data
        ..fileName = fileName);

  String get data;
  String get fileName;
}

abstract class DocumentationScreen
    implements Built<DocumentationScreen, DocumentationScreenBuilder> {
  DocumentationScreen._();
  factory DocumentationScreen._fromBuilder(
          [void Function(DocumentationScreenBuilder) updates]) =
      _$DocumentationScreen;

  factory DocumentationScreen(File? screenshot, Screen screen, RunArgs args) =>
      DocumentationScreen._fromBuilder((b) => b
        ..screenshot = screenshot
        ..screen.replace(screen)
        ..args.replace(args));

  File? get screenshot;
  Screen get screen;
  RunArgs get args;
}
