import 'dart:async';
import 'dart:io';
import 'package:rxdart/rxdart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'protocol/api.dart';

class Server {
  late HttpServer _server;
  final _clients = BehaviorSubject<List<TestRunnerApi>>.seeded([]);

  Server._();

  static Future<Server> start({int? port}) async {
    var server = Server._();
    await server._init(port: port);
    return server;
  }

  Uri get socketUri => Uri(
      scheme: 'ws',
      host: '${_server.address.host}:${_server.port}',
      path: 'socket');

  Future<void> _init({int? port}) async {
    port ??= 0;

    var router = Router();
    router.get('/socket', _scenarioSocketHandler);

    _server = await io.serve(router, InternetAddress.anyIPv4, port);
    _server.defaultResponseHeaders.set('Access-Control-Allow-Origin', '*');

    print('Server started ws://${_server.address.host}:${_server.port}');
  }

  FutureOr<Response> _scenarioSocketHandler(Request request) {
    return webSocketHandler((WebSocketChannel channel) =>
        _onScenarioConnect(request, channel))(request);
  }

  void _onScenarioConnect(Request request, WebSocketChannel channel) async {
    late TestRunnerApi client;
    client = TestRunnerApi(channel.cast<String>(), onClose: () {
      _clients.add(_clients.value..remove(client));
    });

    _clients.add(_clients.value..add(client));
  }

  ValueStream<List<TestRunnerApi>> get clients => _clients;

  void dispose() {
    _clients.close();
  }
}
