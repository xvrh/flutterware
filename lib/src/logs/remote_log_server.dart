import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'logger.dart';

class RemoteLogServer {
  static const printBoxPath = 'print-box';
  static const printLogPath = 'print-log';
  static const startProgressPath = 'start-progress';
  static const stopProgressPath = 'stop-progress';

  final HttpServer server;
  final Logger logger;

  RemoteLogServer._(this.server, this.logger) {
    server.listen(_handleRequest);
  }

  static Future<RemoteLogServer> start(Logger logger, {int? port}) async {
    var httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port ?? 0);
    return RemoteLogServer._(httpServer, logger);
  }

  String get url =>
      'http://${Platform.isWindows ? 'localhost' : server.address.host}:${server.port}';

  void _handleRequest(HttpRequest request) async {
    var path = request.uri.pathSegments.firstOrNull;
    var body = await utf8.decodeStream(request);

    try {
      var bodyJson = jsonDecode(body) as Map<String, dynamic>;

      switch (path) {
        case printBoxPath:
          _handlePrintBox(PrintBox.fromJson(bodyJson));
          break;
        case printLogPath:
          _handlePrintLog(PrintLog.fromJson(bodyJson));
          break;
        case startProgressPath:
          _handleStartProgress(StartProgress.fromJson(bodyJson));
          break;
        case stopProgressPath:
          _handleStopProgress(StopProgress.fromJson(bodyJson));
          break;
      }

      request.response.statusCode = 200;
    } catch (e) {
      request.response.statusCode = 500;
      request.response.add(utf8.encode('$e'));
    }
    await request.response.close();
  }

  void _handlePrintBox(PrintBox command) {
    logger.printBox(command.message, title: command.title);
  }

  void _handlePrintLog(PrintLog command) {
    switch (command.type) {
      case PrintType.trace:
        logger.printTrace(command.message);
        break;
      case PrintType.status:
        logger.printStatus(command.message, wrap: command.wrap);
        break;
      case PrintType.warning:
        logger.printWarning(command.message, wrap: command.wrap);
        break;
      case PrintType.error:
        var stackTrace = command.stackTrace;
        logger.printError(command.message,
            stackTrace:
                stackTrace != null ? StackTrace.fromString(stackTrace) : null,
            wrap: command.wrap);
        break;
    }
  }

  final _currentProgress = <int, Status>{};
  void _handleStartProgress(StartProgress command) {
    var message = command.message;
    Status status;
    if (message != null) {
      status = logger.startProgress(message);
    } else {
      status = logger.startSpinner();
    }
    _currentProgress[command.id] = status;
  }

  void _handleStopProgress(StopProgress command) {
    var status = _currentProgress[command.id]!;
    status.stop();
    _currentProgress.remove(command.id);
  }

  void close() {
    server.close();
  }
}

enum PrintType { trace, status, warning, error }

class PrintLog {
  final PrintType type;
  final String message;
  final String? stackTrace;
  final bool? wrap;

  PrintLog(this.type, this.message, {this.wrap}) : stackTrace = null;

  PrintLog.error(this.message, {this.stackTrace, this.wrap})
      : type = PrintType.error;

  PrintLog._(this.type, this.message, {this.stackTrace, this.wrap});

  factory PrintLog.fromJson(Map<String, dynamic> json) {
    return PrintLog._(
        PrintType.values[json['type'] as int], json['message'] as String,
        stackTrace: json['stackTrace'] as String?, wrap: json['wrap'] as bool?);
  }

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'message': message,
        'stackTrace': stackTrace,
        'wrap': wrap,
      };
}

class PrintBox {
  final String message;
  final String? title;

  PrintBox(this.message, this.title);

  factory PrintBox.fromJson(Map<String, dynamic> json) {
    return PrintBox(json['message'] as String, json['title'] as String?);
  }

  Map<String, dynamic> toJson() => {
        'message': message,
        'title': title,
      };
}

class StartProgress {
  final String? message;
  final int id;

  StartProgress(this.id, this.message);

  factory StartProgress.fromJson(Map<String, dynamic> json) {
    return StartProgress(json['id'] as int, json['message'] as String);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'message': message,
      };
}

class StopProgress {
  final int id;

  StopProgress(this.id);

  factory StopProgress.fromJson(Map<String, dynamic> json) {
    return StopProgress(json['id'] as int);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
      };
}
