// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MessageType _$request = const MessageType._('request');
const MessageType _$response = const MessageType._('response');
const MessageType _$error = const MessageType._('error');

MessageType _$valueOf(String name) {
  switch (name) {
    case 'request':
      return _$request;
    case 'response':
      return _$response;
    case 'error':
      return _$error;
    default:
      throw new ArgumentError(name);
  }
}

final BuiltSet<MessageType> _$values =
    new BuiltSet<MessageType>(const <MessageType>[
  _$request,
  _$response,
  _$error,
]);

Serializers _$messageSerializers = (new Serializers().toBuilder()
      ..add(Message.serializer)
      ..add(MessageType.serializer))
    .build();
Serializer<Message> _$messageSerializer = new _$MessageSerializer();
Serializer<MessageType> _$messageTypeSerializer = new _$MessageTypeSerializer();

class _$MessageSerializer implements StructuredSerializer<Message> {
  @override
  final Iterable<Type> types = const [Message, _$Message];
  @override
  final String wireName = 'Message';

  @override
  Iterable<Object?> serialize(Serializers serializers, Message object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'type',
      serializers.serialize(object.type,
          specifiedType: const FullType(MessageType)),
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(int)),
      'channel',
      serializers.serialize(object.channel,
          specifiedType: const FullType(String)),
      'method',
      serializers.serialize(object.method,
          specifiedType: const FullType(String)),
      'serializedParameter1',
      serializers.serialize(object.serializedParameter1,
          specifiedType: const FullType(String)),
    ];
    Object? value;
    value = object.serializedParameter2;
    if (value != null) {
      result
        ..add('serializedParameter2')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.serializedParameter3;
    if (value != null) {
      result
        ..add('serializedParameter3')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  Message deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new MessageBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'type':
          result.type = serializers.deserialize(value,
              specifiedType: const FullType(MessageType))! as MessageType;
          break;
        case 'id':
          result.id = serializers.deserialize(value,
              specifiedType: const FullType(int))! as int;
          break;
        case 'channel':
          result.channel = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'method':
          result.method = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'serializedParameter1':
          result.serializedParameter1 = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'serializedParameter2':
          result.serializedParameter2 = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'serializedParameter3':
          result.serializedParameter3 = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
      }
    }

    return result.build();
  }
}

class _$MessageTypeSerializer implements PrimitiveSerializer<MessageType> {
  @override
  final Iterable<Type> types = const <Type>[MessageType];
  @override
  final String wireName = 'MessageType';

  @override
  Object serialize(Serializers serializers, MessageType object,
          {FullType specifiedType = FullType.unspecified}) =>
      object.name;

  @override
  MessageType deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      MessageType.valueOf(serialized as String);
}

class _$Message extends Message {
  @override
  final MessageType type;
  @override
  final int id;
  @override
  final String channel;
  @override
  final String method;
  @override
  final String serializedParameter1;
  @override
  final String? serializedParameter2;
  @override
  final String? serializedParameter3;

  factory _$Message([void Function(MessageBuilder)? updates]) =>
      (new MessageBuilder()..update(updates))._build();

  _$Message._(
      {required this.type,
      required this.id,
      required this.channel,
      required this.method,
      required this.serializedParameter1,
      this.serializedParameter2,
      this.serializedParameter3})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(type, r'Message', 'type');
    BuiltValueNullFieldError.checkNotNull(id, r'Message', 'id');
    BuiltValueNullFieldError.checkNotNull(channel, r'Message', 'channel');
    BuiltValueNullFieldError.checkNotNull(method, r'Message', 'method');
    BuiltValueNullFieldError.checkNotNull(
        serializedParameter1, r'Message', 'serializedParameter1');
  }

  @override
  Message rebuild(void Function(MessageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MessageBuilder toBuilder() => new MessageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Message &&
        type == other.type &&
        id == other.id &&
        channel == other.channel &&
        method == other.method &&
        serializedParameter1 == other.serializedParameter1 &&
        serializedParameter2 == other.serializedParameter2 &&
        serializedParameter3 == other.serializedParameter3;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, channel.hashCode);
    _$hash = $jc(_$hash, method.hashCode);
    _$hash = $jc(_$hash, serializedParameter1.hashCode);
    _$hash = $jc(_$hash, serializedParameter2.hashCode);
    _$hash = $jc(_$hash, serializedParameter3.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Message')
          ..add('type', type)
          ..add('id', id)
          ..add('channel', channel)
          ..add('method', method)
          ..add('serializedParameter1', serializedParameter1)
          ..add('serializedParameter2', serializedParameter2)
          ..add('serializedParameter3', serializedParameter3))
        .toString();
  }
}

class MessageBuilder implements Builder<Message, MessageBuilder> {
  _$Message? _$v;

  MessageType? _type;
  MessageType? get type => _$this._type;
  set type(MessageType? type) => _$this._type = type;

  int? _id;
  int? get id => _$this._id;
  set id(int? id) => _$this._id = id;

  String? _channel;
  String? get channel => _$this._channel;
  set channel(String? channel) => _$this._channel = channel;

  String? _method;
  String? get method => _$this._method;
  set method(String? method) => _$this._method = method;

  String? _serializedParameter1;
  String? get serializedParameter1 => _$this._serializedParameter1;
  set serializedParameter1(String? serializedParameter1) =>
      _$this._serializedParameter1 = serializedParameter1;

  String? _serializedParameter2;
  String? get serializedParameter2 => _$this._serializedParameter2;
  set serializedParameter2(String? serializedParameter2) =>
      _$this._serializedParameter2 = serializedParameter2;

  String? _serializedParameter3;
  String? get serializedParameter3 => _$this._serializedParameter3;
  set serializedParameter3(String? serializedParameter3) =>
      _$this._serializedParameter3 = serializedParameter3;

  MessageBuilder();

  MessageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _id = $v.id;
      _channel = $v.channel;
      _method = $v.method;
      _serializedParameter1 = $v.serializedParameter1;
      _serializedParameter2 = $v.serializedParameter2;
      _serializedParameter3 = $v.serializedParameter3;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Message other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$Message;
  }

  @override
  void update(void Function(MessageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Message build() => _build();

  _$Message _build() {
    final _$result = _$v ??
        new _$Message._(
            type:
                BuiltValueNullFieldError.checkNotNull(type, r'Message', 'type'),
            id: BuiltValueNullFieldError.checkNotNull(id, r'Message', 'id'),
            channel: BuiltValueNullFieldError.checkNotNull(
                channel, r'Message', 'channel'),
            method: BuiltValueNullFieldError.checkNotNull(
                method, r'Message', 'method'),
            serializedParameter1: BuiltValueNullFieldError.checkNotNull(
                serializedParameter1, r'Message', 'serializedParameter1'),
            serializedParameter2: serializedParameter2,
            serializedParameter3: serializedParameter3);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
