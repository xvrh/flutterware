import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterware_app/src/test_runner/model/daemon.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';
import 'package:watcher/watcher.dart';
import '../../project.dart';
import '../protocol/api.dart';
import 'server.dart';
import 'package:async/async.dart';

final _logger = Logger('test_runner_service');

class TestService {
  final Project project;
  final _state = ValueNotifier<DaemonState>(DaemonState$Stopped());
  final _server = Server();
  StreamSubscription? _fileWatcherSubscription;

  TestService(this.project);

  ValueListenable<DaemonState> get state => _state;

  ValueStream<List<TestRunnerApi>> get clients => _server.clients;

  bool get isStarted => _server.isStarted;

  void ensureStarted() {
    if (!isStarted) {
      start();
    }
  }

  void start() async {
    if (!_server.isStarted) {
      await _server.start();
    }

    _state.value = DaemonState$Starting('');

    var daemonStarter = DaemonStarter(project, _server);
    try {
      var daemon = await daemonStarter.start();
      _state.value = DaemonState$Connected(daemon);
      await daemon.reload(fullRestart: false);
      _setupWatcher();
      _logger.info('Test runner started');
      await daemon.onExit;
      _state.value = DaemonState$Stopped();
      _disposeWatcher();
      _logger.info('Test runner stopped');
    } catch (e, s) {
      _logger.severe('Failed to start test daemon: $e', e, s);
      _state.value = DaemonState$Stopped(error: e);
    }
  }

  void _setupWatcher() {
    print("Setup watcher");
    _fileWatcherSubscription = StreamGroup.merge([
      DirectoryWatcher(p.join(project.directory.path, 'lib')).events,
      DirectoryWatcher(p.join(project.directory.path, 'test_app')).events,
    ]).throttleTime(Duration(seconds: 1)).listen((e) {
      print("File change $e");
      var stateValue = _state.value;
      if (stateValue is DaemonState$Connected) {
        stateValue.daemon.reload(fullRestart: false);
      }
    });
  }

  void _disposeWatcher() {
    _fileWatcherSubscription?.cancel();
    _fileWatcherSubscription = null;
  }

  void stop() {
    var stateValue = _state.value;
    if (stateValue is! DaemonState$Connected) {
      throw Exception('Only started daemon can be stopped');
    }
    stateValue.daemon.stop();
  }

  void dispose() {
    _disposeWatcher();
    _state.dispose();
    if (_server.isStarted) {
      _server.close();
    }
  }
}

class DaemonState {}

class DaemonState$Starting implements DaemonState {
  final String logs;

  DaemonState$Starting(this.logs);
}

class DaemonState$Stopped implements DaemonState {
  final Object? error;

  DaemonState$Stopped({this.error});
}

class DaemonState$Connected implements DaemonState {
  final Daemon daemon;

  DaemonState$Connected(this.daemon);
}
