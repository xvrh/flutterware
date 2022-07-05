import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutterware_app/src/flutter_sdk.dart';

import 'daemon/commands.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'daemon/events.dart';
import 'daemon/protocol.dart';

final _logger = Logger('flutter_daemon_process');

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
