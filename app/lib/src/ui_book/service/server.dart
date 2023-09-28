import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf;
import 'package:shelf_web_socket/shelf_web_socket.dart' as shelf;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'models.dart';

import '../../utils/connection.dart';
import 'udp_discovery.dart';

class Server {
  final HttpServer _server;
  final UdpDiscovery _udpDiscovery;

  Server(this._server, this._udpDiscovery);

  static Future<Server> start(
      {required void Function(Connection) onRemove,
      required void Function(Connection) onAdd}) async {
    var server =
        await shelf.serve(shelf.webSocketHandler((WebSocketChannel channel) {
      late Connection connection;
      connection = Connection(channel.cast<String>(), modelSerializers)
        ..listen(onClose: () {
          onRemove(connection);
        });
      onAdd(connection);
    }), InternetAddress.anyIPv4, 0);

    var udpDiscovery = await UdpDiscovery.start();

    return Server(server, udpDiscovery);
  }

  int get port => _server.port;

  void close() {
    _server.close();
    _udpDiscovery.stop();
  }
}
