import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../src/logs/remote_log.dart';

abstract class LogClient {
  factory LogClient.print() => _PrintLogClient();

  void printBox(String message, {String? title});
  void printError(String message, {StackTrace? stackTrace});
  void printWarning(String message);
  void printStatus(String message);
  void printTrace(String message);
  ProgressStatus startProgress(String? message);
}

class _PrintLogClient implements LogClient {
  @override
  void printBox(String message, {String? title}) {
    print('[$message - $title]');
  }

  @override
  void printError(String message, {StackTrace? stackTrace}) {
    print('[ERROR] $message\n$stackTrace');
  }

  @override
  void printStatus(String message) {
    print('[STATUS] $message');
  }

  @override
  void printTrace(String message) {
    print('[TRACE] $message');
  }

  @override
  void printWarning(String message) {
    print('[WARNING] $message');
  }

  @override
  ProgressStatus startProgress(String? message) {
    return _EmptyProgress();
  }
}

abstract class ProgressStatus {
  void stop();
}

class _EmptyProgress implements ProgressStatus {
  @override
  void stop() {
    // TODO: implement stop
  }
}

class RemoteLogClient implements LogClient {
  final Uri uri;
  Future? _previousRequest;

  RemoteLogClient(this.uri);

  @override
  void printBox(String message, {String? title}) {
    _send(RemoteLogServer.printBoxPath, PrintBox(message, title));
  }

  @override
  void printError(String message, {StackTrace? stackTrace}) {
    _send(RemoteLogServer.printLogPath,
        PrintLog.error(message, stackTrace: stackTrace?.toString()));
  }

  @override
  void printWarning(String message) {
    _sendLog(PrintType.warning, message);
  }

  @override
  void printStatus(String message) {
    _sendLog(PrintType.status, message);
  }

  @override
  void printTrace(String message) {
    _sendLog(PrintType.trace, message);
  }

  @override
  ProgressStatus startProgress(String? message) {
    var status = _RemoteStatus._(this);
    _send(RemoteLogServer.startProgressPath, StartProgress(status.id, message));
    return status;
  }

  void _stopProgress(int id) {
    _send(RemoteLogServer.stopProgressPath, StopProgress(id));
  }

  void _sendLog(PrintType type, String message) {
    _send(RemoteLogServer.printLogPath, PrintLog(type, message));
  }

  Future<void> _send(String path, Object message) async {
    await _previousRequest?.catchError((e) {});
    _previousRequest = _rawSend(path, message);
  }

  Future<void> _rawSend(String path, Object message) async {
    var client = HttpClient();
    try {
      var request = await client.openUrl(
          'post', uri.replace(path: p.url.join(uri.path, path)));
      request.headers.add('content-type', 'application/json');
      request.add(utf8.encode(jsonEncode(message)));
      var response = await request.close();
      if (response.statusCode >= 400) {
        throw Exception(
            'RemoteLog error (${response.statusCode} ${response.reasonPhrase}');
      }
      await response.drain();
    } catch (e) {
      print('Fail to send log $e');
    } finally {
      client.close();
    }
  }
}

int _statusId = 0;

class _RemoteStatus implements ProgressStatus {
  final int id = ++_statusId;
  final RemoteLogClient client;

  _RemoteStatus._(this.client);

  @override
  void stop() {
    client._stopProgress(id);
  }
}
