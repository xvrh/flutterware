import '../../../utils/connection/connection.dart';

class ProjectClient {
  final Channel _channel;

  ProjectClient(Connection connection)
      : _channel = connection.createChannel('Project');

  void notifyReloaded() {
    _channel.sendRequest('onReloaded');
  }
}
