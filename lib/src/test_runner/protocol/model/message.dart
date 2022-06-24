import 'dart:convert';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'message.g.dart';

abstract class Message implements Built<Message, MessageBuilder> {
  static Serializer<Message> get serializer => _$messageSerializer;

  MessageType get type;
  int get id;
  String get channel;
  String get method;
  String get serializedParameter1;

  String? get serializedParameter2;

  String? get serializedParameter3;

  factory Message([void Function(MessageBuilder b) updates]) = _$Message;

  Message._();

  static Message decode(String serialized) {
    return messageSerializers.deserialize(jsonDecode(serialized))! as Message;
  }

  static String encode(Message message) {
    var serializedMessage = messageSerializers.serialize(message);
    return jsonEncode(serializedMessage);
  }
}

class MessageType extends EnumClass {
  static Serializer<MessageType> get serializer => _$messageTypeSerializer;

  static const MessageType request = _$request;
  static const MessageType response = _$response;
  static const MessageType error = _$error;

  const MessageType._(String name) : super(name);

  static BuiltSet<MessageType> get values => _$values;
  static MessageType valueOf(String name) => _$valueOf(name);
}

@SerializersFor([
  Message,
  MessageType,
])
final Serializers messageSerializers = _$messageSerializers;
