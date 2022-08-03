import '../runtime.dart';
import 'package:stream_channel/stream_channel.dart';
import 'listing.dart';
import 'project.dart';
import 'run.dart';

class TestRunnerApi {
  final Connection _connection;
  late final ListingHost _listing;
  late final ProjectHost _project;
  late final RunHost _runHost;

  TestRunnerApi(StreamChannel<String> channel,
      {required void Function() onClose})
      : _connection = Connection(channel, modelSerializers) {
    _connection.listen(onClose: () {
      onClose();

      _listing.dispose();
      _project.dispose();
      _runHost.dispose();
    });

    _listing = ListingHost(_connection);
    _project = ProjectHost(_connection);
    _runHost = RunHost(_connection);
  }

  void close() => _connection.close();

  ListingHost get listing => _listing;
  ProjectHost get project => _project;
  RunHost get run => _runHost;
}
