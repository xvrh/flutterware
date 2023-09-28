import 'dart:io';
import 'dart:math';

import 'package:flutterware_app/src/project.dart';
import 'package:flutterware_app/src/ui_book/service/server.dart';
import 'package:flutterware_app/src/utils/daemon/protocol.dart';
import 'package:flutterware_app/src/utils/flutter_run_process.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:path/path.dart' as p;

import '../../utils/connection.dart';

final _logger = Logger('ui_book_service');

class UIBookService {
  static const _mainSuffix = 'ui_book.dart';

  final Project project;
  final _devices = BehaviorSubject<List<PreviewDevice>>.seeded([]);
  final _availableMains = BehaviorSubject<List<String>>.seeded([]);
  final _selectedMain = BehaviorSubject<String>.seeded('');
  final String _entryPointPath;
  Server? _server;

  UIBookService(this.project)
      : _entryPointPath = p.join('build', 'flutterware',
            'ui_book_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}.dart');

  Stream<PreviewDevice?> get mainDevice => _devices.map((e) => e.firstOrNull);

  void start() async {
    _server = await Server.start(
        onAdd: _onAddConnection, onRemove: _onRemoveConnection);

    _refreshMainFiles();
    _logger.info('Path: $_entryPointPath');
    _writeEntryPoint();

    // Create entryPoint immediately
    // Update entry point when selected main file change and hotRestart devices
    //

    startDevice('flutter-tester');

    // - Start server
    // - Create entry point with server port
    // - flutter run
    // - Wait for device to connect
    // -
  }

  void _writeEntryPoint() {
    var code = StringBuffer();
    code.writeln('''
// GENERATED-CODE: Flutterware - UIBook feature
import 'package:flutterware/src/ui_book/app_integration.dart';
import '../../${_selectedMain.value}' as user_code;

void main() {
  setupAppIntegration(serverPort: ${_server!.port});
  user_code.main();
}
''');

    File(p.join(project.directory.path, _entryPointPath))
      ..createSync(recursive: true)
      ..writeAsStringSync('$code');
  }

  void _onAddConnection(Connection connection) {}
  void _onRemoveConnection(Connection connection) {}

  void startDevice(String deviceId, {String? flavor}) {
    var device = PreviewDevice(project, deviceId);
    _devices.value.add(device);
    _devices.add(_devices.value);

    device.start(_entryPointPath);
    // flutter run
    // Get daemon protocol
    // Listen for events
  }

  void hotReload() {}

  void hotRestart() {}

  void stop() {}

  void _refreshMainFiles() {
    var mains = _listMains();
    if (mains.isEmpty) {
      mains = [_createSampleFile()];
    }
    _availableMains.value = mains;
    var currentMain = _selectedMain.value;
    if (!mains.contains(currentMain)) {
      _selectedMain.value = _availableMains.value.first;
    }
  }

  List<String> _listMains() {
    var files = <String>[];
    // TODO: only list files that are in non-excluded directories? (use gitignore?)
    for (var file in project.directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((e) => e.path.endsWith(_mainSuffix))) {
      // TODO: check that there is a main() function
      files.add(p.relative(file.path, from: project.directory.path));
    }
    //TODO: sort

    return files;
  }

  String _createSampleFile() {
    var sampleContent = File(p.join(project.context.appToolDirectory.path,
            'lib/src/ui_book/service/ui_book_sample.dart'))
        .readAsStringSync();
    var sample = File(p.join(project.directory.path, 'examples/ui_book.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(sampleContent);
    return sample.path;
  }

  void dispose() {
    _devices.close();
    _selectedMain.close();
    _availableMains.close();
  }
}

class PreviewDevice {
  final Project project;
  final _state = BehaviorSubject<DeviceState>.seeded(InProgressState());
  final String id;
  FlutterRunProcess? _process;
  Connection? connection;

  PreviewDevice(this.project, this.id) {
    // daemon.onEvent.listen((e) {});
  }

  void start(String entrypoint) async {
    var process = _process = await FlutterRunProcess.start(project.directory,
        target: entrypoint,
        device: 'flutter-tester',
        flutterSdk: project.flutterSdkPath);
    process.onLog.listen((event) {
      _logger.info('Log ${event.log}');
    });
    process.onLogMessage.listen((event) {
      _logger.info('LogMessage ${event.message}');
    });
    _updateState();
  }

  void _updateState() {}

  void updateConnection(Connection connection) {}

  void stop() {
    _process?.stop();
    _state.close();
  }
}

sealed class DeviceState {}

class ReadyState extends DeviceState {
  final DaemonProtocol daemon;
  final Connection? connection;

  ReadyState(this.daemon, this.connection);

  void hotReload() {}

  void hotRestart() {}
}

class InProgressState extends DeviceState {}
