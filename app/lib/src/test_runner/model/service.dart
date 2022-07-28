import 'dart:async';
import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';
import 'package:watcher/watcher.dart';
import '../../project.dart';
import '../protocol/api.dart';
import 'daemon.dart';
import 'server.dart';

final _logger = Logger('test_runner_service');

class WatchConfig {
  static final defaultFolders = <String>{'lib', 'test_app'};
  final Set<String> folders;

  WatchConfig(this.folders);

  WatchConfig toggleFolder(String folder) {
    var newFolders = folders.toSet();
    if (newFolders.contains(folder)) {
      newFolders.remove(folder);
    } else {
      newFolders.add(folder);
    }
    return WatchConfig(newFolders);
  }

  bool contains(String folder) => folders.contains(folder);
}

class TestService {
  final Project project;
  final _state = ValueNotifier<DaemonState>(DaemonState$Stopped());

  // TODO(xha): load config from config file
  final _watchConfig =
      ValueNotifier<WatchConfig>(WatchConfig(WatchConfig.defaultFolders));
  final _server = Server();
  StreamSubscription? _fileWatcherSubscription;
  final _messageController = StreamController<DaemonMessage>.broadcast();

  TestService(this.project);

  ValueListenable<DaemonState> get state => _state;

  ValueListenable<WatchConfig> get watchConfig => _watchConfig;

  ValueStream<List<TestRunnerApi>> get clients => _server.clients;

  Stream<DaemonMessage> get daemonMessage => _messageController.stream;

  bool get isStarted => _server.isStarted;

  void start() async {
    if (!_server.isStarted) {
      await _server.start();
    }

    _state.value = DaemonState$Starting('');

    var daemonStarter =
        DaemonStarter(project, _server, _messageController.sink);
    try {
      var daemon = await daemonStarter.start();
      _state.value = DaemonState$Connected(daemon);
      await daemon.reload(fullRestart: false);
      _updateWatcher();
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

  void updateWatchConfig(WatchConfig config) {
    _watchConfig.value = config;
    _updateWatcher();
  }

  void _updateWatcher() {
    _fileWatcherSubscription?.cancel();
    var config = _watchConfig.value;

    _fileWatcherSubscription = StreamGroup.merge([
      for (var config in config.folders)
        DirectoryWatcher(p.join(project.directory.path, config)).events,
    ]).throttleTime(Duration(seconds: 1)).listen((e) {
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
    _messageController.close();
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
