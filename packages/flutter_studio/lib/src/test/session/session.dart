import 'package:flutter_studio/src/test/flutter_run_process.dart';
import 'package:flutter_studio/src/test/session/model.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:stream_channel/stream_channel.dart';

import '../protocol/connection.dart';

class Session {
  final String id;
  final Connection _uiConnection;
  StreamChannel<String> _runnerChannel;
  FlutterRunProcess? _runProcess;

  Session(StreamChannel<String> uiChannel, {required void Function() onClose})
      : _uiConnection = Connection(uiChannel, serializers) {
    _uiConnection.listen(onClose: () {
      onClose();
      _runProcess?.stop();
    });
    // Protocol bi-directional (RPC + events?) between the UI & the server
    // It will make the bridge between the flutter run process

    //

    // 1. Get run process state
    // 2. Start run process
    // 3. Stop run process
    // 4. Send to run process (opaque)
    // 5.
  }

  // Web app connect to server
  //  The session to the Server will hold the reference to the flutter-run
  //    Need to track the progress, the error and the restart

  // 1. Setup communication app vs session
  //   App has method to register to state of runner
  //   Can start runner
  //   Can stop runner

  // 1. Get an id
  // 2. Create a build folder
  // 3. Create the entry point (by listing the _test files)
  // 4. Start the flutter run
  // 5. Wait for the run to complete
  // 6. flutter run entry point:
  //     - connect back to server
  Directory get buildFolder;
}

class SessionHost {
  final Channel _channel;

  SessionHost(Connection connection): _channel = connection.createChannel('session') {
    _channel.registerMethod('start', _start);
    _channel.registerMethod('stop', _stop);
  }

  Future<void> _start() async {}

  Future<void> _stop() async {}
}
