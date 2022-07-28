// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'screen.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<NewScreen> _$newScreenSerializer = _$NewScreenSerializer();
Serializer<ImageFile> _$imageFileSerializer = _$ImageFileSerializer();
Serializer<Screen> _$screenSerializer = _$ScreenSerializer();
Serializer<TextInfo> _$textInfoSerializer = _$TextInfoSerializer();
Serializer<ScreenLink> _$screenLinkSerializer = _$ScreenLinkSerializer();

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
    value = object.imageBase64;
    if (value != null) {
      result
        ..add('imageBase64')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.imageFile;
    if (value != null) {
      result
        ..add('imageFile')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(ImageFile)));
    }
    return result;
  }

  @override
  NewScreen deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = NewScreenBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
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
        case 'imageBase64':
          result.imageBase64 = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'imageFile':
          result.imageFile.replace(serializers.deserialize(value,
              specifiedType: const FullType(ImageFile))! as ImageFile);
          break;
      }
    }

    return result.build();
  }
}

class _$ImageFileSerializer implements StructuredSerializer<ImageFile> {
  @override
  final Iterable<Type> types = const [ImageFile, _$ImageFile];
  @override
  final String wireName = 'ImageFile';

  @override
  Iterable<Object?> serialize(Serializers serializers, ImageFile object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'path',
      serializers.serialize(object.path, specifiedType: const FullType(String)),
      'width',
      serializers.serialize(object.width, specifiedType: const FullType(int)),
      'height',
      serializers.serialize(object.height, specifiedType: const FullType(int)),
    ];

