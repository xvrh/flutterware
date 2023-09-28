import 'dart:async';
import 'dart:convert';
import 'package:built_value/serializer.dart';
import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/stream_channel.dart';
import 'message.dart';

final _logger = Logger('connection');

class Connection {
  static int _messageId = 0;
  final StreamChannel<String> channel;
  final List<Channel> _channels = [];
  final Serializers parameterSerializers;
  late StreamSubscription _subscription;

  Connection(this.channel, this.parameterSerializers);

  void listen({required void Function() onClose}) {
    _subscription = channel.stream.listen(_onMessage, onDone: () {
      for (var channel in _channels) {
        channel.close();
      }

      onClose();
    }, onError: (e) {
      _logger.warning('Connection error', e);
      close();
      onClose();
    });
  }

  void close() {
    _subscription.cancel();
    channel.sink.close();
  }

  Channel createChannel(String name) => Channel._(this, name);

  void _onMessage(String serializedMessage) async {
    var message = Message.decode(serializedMessage);

    try {
      var channel = _channels.firstWhere((d) => d.name == message.channel,
          orElse: () =>
              throw Exception('Channel ${message.channel} not found'));
      await channel._onMessage(message);
    } catch (e, stackTrace) {
      if (message.type == MessageType.request) {
        sendMessage(_createError(message, e));
      } else {
        print('Connection error $e\n$stackTrace');
        rethrow;
      }
    }
  }

  void sendMessage(Message message) {
    channel.sink.add(Message.encode(message));
  }

  void _addChannel(Channel channel) {
    _channels.add(channel);
  }

  String _serializeParameter(parameter) {
    if (parameter == null) {
      return '';
    } else {
      return jsonEncode(parameterSerializers.serialize(parameter));
    }
  }

  Object? _deserializeParameter(String encodeParameter) {
    if (encodeParameter == '') {
      return null;
    }
    return parameterSerializers.deserialize(jsonDecode(encodeParameter));
  }

  Message _createRequest(String channel, String method,
      [parameter1, parameter2, parameter3]) {
    return Message((b) => b
      ..channel = channel
      ..method = method
      ..id = ++_messageId
      ..type = MessageType.request
      ..serializedParameter1 = _serializeParameter(parameter1)
      ..serializedParameter2 = _serializeParameter(parameter2)
      ..serializedParameter3 = _serializeParameter(parameter3));
  }

  Message _createResponse(Message request, parameter) {
    return Message((b) => b
      ..channel = request.channel
      ..method = request.method
      ..id = request.id
      ..type = MessageType.response
      ..serializedParameter1 = _serializeParameter(parameter));
  }

  Message _createError(Message request, exception) {
    return Message((b) => b
      ..channel = request.channel
      ..method = request.method
      ..id = request.id
      ..type = MessageType.error
      ..serializedParameter1 = _serializeParameter(exception.toString()));
  }
}

class Channel {
  final Connection connection;
  final String name;
  final Map<String, Function> _methods = {};
  final Map<Message, Completer> _pendingRequests = {};

  Channel._(this.connection, this.name) {
    connection._addChannel(this);
  }

  void close() {
    for (var pendingRequest in _pendingRequests.values) {
      pendingRequest.completeError('Connection is closed');
    }
  }

  void registerMethod(String methodName, Function callback) {
    if (callback is Function(Never, Never, Never) ||
        callback is Function(Never, Never) ||
        callback is Function(Never) ||
        callback is Function()) {
      _methods[methodName] = callback;
    } else {
      throw Exception('Method must have maximum 3 parameters');
    }
  }

  Future<T> sendRequest<T>(String methodName,
      [parameter1, parameter2, parameter3]) {
    var message = connection._createRequest(
        name, methodName, parameter1, parameter2, parameter3);
    var completer = Completer();
    _pendingRequests[message] = completer;
    connection.sendMessage(message);

    return completer.future.then((value) => value as T);
  }

  Object? _deserialize(String parameter) =>
      connection._deserializeParameter(parameter);

  Future<void> _onMessage(Message message) async {
    if (message.type == MessageType.request) {
      var method = _methods[message.method];
      if (method == null) {
        throw Exception('Method not found ${message.method}');
      }

      dynamic response;
      if (method is Function(Never, Never, Never)) {
        var parameter1 = _deserialize(message.serializedParameter1);
        var parameter2 = _deserialize(message.serializedParameter2!);
        var parameter3 = _deserialize(message.serializedParameter3!);
        response = Function.apply(method, [parameter1, parameter2, parameter3]);
      } else if (method is Function(Never, Never)) {
        var parameter1 = _deserialize(message.serializedParameter1);
        var parameter2 = _deserialize(message.serializedParameter2!);
        response = Function.apply(method, [parameter1, parameter2]);
      } else if (method is Function(Never)) {
        var parameter = _deserialize(message.serializedParameter1);
        response = Function.apply(method, [parameter]);
      } else if (method is Function()) {
        response = await method();
      } else {
        throw Exception('Function with wrong number of args: $method');
      }

      connection.sendMessage(connection._createResponse(message, response));
    } else {
      var request =
          _pendingRequests.keys.firstWhereOrNull((m) => m.id == message.id);

      var completer = _pendingRequests.remove(request)!;

      var parameter = _deserialize(message.serializedParameter1);

      if (message.type == MessageType.error) {
        completer.completeError(parameter!);
      } else {
        completer.complete(parameter);
      }
    }
  }
}
