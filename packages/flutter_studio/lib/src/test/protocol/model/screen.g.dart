// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'screen.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<NewScreen> _$newScreenSerializer = _$NewScreenSerializer();
Serializer<Screen> _$screenSerializer = _$ScreenSerializer();
Serializer<TextInfo> _$textInfoSerializer = _$TextInfoSerializer();
Serializer<ScreenLink> _$screenLinkSerializer = _$ScreenLinkSerializer();
Serializer<AnalyticEvent> _$analyticEventSerializer =
    _$AnalyticEventSerializer();
Serializer<BrowserInfo> _$browserInfoSerializer = _$BrowserInfoSerializer();
Serializer<EmailInfo> _$emailInfoSerializer = _$EmailInfoSerializer();
Serializer<PdfInfo> _$pdfInfoSerializer = _$PdfInfoSerializer();
Serializer<JsonInfo> _$jsonInfoSerializer = _$JsonInfoSerializer();

class _$NewScreenSerializer implements StructuredSerializer<NewScreen> {
  @override
  final Iterable<Type> types = const [NewScreen, _$NewScreen];
  @override
  final String wireName = 'NewScreen';

  @override
  Iterable<Object?> serialize(Serializers serializers, NewScreen object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'screen',
      serializers.serialize(object.screen,
          specifiedType: const FullType(Screen)),
    ];
    Object? value;
    value = object.parent;
    if (value != null) {
      result
        ..add('parent')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.parentRectangle;
    if (value != null) {
      result
        ..add('parentRectangle')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(Rectangle)));
    }
    value = object.analyticEvent;
    if (value != null) {
      result
        ..add('analyticEvent')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(AnalyticEvent)));
    }
    value = object.imageBase64;
    if (value != null) {
      result
        ..add('imageBase64')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  NewScreen deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = NewScreenBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'screen':
          result.screen.replace(serializers.deserialize(value,
              specifiedType: const FullType(Screen))! as Screen);
          break;
        case 'parent':
          result.parent = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'parentRectangle':
          result.parentRectangle.replace(serializers.deserialize(value,
              specifiedType: const FullType(Rectangle))! as Rectangle);
          break;
        case 'analyticEvent':
          result.analyticEvent.replace(serializers.deserialize(value,
              specifiedType: const FullType(AnalyticEvent))! as AnalyticEvent);
          break;
        case 'imageBase64':
          result.imageBase64 = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
      }
    }

    return result.build();
  }
}

class _$ScreenSerializer implements StructuredSerializer<Screen> {
  @override
  final Iterable<Type> types = const [Screen, _$Screen];
  @override
  final String wireName = 'Screen';

  @override
  Iterable<Object?> serialize(Serializers serializers, Screen object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(String)),
      'texts',
      serializers.serialize(object.texts,
          specifiedType: const FullType(BuiltList, [FullType(TextInfo)])),
      'next',
      serializers.serialize(object.next,
          specifiedType: const FullType(BuiltList, [FullType(ScreenLink)])),
      'name',
      serializers.serialize(object.name, specifiedType: const FullType(String)),
      'isCollapsable',
      serializers.serialize(object.isCollapsable,
          specifiedType: const FullType(bool)),
      'isCollapsed',
      serializers.serialize(object.isCollapsed,
          specifiedType: const FullType(bool)),
      'collapsedScreens',
      serializers.serialize(object.collapsedScreens,
          specifiedType: const FullType(BuiltList, [FullType(Screen)])),
    ];
    Object? value;
    value = object.pathName;
    if (value != null) {
      result
        ..add('pathName')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.imageBytes;
    if (value != null) {
      result
        ..add('imageBytes')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(Uint8List)));
    }
    value = object.documentationKey;
    if (value != null) {
      result
        ..add('documentationKey')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.browser;
    if (value != null) {
      result
        ..add('browser')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(BrowserInfo)));
    }
    value = object.email;
    if (value != null) {
      result
        ..add('email')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(EmailInfo)));
    }
    value = object.pdf;
    if (value != null) {
      result
        ..add('pdf')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(PdfInfo)));
    }
    value = object.json;
    if (value != null) {
      result
        ..add('json')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(JsonInfo)));
    }
    return result;
  }

  @override
  Screen deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = ScreenBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'id':
          result.id = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'texts':
          result.texts.replace(serializers.deserialize(value,
                  specifiedType:
                      const FullType(BuiltList, [FullType(TextInfo)]))!
              as BuiltList<Object?>);
          break;
        case 'next':
          result.next.replace(serializers.deserialize(value,
                  specifiedType:
                      const FullType(BuiltList, [FullType(ScreenLink)]))!
              as BuiltList<Object?>);
          break;
        case 'pathName':
          result.pathName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'name':
          result.name = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'imageBytes':
          result.imageBytes = serializers.deserialize(value,
              specifiedType: const FullType(Uint8List)) as Uint8List?;
          break;
        case 'documentationKey':
          result.documentationKey = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'isCollapsable':
          result.isCollapsable = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'isCollapsed':
          result.isCollapsed = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'collapsedScreens':
          result.collapsedScreens.replace(serializers.deserialize(value,
                  specifiedType: const FullType(BuiltList, [FullType(Screen)]))!
              as BuiltList<Object?>);
          break;
        case 'browser':
          result.browser.replace(serializers.deserialize(value,
              specifiedType: const FullType(BrowserInfo))! as BrowserInfo);
          break;
        case 'email':
          result.email.replace(serializers.deserialize(value,
              specifiedType: const FullType(EmailInfo))! as EmailInfo);
          break;
        case 'pdf':
          result.pdf.replace(serializers.deserialize(value,
              specifiedType: const FullType(PdfInfo))! as PdfInfo);
          break;
        case 'json':
          result.json.replace(serializers.deserialize(value,
              specifiedType: const FullType(JsonInfo))! as JsonInfo);
          break;
      }
    }

    return result.build();
  }
}

