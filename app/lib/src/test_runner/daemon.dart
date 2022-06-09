import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import '../flutter_sdk.dart';
import '../globals.dart';
import '../project.dart';
import '../utils/daemon/commands.dart';
import '../utils/daemon/events.dart';
import '../utils/daemon/protocol.dart';
import 'entry_point.dart';
import 'protocol/api.dart';
import 'server.dart';
import 'package:path/path.dart' as p;

import 'service.dart';

final _logger = Logger('Test daemon');

class Daemon {
  final DaemonStarter _starter;
  final Process _process;
  final DaemonProtocol _protocol;
  final String _appId;
  late StreamSubscription _eventSubscription;
  final _isReloading = ValueNotifier<bool>(false);

  Daemon(this._starter, this._process, this._protocol, this._appId) {
    _eventSubscription = _protocol.onEvent.listen((event) {
      //TODO(xha): dispatch messages etc...
      print("Event ${event.runtimeType}");
    });
  }

  Project get _project => _starter.project;

  ValueListenable<bool> get isReloading => _isReloading;

  Future<void> reload({required bool fullRestart}) async {
    _isReloading.value = true;
    var testFiles = collectTestFiles(Directory(_project.directory));
    await _starter.writeEntryPoint(testFiles);
    var endOfReload = _protocol.onEvent
        .where((e) =>
            e is AppProgressEvent &&
            e.appId == _appId &&
            e.progressId == (fullRestart ? 'hot.restart' : 'hot.reload') &&
            e.finished)
        .first;
    await _protocol.sendCommand(
        AppRestartCommand(appId: _appId, fullRestart: fullRestart));
    print("Will wait for reload");
    await endOfReload;
    print("End of reload");
    _isReloading.value = false;
  }

  Future<void> stop() async {
    await _protocol.sendCommand(AppStopCommand(appId: _appId));
    return onExit;
  }

  Future<void> get onExit => _process.exitCode;

  void dispose() {
    _eventSubscription.cancel();
  }
}

class DaemonStarter {
  final id =
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';
  final Project project;
  final Server server;
  late final File _entryPoint;

  DaemonStarter(this.project, this.server) {
    _entryPoint = File(p.join(project.directory, 'build', 'flutter_studio',
        '${id}_test_entry_point.dart'))
      ..parent.createSync(recursive: true);
  }

  Future<void> writeEntryPoint(List<TestFile> testFiles) async {
    var code = entryPointCode(project, testFiles, server.socketUri!);
    await _entryPoint.writeAsString(code);
  }

  Future<Daemon> start() async {
    await _buildBundle();
    await writeEntryPoint([]);
    var process = await Process.start(
        project.flutterSdkPath.flutter,
        [
          'run',
          '--machine',
          '--target',
          p.relative(_entryPoint.path, from: project.directory),
          '--device-id',
          'flutter-tester'
        ],
        workingDirectory: project.directory);
    await globals.resourceCleaner.killProcessOnNextLaunch(process.pid);
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
        return Daemon(this, process, protocol, event.appId);
      }
    }
    throw Exception('Failed to start daemon');
  }

  Future<void> _buildBundle() async {
    var emptyFile = File('build/__empty_${id}__.dart')
      ..createSync()
      ..writeAsStringSync('void main() {}');

    try {
      var result = await Process.run(project.flutterSdkPath.flutter,
          ['build', 'bundle', '--release', emptyFile.path]);
      if (result.exitCode != 0) {
        throw Exception('Failed to build bundle ${result.stderr}');
      }
    } finally {
      emptyFile.deleteSync();
    }
  }
}
