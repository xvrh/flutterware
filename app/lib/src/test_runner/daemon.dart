import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../flutter_sdk.dart';
import '../utils/daemon/commands.dart';
import '../utils/daemon/events.dart';
import '../utils/daemon/protocol.dart';
import 'protocol/api.dart';
import 'server.dart';

class Daemon {
  TestRunnerApi _client;

  Daemon._(this._client);

  static Future<Daemon> start({int? port}) async* {
    var server = await Server.start();

    // 1. Start daemon
    // 2. Wait for server connection && AppStarted
    // 3. If onExit, close server and emit Daemon error
    //    Expose Stream<DaemonEvent> as protocol for upper communication
    // 4. Manage entry point code (with collect files)
    // 5. Save pid in file to delete on App hot restart

    // New start:
    //  - Solidify: daemon, entry point & server
    //  - Create strong UI against the state: stop, hot restart, hot reload, watch directories
    //  -
  }

  void reload({required bool fullRestart}) {
    // Write new end point
    // reload
    // Events will come from the Stream
  }

  void forceStop() {
    // Stop the server to stop, kill the flutter run, end the stream
  }

  void dispose() {
    _client.dispose();
  }
}

class FlutterRunProcess {
  final Process _process;
  final DaemonProtocol _protocol;
  final String appId;

  FlutterRunProcess._(this._process, this._protocol, this.appId);

  static Future<FlutterRunProcess> start(
    Directory directory, {
    required String target,
    required String device,
    required FlutterSdkPath flutterSdk,
  }) async {
    var process = await Process.start(flutterSdk.flutter,
        ['run', '--machine', '--target', target, '--device-id', device],
        workingDirectory: directory.path, environment: {});
    var protocol = DaemonProtocol(
        process.stdin,
        process.stdout
            .transform(Utf8Decoder())
            .transform(const LineSplitter()));
    process.stderr
        .transform(Utf8Decoder())
        .transform(const LineSplitter())
        .listen(_logger.warning);

    await for (var event in protocol.onEvent) {
      if (event is AppStartedEvent) {
        return FlutterRunProcess._(process, protocol, event.appId);
      }
    }
    throw Exception('Failed to run flutter app');
  }

  Future<void> reload({required bool fullRestart}) async {
    await _protocol
        .sendCommand(AppRestartCommand(appId: appId, fullRestart: fullRestart));
  }

  Future<void> stop() async {
    await _protocol.sendCommand(AppStopCommand(appId: appId));
    return onExit;
  }

  Future<void> get onExit => _process.exitCode;
}