class _$TextInfoSerializer implements StructuredSerializer<TextInfo> {
  @override
  final Iterable<Type> types = const [TextInfo, _$TextInfo];
  @override
  final String wireName = 'TextInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, TextInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'translationKey',
      serializers.serialize(object.translationKey,
          specifiedType: const FullType(String)),
      'rawTranslation',
      serializers.serialize(object.rawTranslation,
          specifiedType: const FullType(String)),
      'text',
      serializers.serialize(object.text, specifiedType: const FullType(String)),
      'globalRectangle',
      serializers.serialize(object.globalRectangle,
          specifiedType: const FullType(Rectangle)),
    ];
    Object? value;
    value = object.fontFamily;
    if (value != null) {
      result
        ..add('fontFamily')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.fontSize;
    if (value != null) {
      result
        ..add('fontSize')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(double)));
    }
    value = object.color;
    if (value != null) {
      result
        ..add('color')
        ..add(serializers.serialize(value, specifiedType: const FullType(int)));
    }
    value = object.fontWeight;
    if (value != null) {
      result
        ..add('fontWeight')
        ..add(serializers.serialize(value, specifiedType: const FullType(int)));
    }
    return result;
  }

  @override
  TextInfo deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = TextInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'translationKey':
          result.translationKey = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'rawTranslation':
          result.rawTranslation = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'text':
          result.text = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'globalRectangle':
          result.globalRectangle.replace(serializers.deserialize(value,
              specifiedType: const FullType(Rectangle))! as Rectangle);
          break;
        case 'fontFamily':
          result.fontFamily = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'fontSize':
          result.fontSize = serializers.deserialize(value,
              specifiedType: const FullType(double)) as double?;
          break;
        case 'color':
          result.color = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int?;
          break;
        case 'fontWeight':
          result.fontWeight = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int?;
          break;
      }
    }

    return result.build();
  }
}

class _$ScreenLinkSerializer implements StructuredSerializer<ScreenLink> {
  @override
  final Iterable<Type> types = const [ScreenLink, _$ScreenLink];
  @override
  final String wireName = 'ScreenLink';

  @override
  Iterable<Object?> serialize(Serializers serializers, ScreenLink object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'to',
      serializers.serialize(object.to, specifiedType: const FullType(String)),
    ];
    Object? value;
    value = object.tapRect;
    if (value != null) {
      result
        ..add('tapRect')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(Rectangle)));
    }
    value = object.analytic;
    if (value != null) {
      result
        ..add('analytic')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(AnalyticEvent)));
    }
    return result;
  }

  @override
  ScreenLink deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = ScreenLinkBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'to':
          result.to = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'tapRect':
          result.tapRect.replace(serializers.deserialize(value,
              specifiedType: const FullType(Rectangle))! as Rectangle);
          break;
        case 'analytic':
          result.analytic.replace(serializers.deserialize(value,
              specifiedType: const FullType(AnalyticEvent))! as AnalyticEvent);
          break;
      }
    }

    return result.build();
  }
}

class _$AnalyticEventSerializer implements StructuredSerializer<AnalyticEvent> {
  @override
  final Iterable<Type> types = const [AnalyticEvent, _$AnalyticEvent];
  @override
  final String wireName = 'AnalyticEvent';

  @override
  Iterable<Object?> serialize(Serializers serializers, AnalyticEvent object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'event',
      serializers.serialize(object.event,
          specifiedType: const FullType(String)),
      'args',
      serializers.serialize(object.args,
          specifiedType:
              const FullType(BuiltMap, [FullType(String), FullType(String)])),
    ];

    return result;
  }

  @override
  AnalyticEvent deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = AnalyticEventBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'event':
          result.event = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'args':
          result.args.replace(serializers.deserialize(value,
              specifiedType: const FullType(
                  BuiltMap, [FullType(String), FullType(String)]))!);
          break;
      }
    }

    return result.build();
  }
}

