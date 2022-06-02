import '../connection.dart';
import '../models.dart';

class ProjectClient {
  final Channel _channel;

  ProjectClient(Connection connection, {required ProjectInfo Function() load})
      : _channel = connection.createChannel('Project') {
    _channel.registerMethod('load', load);
  }

  void notifyReloaded() {
    _channel.sendRequest('onReloaded');
  }
}
