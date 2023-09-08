import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../../utils/value_stream.dart';
import '../../devbar.dart';
import 'ui.dart';

class LogNetworkPlugin implements DevbarPlugin {
  static const _maxRequest = 200;

  final requests = ValueStream<List<NetworkRequest>>([]);
  final DevbarState devbar;

  LogNetworkPlugin(this.devbar) {
    devbar.ui
        .addTab(Tab(text: 'Network'), NetworkList(this), hierarchy: ['Logs']);
  }

  static LogNetworkPlugin Function(DevbarState) init() {
    return (devbar) => LogNetworkPlugin(devbar);
  }

  void clear() {
    requests.add([]);
  }

  void request(
    int id, {
    String? apiName,
    Object? body,
    required String method,
    required String path,
    Map<String, String?>? parameters,
  }) {
    var request = NetworkRequest(id,
        apiName: apiName,
        requestBody: body,
        httpMethod: method,
        path: path,
        parameters: parameters ?? {});

    var requestList = requests.value..add(request);

    if (requestList.length > _maxRequest) {
      requestList.removeAt(0);
    }

    requests.add(requestList);
  }

  void response(int id, {body}) {
    var request = requests.value.firstWhereOrNull((n) => n.id == id);
    if (request != null) {
      request.watch.stop();

      request.response = body;

      requests.add(requests.value);
    }
  }

  void responseError(int id, {int? code, String? reason, String? message}) {
    var request = requests.value.firstWhereOrNull((n) => n.id == id);
    if (request != null) {
      request.watch.stop();

      request.errorResponse = ErrorResponse(
          code: code ?? 400, reason: reason ?? '', message: message ?? '');

      requests.add(requests.value);
    }
  }

  @override
  void dispose() {
    requests.dispose();
  }
}

class NetworkRequest {
  final int id;
  final String? apiName;
  final String httpMethod;
  final String path;
  final Map<String, String?> parameters;
  final dynamic requestBody;
  final watch = Stopwatch()..start();
  dynamic response;
  ErrorResponse? errorResponse;

  NetworkRequest(
    this.id, {
    required this.apiName,
    required this.requestBody,
    required this.httpMethod,
    required this.path,
    required this.parameters,
  });
}

class ErrorResponse {
  final int code;
  final String reason, message;

  ErrorResponse(
      {required this.code, required this.reason, required this.message});
}

extension LogNetworkPluginDevbarExtension on DevbarState {
  LogNetworkPlugin get network => plugin<LogNetworkPlugin>();
}
