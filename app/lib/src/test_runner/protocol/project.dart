import 'dart:async';
import 'package:flutterware/internals/test_runner.dart';

class ProjectHost {
  final Channel _channel;
  final _onReloadedController = StreamController<void>.broadcast();

  ProjectHost(Connection connection)
      : _channel = connection.createChannel('Project') {
    _channel.registerMethod('onReloaded', _onReloaded);
  }

  Stream<void> get onReloaded => _onReloadedController.stream;

  void _onReloaded() {
    _onReloadedController.add(null);
  }

  void dispose() {
    _onReloadedController.close();
  }
}
