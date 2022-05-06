import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';

final _logger = Logger('flutter_tester_process');

class FlutterTesterProcess {
  final Process _process;

  FlutterTesterProcess._(this._process) {
    _process.stdout
        .transform(Utf8Decoder())
        .transform(const LineSplitter())
        .listen((line) {
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
}