    return result;
  }

  @override
  ImageFile deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = ImageFileBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'path':
          result.path = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'width':
          result.width = serializers.deserialize(value,
              specifiedType: const FullType(int))! as int;
          break;
        case 'height':
          result.height = serializers.deserialize(value,
              specifiedType: const FullType(int))! as int;
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
    ];
    Object? value;
    value = object.splitName;
    if (value != null) {
      result
        ..add('splitName')
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
    value = object.imageFile;
    if (value != null) {
      result
        ..add('imageFile')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(ImageFile)));
    }
    value = object.topBrightness;
    if (value != null) {
      result
        ..add('topBrightness')
        ..add(serializers.serialize(value, specifiedType: const FullType(int)));
    }
    value = object.bottomBrightness;
    if (value != null) {
      result
        ..add('bottomBrightness')
        ..add(serializers.serialize(value, specifiedType: const FullType(int)));
    }
    value = object.supportedLocales;
    if (value != null) {
      result
        ..add('supportedLocales')
        ..add(serializers.serialize(value,
            specifiedType:
                const FullType(BuiltList, [FullType(SerializableLocale)])));
    }
    return result;
  }

  @override
  Screen deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = ScreenBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'id':
          result.id = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
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
        case 'splitName':
          result.splitName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'name':
          result.name = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'imageBytes':
          result.imageBytes = serializers.deserialize(value,
              specifiedType: const FullType(Uint8List)) as Uint8List?;
          break;
        case 'imageFile':
          result.imageFile.replace(serializers.deserialize(value,
              specifiedType: const FullType(ImageFile))! as ImageFile);
          break;
        case 'topBrightness':
          result.topBrightness = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int?;
          break;
        case 'bottomBrightness':
          result.bottomBrightness = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int?;
          break;
        case 'supportedLocales':
          result.supportedLocales.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, [FullType(SerializableLocale)]))!
              as BuiltList<Object?>);
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
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'translationKey':
          result.translationKey = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'rawTranslation':
          result.rawTranslation = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'text':
          result.text = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
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
    return result;
  }

  @override
  ScreenLink deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = ScreenLinkBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'to':
          result.to = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'tapRect':
          result.tapRect.replace(serializers.deserialize(value,
              specifiedType: const FullType(Rectangle))! as Rectangle);
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
  final String? imageBase64;
  @override
  final ImageFile? imageFile;

  factory _$NewScreen([void Function(NewScreenBuilder)? updates]) =>
      (NewScreenBuilder()..update(updates))._build();

  _$NewScreen._(
      {required this.screen,
      this.parent,
      this.parentRectangle,
      this.imageBase64,
      this.imageFile})
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
        imageBase64 == other.imageBase64 &&
        imageFile == other.imageFile;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc($jc($jc(0, screen.hashCode), parent.hashCode),
                parentRectangle.hashCode),
            imageBase64.hashCode),
        imageFile.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('NewScreen')
          ..add('screen', screen)
          ..add('parent', parent)
          ..add('parentRectangle', parentRectangle)
          ..add('imageBase64', imageBase64)
          ..add('imageFile', imageFile))
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

  String? _imageBase64;
  String? get imageBase64 => _$this._imageBase64;
  set imageBase64(String? imageBase64) => _$this._imageBase64 = imageBase64;

  ImageFileBuilder? _imageFile;
  ImageFileBuilder get imageFile => _$this._imageFile ??= ImageFileBuilder();
  set imageFile(ImageFileBuilder? imageFile) => _$this._imageFile = imageFile;

  NewScreenBuilder();

  NewScreenBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _screen = $v.screen.toBuilder();
      _parent = $v.parent;
      _parentRectangle = $v.parentRectangle?.toBuilder();
      _imageBase64 = $v.imageBase64;
      _imageFile = $v.imageFile?.toBuilder();
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
  NewScreen build() => _build();

  _$NewScreen _build() {
    _$NewScreen _$result;
    try {
      _$result = _$v ??
          _$NewScreen._(
              screen: screen.build(),
              parent: parent,
              parentRectangle: _parentRectangle?.build(),
              imageBase64: imageBase64,
              imageFile: _imageFile?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'screen';
        screen.build();

        _$failedField = 'parentRectangle';
        _parentRectangle?.build();

        _$failedField = 'imageFile';
        _imageFile?.build();
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

class _$ImageFile extends ImageFile {
  @override
  final String path;
  @override
  final int width;
  @override
  final int height;

  factory _$ImageFile([void Function(ImageFileBuilder)? updates]) =>
      (ImageFileBuilder()..update(updates))._build();

  _$ImageFile._({required this.path, required this.width, required this.height})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(path, 'ImageFile', 'path');
    BuiltValueNullFieldError.checkNotNull(width, 'ImageFile', 'width');
    BuiltValueNullFieldError.checkNotNull(height, 'ImageFile', 'height');
  }

  @override
  ImageFile rebuild(void Function(ImageFileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ImageFileBuilder toBuilder() => ImageFileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ImageFile &&
        path == other.path &&
        width == other.width &&
        height == other.height;
  }

  @override
  int get hashCode {
    return $jf(
        $jc($jc($jc(0, path.hashCode), width.hashCode), height.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ImageFile')
          ..add('path', path)
          ..add('width', width)
          ..add('height', height))
        .toString();
  }
}

class ImageFileBuilder implements Builder<ImageFile, ImageFileBuilder> {
  _$ImageFile? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  int? _width;
  int? get width => _$this._width;
  set width(int? width) => _$this._width = width;

  int? _height;
  int? get height => _$this._height;
  set height(int? height) => _$this._height = height;

  ImageFileBuilder();

  ImageFileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _width = $v.width;
      _height = $v.height;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ImageFile other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$ImageFile;
  }

  @override
  void update(void Function(ImageFileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ImageFile build() => _build();

  _$ImageFile _build() {
    final _$result = _$v ??
        _$ImageFile._(
            path: BuiltValueNullFieldError.checkNotNull(
                path, 'ImageFile', 'path'),
            width: BuiltValueNullFieldError.checkNotNull(
                width, 'ImageFile', 'width'),
            height: BuiltValueNullFieldError.checkNotNull(
                height, 'ImageFile', 'height'));
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
  final String? splitName;
  @override
  final String name;
  @override
  final Uint8List? imageBytes;
  @override
  final ImageFile? imageFile;
  @override
  final int? topBrightness;
  @override
  final int? bottomBrightness;
  @override
  final BuiltList<SerializableLocale>? supportedLocales;

  factory _$Screen([void Function(ScreenBuilder)? updates]) =>
      (ScreenBuilder()..update(updates))._build();

  _$Screen._(
      {required this.id,
      required this.texts,
      required this.next,
      this.splitName,
      required this.name,
      this.imageBytes,
      this.imageFile,
      this.topBrightness,
      this.bottomBrightness,
      this.supportedLocales})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(id, 'Screen', 'id');
    BuiltValueNullFieldError.checkNotNull(texts, 'Screen', 'texts');
    BuiltValueNullFieldError.checkNotNull(next, 'Screen', 'next');
    BuiltValueNullFieldError.checkNotNull(name, 'Screen', 'name');
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
        splitName == other.splitName &&
        name == other.name &&
        imageBytes == other.imageBytes &&
        imageFile == other.imageFile &&
        topBrightness == other.topBrightness &&
        bottomBrightness == other.bottomBrightness &&
        supportedLocales == other.supportedLocales;
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
                                $jc($jc($jc(0, id.hashCode), texts.hashCode),
                                    next.hashCode),
                                splitName.hashCode),
                            name.hashCode),
                        imageBytes.hashCode),
                    imageFile.hashCode),
                topBrightness.hashCode),
            bottomBrightness.hashCode),
        supportedLocales.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('Screen')
          ..add('id', id)
          ..add('texts', texts)
          ..add('next', next)
          ..add('splitName', splitName)
          ..add('name', name)
          ..add('imageBytes', imageBytes)
          ..add('imageFile', imageFile)
          ..add('topBrightness', topBrightness)
          ..add('bottomBrightness', bottomBrightness)
          ..add('supportedLocales', supportedLocales))
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

  String? _splitName;
  String? get splitName => _$this._splitName;
  set splitName(String? splitName) => _$this._splitName = splitName;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  Uint8List? _imageBytes;
  Uint8List? get imageBytes => _$this._imageBytes;
  set imageBytes(Uint8List? imageBytes) => _$this._imageBytes = imageBytes;

  ImageFileBuilder? _imageFile;
  ImageFileBuilder get imageFile => _$this._imageFile ??= ImageFileBuilder();
  set imageFile(ImageFileBuilder? imageFile) => _$this._imageFile = imageFile;

  int? _topBrightness;
  int? get topBrightness => _$this._topBrightness;
  set topBrightness(int? topBrightness) =>
      _$this._topBrightness = topBrightness;

  int? _bottomBrightness;
  int? get bottomBrightness => _$this._bottomBrightness;
  set bottomBrightness(int? bottomBrightness) =>
      _$this._bottomBrightness = bottomBrightness;

  ListBuilder<SerializableLocale>? _supportedLocales;
  ListBuilder<SerializableLocale> get supportedLocales =>
      _$this._supportedLocales ??= ListBuilder<SerializableLocale>();
  set supportedLocales(ListBuilder<SerializableLocale>? supportedLocales) =>
      _$this._supportedLocales = supportedLocales;

  ScreenBuilder();

  ScreenBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _texts = $v.texts.toBuilder();
      _next = $v.next.toBuilder();
      _splitName = $v.splitName;
      _name = $v.name;
      _imageBytes = $v.imageBytes;
      _imageFile = $v.imageFile?.toBuilder();
      _topBrightness = $v.topBrightness;
      _bottomBrightness = $v.bottomBrightness;
      _supportedLocales = $v.supportedLocales?.toBuilder();
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
  Screen build() => _build();

  _$Screen _build() {
    _$Screen _$result;
    try {
      _$result = _$v ??
          _$Screen._(
              id: BuiltValueNullFieldError.checkNotNull(id, 'Screen', 'id'),
              texts: texts.build(),
              next: next.build(),
              splitName: splitName,
              name:
                  BuiltValueNullFieldError.checkNotNull(name, 'Screen', 'name'),
              imageBytes: imageBytes,
              imageFile: _imageFile?.build(),
              topBrightness: topBrightness,
              bottomBrightness: bottomBrightness,
              supportedLocales: _supportedLocales?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'texts';
        texts.build();
        _$failedField = 'next';
        next.build();

        _$failedField = 'imageFile';
        _imageFile?.build();

        _$failedField = 'supportedLocales';
        _supportedLocales?.build();
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
      (TextInfoBuilder()..update(updates))._build();

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
  TextInfo build() => _build();

  _$TextInfo _build() {
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

  factory _$ScreenLink([void Function(ScreenLinkBuilder)? updates]) =>
      (ScreenLinkBuilder()..update(updates))._build();

  _$ScreenLink._({required this.to, this.tapRect}) : super._() {
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
    return other is ScreenLink && to == other.to && tapRect == other.tapRect;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, to.hashCode), tapRect.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ScreenLink')
          ..add('to', to)
          ..add('tapRect', tapRect))
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

  ScreenLinkBuilder();

  ScreenLinkBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _to = $v.to;
      _tapRect = $v.tapRect?.toBuilder();
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
  ScreenLink build() => _build();

  _$ScreenLink _build() {
    _$ScreenLink _$result;
    try {
      _$result = _$v ??
          _$ScreenLink._(
              to: BuiltValueNullFieldError.checkNotNull(to, 'ScreenLink', 'to'),
              tapRect: _tapRect?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'tapRect';
        _tapRect?.build();
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

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
