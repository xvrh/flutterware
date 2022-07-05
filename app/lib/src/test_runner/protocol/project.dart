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

  Future<ProjectInfo> loadInfo() async {
    return await _channel.sendRequest<ProjectInfo>('load');
  }

  void _onReloaded() {
    _onReloadedController.add(null);
  }

  void dispose() {
    _onReloadedController.close();
  }
}
