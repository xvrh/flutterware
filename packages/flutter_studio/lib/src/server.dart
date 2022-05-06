import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class Server {
  late HttpServer _server;

  Server._();

  static Future<Server> start({int? port}) async {
    var server = Server._();
    await server._init(port: port);
    return server;
  }

  Future<void> _init({int? port}) async {
    port ??= 0;

    var router = Router();
    router.get('/socket', _socketHandler);

    _server = await io.serve(router, InternetAddress.anyIPv4, port);
    _server.defaultResponseHeaders.set('Access-Control-Allow-Origin', '*');

    print('Server started ws://${_server.address.host}:${_server.port}');
  }

  FutureOr<Response> _socketHandler(Request request) {
    return webSocketHandler(
        (WebSocketChannel channel) => _onConnect(request, channel))(request);
  }

  void _onConnect(Request request, WebSocketChannel channel) async {}

  void dispose() {}
}
