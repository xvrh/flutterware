import 'dart:async';
import 'dart:io';
import 'package:rxdart/rxdart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/api.dart';

class Server {
  late HttpServer _server;
  bool _isStarted = false;
  final _clients = BehaviorSubject<List<TestRunnerApi>>.seeded([]);

  Uri? get socketUri {
    if (_isStarted) {
      return Uri(
          scheme: 'ws',
          host: Platform.isWindows ? 'localhost' : _server.address.host,
          port: _server.port,
          path: 'socket');
    }
    return null;
  }

  bool get isStarted => _isStarted;

  Future<void> start({int? port}) async {
    if (_isStarted) return;
    _isStarted = true;
    port ??= 0;

    var router = Router();
    router.get('/socket', _socketHandler);

    _server = await io.serve(router.call, InternetAddress.anyIPv4, port);
    _server.defaultResponseHeaders.set('Access-Control-Allow-Origin', '*');

    print('Server started ws://${_server.address.host}:${_server.port}');
  }

  FutureOr<Response> _socketHandler(Request request) {
    return webSocketHandler(
        (channel, _) => _onConnect(request, channel))(request);
  }

  void _onConnect(Request request, WebSocketChannel channel) async {
    late TestRunnerApi client;
    client = TestRunnerApi(channel.cast<String>(), onClose: () {
      _clients.add(_clients.value..remove(client));
    });

    _clients.add(_clients.value..add(client));
  }

  ValueStream<List<TestRunnerApi>> get clients => _clients;

  void close() {
    _clients.close();
    if (_isStarted) {
      _server.close();
    }
  }
}
