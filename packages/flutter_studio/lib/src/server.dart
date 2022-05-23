import 'dart:async';
import 'dart:io';
import 'package:flutter_studio/src/test/session/session.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final _logger = Logger('server');

class Server {
  late HttpServer _server;
  final _sessions = <Session>[];

  Server._();

  static Future<Server> start({int? port}) async {
    var server = Server._();
    await server._init(port: port);
    return server;
  }

  Uri get uri => Uri(scheme: 'ws', host: 'localhost:${_server.port}');

  Future<void> _init({int? port}) async {
    port ??= 0;

    var router = Router();
    router.get('/socket', _socketHandler);

    _server = await io.serve(router, InternetAddress.anyIPv4, port);
    _server.defaultResponseHeaders.set('Access-Control-Allow-Origin', '*');

    var message = 'Flutter Studio: ${'http'}://${_server.address.address}:${_server.port}';
    _logger.info('${'='*message.length}\n$message\n${'='*message.length}');
  }

  FutureOr<Response> _socketHandler(Request request) {
    return webSocketHandler(
        (WebSocketChannel channel) => _onConnect(request, channel))(request);
  }

  void _onConnect(Request request, WebSocketChannel rawChannel) async {
    var channel = rawChannel.cast<String>();
    late Session session;
     session = Session(channel, onClose: () {
      _sessions.remove(session);
    });
    _sessions.add(session);
  }

  void dispose() {
    _server.close();
  }
}
