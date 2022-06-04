import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_studio_app/src/test_runner/entry_point.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:path/path.dart' as p;
import '../project.dart';
import '../utils/flutter_run_process.dart';
import 'protocol/api.dart';
import 'server.dart';

final _logger = Logger('test_runner_service');

class TestService {
  final Project project;
  final _state = ValueNotifier<DaemonState>(DaemonState$Initial());
  final Directory _projectRoot;
  final File _entryPoint;
  late Server _server;

  TestService(this.project)
      : _projectRoot = Directory(project.directory),
        _entryPoint = File(p.join(project.directory, 'build', 'flutter_studio', 'test_entry_point.dart')) {
    _entryPoint.parent.createSync(recursive: true);
  }

  ValueListenable<DaemonState> get state => _state;

  void ensureStarted() {
    if (_state.value is DaemonState$Initial) {
      start();
    }
  }

  Future<void> _writeEntryPoint() async {
    var testFiles = collectTestFiles(_projectRoot);
    var code = entryPointCode(testFiles, _server.socketUri);
    await _entryPoint.writeAsString(code);
  }

  void start() async {
    assert(_state.value is DaemonState$Initial ||
        _state.value is DaemonState$Stopped);
    _state.value = DaemonState$Starting('');

    _server = await Server.start();
    await _writeEntryPoint();

    try {
      var daemon = await FlutterRunProcess.start(_projectRoot,
          target: p.relative(_entryPoint.path, from: _projectRoot.path),
          device: 'flutter-tester',
          flutterSdk: project.flutterSdkPath);
      _state.value = DaemonState$Connected(daemon);
    } catch (e, s) {
      _logger.severe('Fail to start flutter run -d flutter-tester', e, s);
      _state.value = DaemonState$Stopped(error: e);
    }
  }

  void stop() {
    _server.dispose();

    var stateValue = _state.value;
    if (stateValue is! DaemonState$Connected) {
      throw Exception('Only started daemon can be stopped');
    }
    stateValue.daemon.stop();
    _state.value = DaemonState$Stopped();
  }
}

class DaemonState {}

class DaemonState$Initial implements DaemonState {}

class DaemonState$Starting implements DaemonState {
  final String logs;

  DaemonState$Starting(this.logs);
}

class DaemonState$Stopped implements DaemonState {
  final Object? error;

  DaemonState$Stopped({this.error});
}

class DaemonState$Connected implements DaemonState {
  final FlutterRunProcess daemon;

  DaemonState$Connected(this.daemon);
}