class _$BrowserInfoSerializer implements StructuredSerializer<BrowserInfo> {
  @override
  final Iterable<Type> types = const [BrowserInfo, _$BrowserInfo];
  @override
  final String wireName = 'BrowserInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, BrowserInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'url',
      serializers.serialize(object.url, specifiedType: const FullType(String)),
      'useSafariVC',
      serializers.serialize(object.useSafariVC,
          specifiedType: const FullType(bool)),
      'useWebView',
      serializers.serialize(object.useWebView,
          specifiedType: const FullType(bool)),
    ];

    return result;
  }

  @override
  BrowserInfo deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = BrowserInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'url':
          result.url = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'useSafariVC':
          result.useSafariVC = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'useWebView':
          result.useWebView = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$EmailInfoSerializer implements StructuredSerializer<EmailInfo> {
  @override
  final Iterable<Type> types = const [EmailInfo, _$EmailInfo];
  @override
  final String wireName = 'EmailInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, EmailInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'subject',
      serializers.serialize(object.subject,
          specifiedType: const FullType(String)),
      'body',
      serializers.serialize(object.body, specifiedType: const FullType(String)),
      'sender',
      serializers.serialize(object.sender,
          specifiedType: const FullType(String)),
      'recipient',
      serializers.serialize(object.recipient,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  EmailInfo deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = EmailInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'subject':
          result.subject = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'body':
          result.body = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'sender':
          result.sender = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'recipient':
          result.recipient = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$PdfInfoSerializer implements StructuredSerializer<PdfInfo> {
  @override
  final Iterable<Type> types = const [PdfInfo, _$PdfInfo];
  @override
  final String wireName = 'PdfInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, PdfInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'bytesBase64',
      serializers.serialize(object.bytesBase64,
          specifiedType: const FullType(String)),
      'fileName',
      serializers.serialize(object.fileName,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  PdfInfo deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = PdfInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'bytesBase64':
          result.bytesBase64 = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'fileName':
          result.fileName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$JsonInfoSerializer implements StructuredSerializer<JsonInfo> {
  @override
  final Iterable<Type> types = const [JsonInfo, _$JsonInfo];
  @override
  final String wireName = 'JsonInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, JsonInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'data',
      serializers.serialize(object.data, specifiedType: const FullType(String)),
      'fileName',
      serializers.serialize(object.fileName,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  JsonInfo deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = JsonInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'data':
          result.data = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'fileName':
          result.fileName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$NewScreen extends NewScreen {
  @override
  final Screen screen;
  @override
  final String? parent;
  @override
  final Rectangle? parentRectangle;
  @override
  final AnalyticEvent? analyticEvent;
  @override
  final String? imageBase64;

  factory _$NewScreen([void Function(NewScreenBuilder)? updates]) =>
      (NewScreenBuilder()..update(updates)).build();

  _$NewScreen._(
      {required this.screen,
      this.parent,
      this.parentRectangle,
      this.analyticEvent,
      this.imageBase64})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(screen, 'NewScreen', 'screen');
  }

  @override
  NewScreen rebuild(void Function(NewScreenBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NewScreenBuilder toBuilder() => NewScreenBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NewScreen &&
        screen == other.screen &&
        parent == other.parent &&
        parentRectangle == other.parentRectangle &&
        analyticEvent == other.analyticEvent &&
        imageBase64 == other.imageBase64;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc($jc($jc(0, screen.hashCode), parent.hashCode),
                parentRectangle.hashCode),
            analyticEvent.hashCode),
        imageBase64.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('NewScreen')
          ..add('screen', screen)
          ..add('parent', parent)
          ..add('parentRectangle', parentRectangle)
          ..add('analyticEvent', analyticEvent)
          ..add('imageBase64', imageBase64))
        .toString();
  }
}

class NewScreenBuilder implements Builder<NewScreen, NewScreenBuilder> {
  _$NewScreen? _$v;

  ScreenBuilder? _screen;
  ScreenBuilder get screen => _$this._screen ??= ScreenBuilder();
  set screen(ScreenBuilder? screen) => _$this._screen = screen;

  String? _parent;
  String? get parent => _$this._parent;
  set parent(String? parent) => _$this._parent = parent;

  RectangleBuilder? _parentRectangle;
  RectangleBuilder get parentRectangle =>
      _$this._parentRectangle ??= RectangleBuilder();
  set parentRectangle(RectangleBuilder? parentRectangle) =>
      _$this._parentRectangle = parentRectangle;

  AnalyticEventBuilder? _analyticEvent;
  AnalyticEventBuilder get analyticEvent =>
      _$this._analyticEvent ??= AnalyticEventBuilder();
  set analyticEvent(AnalyticEventBuilder? analyticEvent) =>
      _$this._analyticEvent = analyticEvent;

  String? _imageBase64;
  String? get imageBase64 => _$this._imageBase64;
  set imageBase64(String? imageBase64) => _$this._imageBase64 = imageBase64;

  NewScreenBuilder();

  NewScreenBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _screen = $v.screen.toBuilder();
      _parent = $v.parent;
      _parentRectangle = $v.parentRectangle?.toBuilder();
      _analyticEvent = $v.analyticEvent?.toBuilder();
      _imageBase64 = $v.imageBase64;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NewScreen other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$NewScreen;
  }

  @override
  void update(void Function(NewScreenBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$NewScreen build() {
    _$NewScreen _$result;
    try {
      _$result = _$v ??
          _$NewScreen._(
              screen: screen.build(),
              parent: parent,
              parentRectangle: _parentRectangle?.build(),
              analyticEvent: _analyticEvent?.build(),
              imageBase64: imageBase64);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'screen';
        screen.build();

        _$failedField = 'parentRectangle';
        _parentRectangle?.build();
        _$failedField = 'analyticEvent';
        _analyticEvent?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            'NewScreen', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$Screen extends Screen {
  @override
  final String id;
  @override
  final BuiltList<TextInfo> texts;
  @override
  final BuiltList<ScreenLink> next;
  @override
  final String? pathName;
  @override
  final String name;
  @override
  final Uint8List? imageBytes;
  @override
  final String? documentationKey;
  @override
  final bool isCollapsable;
  @override
  final bool isCollapsed;
  @override
  final BuiltList<Screen> collapsedScreens;
  @override
  final BrowserInfo? browser;
  @override
  final EmailInfo? email;
  @override
  final PdfInfo? pdf;
  @override
  final JsonInfo? json;

  factory _$Screen([void Function(ScreenBuilder)? updates]) =>
      (ScreenBuilder()..update(updates)).build();

  _$Screen._(
      {required this.id,
      required this.texts,
      required this.next,
      this.pathName,
      required this.name,
      this.imageBytes,
      this.documentationKey,
      required this.isCollapsable,
      required this.isCollapsed,
      required this.collapsedScreens,
      this.browser,
      this.email,
      this.pdf,
      this.json})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(id, 'Screen', 'id');
    BuiltValueNullFieldError.checkNotNull(texts, 'Screen', 'texts');
    BuiltValueNullFieldError.checkNotNull(next, 'Screen', 'next');
    BuiltValueNullFieldError.checkNotNull(name, 'Screen', 'name');
    BuiltValueNullFieldError.checkNotNull(
        isCollapsable, 'Screen', 'isCollapsable');
    BuiltValueNullFieldError.checkNotNull(isCollapsed, 'Screen', 'isCollapsed');
    BuiltValueNullFieldError.checkNotNull(
        collapsedScreens, 'Screen', 'collapsedScreens');
  }

  @override
  Screen rebuild(void Function(ScreenBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScreenBuilder toBuilder() => ScreenBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Screen &&
        id == other.id &&
        texts == other.texts &&
        next == other.next &&
        pathName == other.pathName &&
        name == other.name &&
        imageBytes == other.imageBytes &&
        documentationKey == other.documentationKey &&
        isCollapsable == other.isCollapsable &&
        isCollapsed == other.isCollapsed &&
        collapsedScreens == other.collapsedScreens &&
        browser == other.browser &&
        email == other.email &&
        pdf == other.pdf &&
        json == other.json;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc(
                        $jc(
                            $jc(
                                $jc(
                                    $jc(
                                        $jc(
                                            $jc(
                                                $jc(
                                                    $jc($jc(0, id.hashCode),
                                                        texts.hashCode),
                                                    next.hashCode),
                                                pathName.hashCode),
                                            name.hashCode),
                                        imageBytes.hashCode),
                                    documentationKey.hashCode),
                                isCollapsable.hashCode),
                            isCollapsed.hashCode),
                        collapsedScreens.hashCode),
                    browser.hashCode),
                email.hashCode),
            pdf.hashCode),
        json.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('Screen')
          ..add('id', id)
          ..add('texts', texts)
          ..add('next', next)
          ..add('pathName', pathName)
          ..add('name', name)
          ..add('imageBytes', imageBytes)
          ..add('documentationKey', documentationKey)
          ..add('isCollapsable', isCollapsable)
          ..add('isCollapsed', isCollapsed)
          ..add('collapsedScreens', collapsedScreens)
          ..add('browser', browser)
          ..add('email', email)
          ..add('pdf', pdf)
          ..add('json', json))
        .toString();
  }
}

class ScreenBuilder implements Builder<Screen, ScreenBuilder> {
  _$Screen? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  ListBuilder<TextInfo>? _texts;
  ListBuilder<TextInfo> get texts => _$this._texts ??= ListBuilder<TextInfo>();
  set texts(ListBuilder<TextInfo>? texts) => _$this._texts = texts;

  ListBuilder<ScreenLink>? _next;
  ListBuilder<ScreenLink> get next =>
      _$this._next ??= ListBuilder<ScreenLink>();
  set next(ListBuilder<ScreenLink>? next) => _$this._next = next;

  String? _pathName;
  String? get pathName => _$this._pathName;
  set pathName(String? pathName) => _$this._pathName = pathName;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  Uint8List? _imageBytes;
  Uint8List? get imageBytes => _$this._imageBytes;
  set imageBytes(Uint8List? imageBytes) => _$this._imageBytes = imageBytes;

  String? _documentationKey;
  String? get documentationKey => _$this._documentationKey;
  set documentationKey(String? documentationKey) =>
      _$this._documentationKey = documentationKey;

  bool? _isCollapsable;
  bool? get isCollapsable => _$this._isCollapsable;
  set isCollapsable(bool? isCollapsable) =>
      _$this._isCollapsable = isCollapsable;

  bool? _isCollapsed;
  bool? get isCollapsed => _$this._isCollapsed;
  set isCollapsed(bool? isCollapsed) => _$this._isCollapsed = isCollapsed;

  ListBuilder<Screen>? _collapsedScreens;
  ListBuilder<Screen> get collapsedScreens =>
      _$this._collapsedScreens ??= ListBuilder<Screen>();
  set collapsedScreens(ListBuilder<Screen>? collapsedScreens) =>
      _$this._collapsedScreens = collapsedScreens;

  BrowserInfoBuilder? _browser;
  BrowserInfoBuilder get browser => _$this._browser ??= BrowserInfoBuilder();
  set browser(BrowserInfoBuilder? browser) => _$this._browser = browser;

  EmailInfoBuilder? _email;
  EmailInfoBuilder get email => _$this._email ??= EmailInfoBuilder();
  set email(EmailInfoBuilder? email) => _$this._email = email;

  PdfInfoBuilder? _pdf;
  PdfInfoBuilder get pdf => _$this._pdf ??= PdfInfoBuilder();
  set pdf(PdfInfoBuilder? pdf) => _$this._pdf = pdf;

  JsonInfoBuilder? _json;
  JsonInfoBuilder get json => _$this._json ??= JsonInfoBuilder();
  set json(JsonInfoBuilder? json) => _$this._json = json;

  ScreenBuilder();

  ScreenBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _texts = $v.texts.toBuilder();
      _next = $v.next.toBuilder();
      _pathName = $v.pathName;
      _name = $v.name;
      _imageBytes = $v.imageBytes;
      _documentationKey = $v.documentationKey;
      _isCollapsable = $v.isCollapsable;
      _isCollapsed = $v.isCollapsed;
      _collapsedScreens = $v.collapsedScreens.toBuilder();
      _browser = $v.browser?.toBuilder();
      _email = $v.email?.toBuilder();
      _pdf = $v.pdf?.toBuilder();
      _json = $v.json?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Screen other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$Screen;
  }

  @override
  void update(void Function(ScreenBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$Screen build() {
    _$Screen _$result;
    try {
      _$result = _$v ??
          _$Screen._(
              id: BuiltValueNullFieldError.checkNotNull(id, 'Screen', 'id'),
              texts: texts.build(),
              next: next.build(),
              pathName: pathName,
              name:
                  BuiltValueNullFieldError.checkNotNull(name, 'Screen', 'name'),
              imageBytes: imageBytes,
              documentationKey: documentationKey,
              isCollapsable: BuiltValueNullFieldError.checkNotNull(
                  isCollapsable, 'Screen', 'isCollapsable'),
              isCollapsed: BuiltValueNullFieldError.checkNotNull(
                  isCollapsed, 'Screen', 'isCollapsed'),
              collapsedScreens: collapsedScreens.build(),
              browser: _browser?.build(),
              email: _email?.build(),
              pdf: _pdf?.build(),
              json: _json?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'texts';
        texts.build();
        _$failedField = 'next';
        next.build();

        _$failedField = 'collapsedScreens';
        collapsedScreens.build();
        _$failedField = 'browser';
        _browser?.build();
        _$failedField = 'email';
        _email?.build();
        _$failedField = 'pdf';
        _pdf?.build();
        _$failedField = 'json';
        _json?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError('Screen', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$TextInfo extends TextInfo {
  @override
  final String translationKey;
  @override
  final String rawTranslation;
  @override
  final String text;
  @override
  final Rectangle globalRectangle;
  @override
  final String? fontFamily;
  @override
  final double? fontSize;
  @override
  final int? color;
  @override
  final int? fontWeight;

  factory _$TextInfo([void Function(TextInfoBuilder)? updates]) =>
      (TextInfoBuilder()..update(updates)).build();

  _$TextInfo._(
      {required this.translationKey,
      required this.rawTranslation,
      required this.text,
      required this.globalRectangle,
      this.fontFamily,
      this.fontSize,
      this.color,
      this.fontWeight})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(
        translationKey, 'TextInfo', 'translationKey');
    BuiltValueNullFieldError.checkNotNull(
        rawTranslation, 'TextInfo', 'rawTranslation');
    BuiltValueNullFieldError.checkNotNull(text, 'TextInfo', 'text');
    BuiltValueNullFieldError.checkNotNull(
        globalRectangle, 'TextInfo', 'globalRectangle');
  }

  @override
  TextInfo rebuild(void Function(TextInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TextInfoBuilder toBuilder() => TextInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TextInfo &&
        translationKey == other.translationKey &&
        rawTranslation == other.rawTranslation &&
        text == other.text &&
        globalRectangle == other.globalRectangle &&
        fontFamily == other.fontFamily &&
        fontSize == other.fontSize &&
        color == other.color &&
        fontWeight == other.fontWeight;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc(
                        $jc(
                            $jc($jc(0, translationKey.hashCode),
                                rawTranslation.hashCode),
                            text.hashCode),
                        globalRectangle.hashCode),
                    fontFamily.hashCode),
                fontSize.hashCode),
            color.hashCode),
        fontWeight.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('TextInfo')
          ..add('translationKey', translationKey)
          ..add('rawTranslation', rawTranslation)
          ..add('text', text)
          ..add('globalRectangle', globalRectangle)
          ..add('fontFamily', fontFamily)
          ..add('fontSize', fontSize)
          ..add('color', color)
          ..add('fontWeight', fontWeight))
        .toString();
  }
}

class TextInfoBuilder implements Builder<TextInfo, TextInfoBuilder> {
  _$TextInfo? _$v;

  String? _translationKey;
  String? get translationKey => _$this._translationKey;
  set translationKey(String? translationKey) =>
      _$this._translationKey = translationKey;

  String? _rawTranslation;
  String? get rawTranslation => _$this._rawTranslation;
  set rawTranslation(String? rawTranslation) =>
      _$this._rawTranslation = rawTranslation;

  String? _text;
  String? get text => _$this._text;
  set text(String? text) => _$this._text = text;

  RectangleBuilder? _globalRectangle;
  RectangleBuilder get globalRectangle =>
      _$this._globalRectangle ??= RectangleBuilder();
  set globalRectangle(RectangleBuilder? globalRectangle) =>
      _$this._globalRectangle = globalRectangle;

  String? _fontFamily;
  String? get fontFamily => _$this._fontFamily;
  set fontFamily(String? fontFamily) => _$this._fontFamily = fontFamily;

  double? _fontSize;
  double? get fontSize => _$this._fontSize;
  set fontSize(double? fontSize) => _$this._fontSize = fontSize;

  int? _color;
  int? get color => _$this._color;
  set color(int? color) => _$this._color = color;

  int? _fontWeight;
  int? get fontWeight => _$this._fontWeight;
  set fontWeight(int? fontWeight) => _$this._fontWeight = fontWeight;

  TextInfoBuilder();

  TextInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _translationKey = $v.translationKey;
      _rawTranslation = $v.rawTranslation;
      _text = $v.text;
      _globalRectangle = $v.globalRectangle.toBuilder();
      _fontFamily = $v.fontFamily;
      _fontSize = $v.fontSize;
      _color = $v.color;
      _fontWeight = $v.fontWeight;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TextInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$TextInfo;
  }

  @override
  void update(void Function(TextInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$TextInfo build() {
    _$TextInfo _$result;
    try {
      _$result = _$v ??
          _$TextInfo._(
              translationKey: BuiltValueNullFieldError.checkNotNull(
                  translationKey, 'TextInfo', 'translationKey'),
              rawTranslation: BuiltValueNullFieldError.checkNotNull(
                  rawTranslation, 'TextInfo', 'rawTranslation'),
              text: BuiltValueNullFieldError.checkNotNull(
                  text, 'TextInfo', 'text'),
              globalRectangle: globalRectangle.build(),
              fontFamily: fontFamily,
              fontSize: fontSize,
              color: color,
              fontWeight: fontWeight);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'globalRectangle';
        globalRectangle.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            'TextInfo', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$ScreenLink extends ScreenLink {
  @override
  final String to;
  @override
  final Rectangle? tapRect;
  @override
  final AnalyticEvent? analytic;

  factory _$ScreenLink([void Function(ScreenLinkBuilder)? updates]) =>
      (ScreenLinkBuilder()..update(updates)).build();

  _$ScreenLink._({required this.to, this.tapRect, this.analytic}) : super._() {
    BuiltValueNullFieldError.checkNotNull(to, 'ScreenLink', 'to');
  }

  @override
  ScreenLink rebuild(void Function(ScreenLinkBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScreenLinkBuilder toBuilder() => ScreenLinkBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScreenLink &&
        to == other.to &&
        tapRect == other.tapRect &&
        analytic == other.analytic;
  }

  @override
  int get hashCode {
    return $jf(
        $jc($jc($jc(0, to.hashCode), tapRect.hashCode), analytic.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ScreenLink')
          ..add('to', to)
          ..add('tapRect', tapRect)
          ..add('analytic', analytic))
        .toString();
  }
}

class ScreenLinkBuilder implements Builder<ScreenLink, ScreenLinkBuilder> {
  _$ScreenLink? _$v;

  String? _to;
  String? get to => _$this._to;
  set to(String? to) => _$this._to = to;

  RectangleBuilder? _tapRect;
  RectangleBuilder get tapRect => _$this._tapRect ??= RectangleBuilder();
  set tapRect(RectangleBuilder? tapRect) => _$this._tapRect = tapRect;

  AnalyticEventBuilder? _analytic;
  AnalyticEventBuilder get analytic =>
      _$this._analytic ??= AnalyticEventBuilder();
  set analytic(AnalyticEventBuilder? analytic) => _$this._analytic = analytic;

  ScreenLinkBuilder();

  ScreenLinkBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _to = $v.to;
      _tapRect = $v.tapRect?.toBuilder();
      _analytic = $v.analytic?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScreenLink other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$ScreenLink;
  }

  @override
  void update(void Function(ScreenLinkBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ScreenLink build() {
    _$ScreenLink _$result;
    try {
      _$result = _$v ??
          _$ScreenLink._(
              to: BuiltValueNullFieldError.checkNotNull(to, 'ScreenLink', 'to'),
              tapRect: _tapRect?.build(),
              analytic: _analytic?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'tapRect';
        _tapRect?.build();
        _$failedField = 'analytic';
        _analytic?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            'ScreenLink', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$AnalyticEvent extends AnalyticEvent {
  @override
  final String event;
  @override
  final BuiltMap<String, String> args;

  factory _$AnalyticEvent([void Function(AnalyticEventBuilder)? updates]) =>
      (AnalyticEventBuilder()..update(updates)).build();

  _$AnalyticEvent._({required this.event, required this.args}) : super._() {
    BuiltValueNullFieldError.checkNotNull(event, 'AnalyticEvent', 'event');
    BuiltValueNullFieldError.checkNotNull(args, 'AnalyticEvent', 'args');
  }

  @override
  AnalyticEvent rebuild(void Function(AnalyticEventBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AnalyticEventBuilder toBuilder() => AnalyticEventBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AnalyticEvent && event == other.event && args == other.args;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, event.hashCode), args.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('AnalyticEvent')
          ..add('event', event)
          ..add('args', args))
        .toString();
  }
}

class AnalyticEventBuilder
    implements Builder<AnalyticEvent, AnalyticEventBuilder> {
  _$AnalyticEvent? _$v;

  String? _event;
  String? get event => _$this._event;
  set event(String? event) => _$this._event = event;

  MapBuilder<String, String>? _args;
  MapBuilder<String, String> get args =>
      _$this._args ??= MapBuilder<String, String>();
  set args(MapBuilder<String, String>? args) => _$this._args = args;

  AnalyticEventBuilder();

  AnalyticEventBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _event = $v.event;
      _args = $v.args.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AnalyticEvent other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$AnalyticEvent;
  }

  @override
  void update(void Function(AnalyticEventBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$AnalyticEvent build() {
    _$AnalyticEvent _$result;
    try {
      _$result = _$v ??
          _$AnalyticEvent._(
              event: BuiltValueNullFieldError.checkNotNull(
                  event, 'AnalyticEvent', 'event'),
              args: args.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'args';
        args.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            'AnalyticEvent', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$BrowserInfo extends BrowserInfo {
  @override
  final String url;
  @override
  final bool useSafariVC;
  @override
  final bool useWebView;

  factory _$BrowserInfo([void Function(BrowserInfoBuilder)? updates]) =>
      (BrowserInfoBuilder()..update(updates)).build();

  _$BrowserInfo._(
      {required this.url, required this.useSafariVC, required this.useWebView})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(url, 'BrowserInfo', 'url');
    BuiltValueNullFieldError.checkNotNull(
        useSafariVC, 'BrowserInfo', 'useSafariVC');
    BuiltValueNullFieldError.checkNotNull(
        useWebView, 'BrowserInfo', 'useWebView');
  }

  @override
  BrowserInfo rebuild(void Function(BrowserInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BrowserInfoBuilder toBuilder() => BrowserInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BrowserInfo &&
        url == other.url &&
        useSafariVC == other.useSafariVC &&
        useWebView == other.useWebView;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc(0, url.hashCode), useSafariVC.hashCode), useWebView.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('BrowserInfo')
          ..add('url', url)
          ..add('useSafariVC', useSafariVC)
          ..add('useWebView', useWebView))
        .toString();
  }
}

class BrowserInfoBuilder implements Builder<BrowserInfo, BrowserInfoBuilder> {
  _$BrowserInfo? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  bool? _useSafariVC;
  bool? get useSafariVC => _$this._useSafariVC;
  set useSafariVC(bool? useSafariVC) => _$this._useSafariVC = useSafariVC;

  bool? _useWebView;
  bool? get useWebView => _$this._useWebView;
  set useWebView(bool? useWebView) => _$this._useWebView = useWebView;

  BrowserInfoBuilder();

  BrowserInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _useSafariVC = $v.useSafariVC;
      _useWebView = $v.useWebView;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BrowserInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$BrowserInfo;
  }

  @override
  void update(void Function(BrowserInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$BrowserInfo build() {
    final _$result = _$v ??
        _$BrowserInfo._(
            url: BuiltValueNullFieldError.checkNotNull(
                url, 'BrowserInfo', 'url'),
            useSafariVC: BuiltValueNullFieldError.checkNotNull(
                useSafariVC, 'BrowserInfo', 'useSafariVC'),
            useWebView: BuiltValueNullFieldError.checkNotNull(
                useWebView, 'BrowserInfo', 'useWebView'));
    replace(_$result);
    return _$result;
  }
}

class _$EmailInfo extends EmailInfo {
  @override
  final String subject;
  @override
  final String body;
  @override
  final String sender;
  @override
  final String recipient;

  factory _$EmailInfo([void Function(EmailInfoBuilder)? updates]) =>
      (EmailInfoBuilder()..update(updates)).build();

  _$EmailInfo._(
      {required this.subject,
      required this.body,
      required this.sender,
      required this.recipient})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(subject, 'EmailInfo', 'subject');
    BuiltValueNullFieldError.checkNotNull(body, 'EmailInfo', 'body');
    BuiltValueNullFieldError.checkNotNull(sender, 'EmailInfo', 'sender');
    BuiltValueNullFieldError.checkNotNull(recipient, 'EmailInfo', 'recipient');
  }

  @override
  EmailInfo rebuild(void Function(EmailInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmailInfoBuilder toBuilder() => EmailInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmailInfo &&
        subject == other.subject &&
        body == other.body &&
        sender == other.sender &&
        recipient == other.recipient;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc($jc(0, subject.hashCode), body.hashCode), sender.hashCode),
        recipient.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('EmailInfo')
          ..add('subject', subject)
          ..add('body', body)
          ..add('sender', sender)
          ..add('recipient', recipient))
        .toString();
  }
}

class EmailInfoBuilder implements Builder<EmailInfo, EmailInfoBuilder> {
  _$EmailInfo? _$v;

  String? _subject;
  String? get subject => _$this._subject;
  set subject(String? subject) => _$this._subject = subject;

  String? _body;
  String? get body => _$this._body;
  set body(String? body) => _$this._body = body;

  String? _sender;
  String? get sender => _$this._sender;
  set sender(String? sender) => _$this._sender = sender;

  String? _recipient;
  String? get recipient => _$this._recipient;
  set recipient(String? recipient) => _$this._recipient = recipient;

  EmailInfoBuilder();

  EmailInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _subject = $v.subject;
      _body = $v.body;
      _sender = $v.sender;
      _recipient = $v.recipient;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmailInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$EmailInfo;
  }

  @override
  void update(void Function(EmailInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$EmailInfo build() {
    final _$result = _$v ??
        _$EmailInfo._(
            subject: BuiltValueNullFieldError.checkNotNull(
                subject, 'EmailInfo', 'subject'),
            body: BuiltValueNullFieldError.checkNotNull(
                body, 'EmailInfo', 'body'),
            sender: BuiltValueNullFieldError.checkNotNull(
                sender, 'EmailInfo', 'sender'),
            recipient: BuiltValueNullFieldError.checkNotNull(
                recipient, 'EmailInfo', 'recipient'));
    replace(_$result);
    return _$result;
  }
}

class _$PdfInfo extends PdfInfo {
  @override
  final String bytesBase64;
  @override
  final String fileName;

  factory _$PdfInfo([void Function(PdfInfoBuilder)? updates]) =>
      (PdfInfoBuilder()..update(updates)).build();

  _$PdfInfo._({required this.bytesBase64, required this.fileName}) : super._() {
    BuiltValueNullFieldError.checkNotNull(
        bytesBase64, 'PdfInfo', 'bytesBase64');
    BuiltValueNullFieldError.checkNotNull(fileName, 'PdfInfo', 'fileName');
  }

  @override
  PdfInfo rebuild(void Function(PdfInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PdfInfoBuilder toBuilder() => PdfInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PdfInfo &&
        bytesBase64 == other.bytesBase64 &&
        fileName == other.fileName;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, bytesBase64.hashCode), fileName.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('PdfInfo')
          ..add('bytesBase64', bytesBase64)
          ..add('fileName', fileName))
        .toString();
  }
}

class PdfInfoBuilder implements Builder<PdfInfo, PdfInfoBuilder> {
  _$PdfInfo? _$v;

  String? _bytesBase64;
  String? get bytesBase64 => _$this._bytesBase64;
  set bytesBase64(String? bytesBase64) => _$this._bytesBase64 = bytesBase64;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  PdfInfoBuilder();

  PdfInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bytesBase64 = $v.bytesBase64;
      _fileName = $v.fileName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PdfInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$PdfInfo;
  }

  @override
  void update(void Function(PdfInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$PdfInfo build() {
    final _$result = _$v ??
        _$PdfInfo._(
            bytesBase64: BuiltValueNullFieldError.checkNotNull(
                bytesBase64, 'PdfInfo', 'bytesBase64'),
            fileName: BuiltValueNullFieldError.checkNotNull(
                fileName, 'PdfInfo', 'fileName'));
    replace(_$result);
    return _$result;
  }
}

class _$JsonInfo extends JsonInfo {
  @override
  final String data;
  @override
  final String fileName;

  factory _$JsonInfo([void Function(JsonInfoBuilder)? updates]) =>
      (JsonInfoBuilder()..update(updates)).build();

  _$JsonInfo._({required this.data, required this.fileName}) : super._() {
    BuiltValueNullFieldError.checkNotNull(data, 'JsonInfo', 'data');
    BuiltValueNullFieldError.checkNotNull(fileName, 'JsonInfo', 'fileName');
  }

  @override
  JsonInfo rebuild(void Function(JsonInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  JsonInfoBuilder toBuilder() => JsonInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is JsonInfo &&
        data == other.data &&
        fileName == other.fileName;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, data.hashCode), fileName.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('JsonInfo')
          ..add('data', data)
          ..add('fileName', fileName))
        .toString();
  }
}

class JsonInfoBuilder implements Builder<JsonInfo, JsonInfoBuilder> {
  _$JsonInfo? _$v;

  String? _data;
  String? get data => _$this._data;
  set data(String? data) => _$this._data = data;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  JsonInfoBuilder();

  JsonInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _data = $v.data;
      _fileName = $v.fileName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(JsonInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$JsonInfo;
  }

  @override
  void update(void Function(JsonInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$JsonInfo build() {
    final _$result = _$v ??
        _$JsonInfo._(
            data:
                BuiltValueNullFieldError.checkNotNull(data, 'JsonInfo', 'data'),
            fileName: BuiltValueNullFieldError.checkNotNull(
                fileName, 'JsonInfo', 'fileName'));
    replace(_$result);
    return _$result;
  }
}

class _$DocumentationScreen extends DocumentationScreen {
  @override
  final File? screenshot;
  @override
  final Screen screen;
  @override
  final RunArgs args;

  factory _$DocumentationScreen(
          [void Function(DocumentationScreenBuilder)? updates]) =>
      (DocumentationScreenBuilder()..update(updates)).build();

  _$DocumentationScreen._(
      {this.screenshot, required this.screen, required this.args})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(
        screen, 'DocumentationScreen', 'screen');
    BuiltValueNullFieldError.checkNotNull(args, 'DocumentationScreen', 'args');
  }

  @override
  DocumentationScreen rebuild(
          void Function(DocumentationScreenBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DocumentationScreenBuilder toBuilder() =>
      DocumentationScreenBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DocumentationScreen &&
        screenshot == other.screenshot &&
        screen == other.screen &&
        args == other.args;
  }

  @override
  int get hashCode {
    return $jf(
        $jc($jc($jc(0, screenshot.hashCode), screen.hashCode), args.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('DocumentationScreen')
          ..add('screenshot', screenshot)
          ..add('screen', screen)
          ..add('args', args))
        .toString();
  }
}

class DocumentationScreenBuilder
    implements Builder<DocumentationScreen, DocumentationScreenBuilder> {
  _$DocumentationScreen? _$v;

  File? _screenshot;
  File? get screenshot => _$this._screenshot;
  set screenshot(File? screenshot) => _$this._screenshot = screenshot;

  ScreenBuilder? _screen;
  ScreenBuilder get screen => _$this._screen ??= ScreenBuilder();
  set screen(ScreenBuilder? screen) => _$this._screen = screen;

  RunArgsBuilder? _args;
  RunArgsBuilder get args => _$this._args ??= RunArgsBuilder();
  set args(RunArgsBuilder? args) => _$this._args = args;

  DocumentationScreenBuilder();

  DocumentationScreenBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _screenshot = $v.screenshot;
      _screen = $v.screen.toBuilder();
      _args = $v.args.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DocumentationScreen other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$DocumentationScreen;
  }

  @override
  void update(void Function(DocumentationScreenBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$DocumentationScreen build() {
    _$DocumentationScreen _$result;
    try {
      _$result = _$v ??
          _$DocumentationScreen._(
              screenshot: screenshot,
              screen: screen.build(),
              args: args.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'screen';
        screen.build();
        _$failedField = 'args';
        args.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            'DocumentationScreen', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
