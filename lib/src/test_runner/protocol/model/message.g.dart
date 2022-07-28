// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MessageType _$request = MessageType._('request');
const MessageType _$response = MessageType._('response');
const MessageType _$error = MessageType._('error');

MessageType _$valueOf(String name) {
  switch (name) {
    case 'request':
      return _$request;
    case 'response':
      return _$response;
    case 'error':
      return _$error;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MessageType> _$values =
    BuiltSet<MessageType>(const <MessageType>[
  _$request,
  _$response,
  _$error,
]);

Serializers _$messageSerializers = (Serializers().toBuilder()
      ..add(Message.serializer)
      ..add(MessageType.serializer))
    .build();
Serializer<Message> _$messageSerializer = _$MessageSerializer();
Serializer<MessageType> _$messageTypeSerializer = _$MessageTypeSerializer();

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
    final result = MessageBuilder();

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
      (MessageBuilder()..update(updates))._build();

  _$Message._(
      {required this.type,
      required this.id,
      required this.channel,
      required this.method,
      required this.serializedParameter1,
      this.serializedParameter2,
      this.serializedParameter3})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(type, 'Message', 'type');
    BuiltValueNullFieldError.checkNotNull(id, 'Message', 'id');
    BuiltValueNullFieldError.checkNotNull(channel, 'Message', 'channel');
    BuiltValueNullFieldError.checkNotNull(method, 'Message', 'method');
    BuiltValueNullFieldError.checkNotNull(
        serializedParameter1, 'Message', 'serializedParameter1');
  }

  @override
  Message rebuild(void Function(MessageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MessageBuilder toBuilder() => MessageBuilder()..replace(this);

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
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc($jc($jc(0, type.hashCode), id.hashCode),
                        channel.hashCode),
                    method.hashCode),
                serializedParameter1.hashCode),
            serializedParameter2.hashCode),
        serializedParameter3.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('Message')
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
        _$Message._(
            type:
                BuiltValueNullFieldError.checkNotNull(type, 'Message', 'type'),
            id: BuiltValueNullFieldError.checkNotNull(id, 'Message', 'id'),
            channel: BuiltValueNullFieldError.checkNotNull(
                channel, 'Message', 'channel'),
            method: BuiltValueNullFieldError.checkNotNull(
                method, 'Message', 'method'),
            serializedParameter1: BuiltValueNullFieldError.checkNotNull(
                serializedParameter1, 'Message', 'serializedParameter1'),
            serializedParameter2: serializedParameter2,
            serializedParameter3: serializedParameter3);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
