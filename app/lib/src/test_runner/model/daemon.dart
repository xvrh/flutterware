import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import '../../globals.dart';
import '../../project.dart';
import '../../utils/daemon/commands.dart';
import '../../utils/daemon/events.dart';
import '../../utils/daemon/protocol.dart';
import '../entry_point.dart';
import 'server.dart';
import 'package:path/path.dart' as p;
export '../../utils/daemon/events.dart' show MessageLevel;

final _logger = Logger('Test daemon');

class DaemonMessage {
  final String message;
  final MessageLevel type;

  DaemonMessage(this.message, this.type);
}

class Daemon {
  final DaemonStarter _starter;
  final Process _process;
  final DaemonProtocol _protocol;
  final String _appId;
  late StreamSubscription _eventSubscription;
  final _isReloading = ValueNotifier<bool>(false);
  final _progressMessage = ValueNotifier<String?>(null);
  String? _currentProgressMessageId;

  Daemon(this._starter, this._process, this._protocol, this._appId) {
    _eventSubscription = _protocol.onEvent.listen((event) {
      if (event is AppProgressEvent) {
        var message = event.message;
        if (message != null) {
          _clearProgressTimer?.cancel();
          _currentProgressMessageId = event.id;
          _progressMessage.value = message;
        } else if (event.id == _currentProgressMessageId) {
          _progressMessage.value = null;
        }
      } else if (event is DaemonLogEvent) {
        _showMessage(
            event.log, event.error ? MessageLevel.error : MessageLevel.info);
      } else if (event is DaemonLogMessageEvent) {
        _showMessage(event.message, event.level);
      }
    });
  }

  Timer? _clearProgressTimer;
  void _setProgressMessage(String message, Duration duration) {
    _clearProgressTimer?.cancel();
    _currentProgressMessageId = null;
    _progressMessage.value = message;
    _clearProgressTimer = Timer(duration, () {
      _progressMessage.value = null;
    });
  }

  void _showMessage(String message, MessageLevel level) {
    _starter.messageSink.add(DaemonMessage(message, level));
  }

  Project get _project => _starter.project;

  ValueListenable<bool> get isReloading => _isReloading;

  ValueListenable<String?> get progressMessage => _progressMessage;

  Future<void> reload({required bool fullRestart}) async {
    _isReloading.value = true;
    var testFiles = collectTestFiles(_project.directory);
    await _starter.writeEntryPoint(testFiles);
    var endOfReload = _protocol.onEvent
        .where((e) =>
            e is AppProgressEvent &&
            e.appId == _appId &&
            e.progressId == (fullRestart ? 'hot.restart' : 'hot.reload') &&
            e.finished)
        .first;
    var endResult = await _protocol.sendCommand(
        AppRestartCommand(appId: _appId, fullRestart: fullRestart));
    await endOfReload;
    _isReloading.value = false;
    _setProgressMessage(endResult.message, Duration(seconds: 2));
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
  final Sink<DaemonMessage> messageSink;
  late final File _entryPoint;

  DaemonStarter(this.project, this.server, this.messageSink) {
    _entryPoint = File(p.join(project.directory.path, 'build', 'flutterware',
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
          p.relative(_entryPoint.path, from: project.directory.path),
          '--device-id',
          'flutter-tester'
        ],
        workingDirectory: project.directory.path);
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
