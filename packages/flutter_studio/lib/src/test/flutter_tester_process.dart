import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';

final _logger = Logger('flutter_tester_process');

const _toolStartedSignal =
    'The Flutter DevTools debugger and profiler on Flutter test device is available at';

class FlutterTesterProcess {
  final Process _process;
  final _onStartedCompleter = Completer<void>();

  FlutterTesterProcess._(this._process) {
    _process.stdout
        .transform(Utf8Decoder())
        .transform(const LineSplitter())
        .listen((line) {
      if (line.startsWith(_toolStartedSignal) &&
          !_onStartedCompleter.isCompleted) {
        _onStartedCompleter.complete();
      }

      _logger.fine(line);
    });
    _process.stderr
        .transform(Utf8Decoder())
        .transform(const LineSplitter())
        .listen((line) {
      _logger.warning(line);
    });
  }

  static Future<FlutterTesterProcess> start(Directory directory) async {
    //TODO(xha): use flutter from the same place Platform.resolvedExecutable
    var process = await Process.start(
        'flutter', ['run', '-d', 'flutter-tester'],
        workingDirectory: directory.path);
    return FlutterTesterProcess._(process);
  }

  Future<void> get onStarted => _onStartedCompleter.future;
  Future<void> get onExit => _process.exitCode;

  Future<void> reload() async {
    _process.stdin.write('r');
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<void> restart() async {
    _process.stdin.write('R');
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<void> quit() async {
    _process.stdin.write('q');
    return onExit;
  }
}
