import 'dart:convert';
import 'package:http/http.dart';
import '../../../../devbar.dart';
import '../../../../devbar_plugins/log_network.dart';

class DevbarHttpClient extends BaseClient {
  static int _id = 0;
  final String apiName;
  final Client inner;
  final DevbarState? devbar;

  DevbarHttpClient(this.inner, {required this.apiName, this.devbar});

  List<DevbarState> get _instances {
    if (devbar case var instance?) {
      return [instance];
    }
    return Devbar.instances;
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    var id = _id++;
    dynamic requestBody = '<unknown>';
    if (request.method.toUpperCase() == 'GET') {
      requestBody = '';
    } else if (request.headers['content-type']?.contains('json') ?? false) {
      var bodyBytes = await request.finalize().toBytes();
      var bodyString = requestBody = utf8.decode(bodyBytes);
      if (bodyString.isNotEmpty) {
        requestBody = jsonDecode(bodyString);
      }
      // Recreate the request since the body was read
      request = Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = bodyBytes;
    }

    for (var devbar in _instances) {
      devbar.maybeNetwork?.request(
        id,
        apiName: apiName,
        method: request.method,
        body: requestBody,
        path: request.url.toString(),
        parameters: {
          ...request.url.queryParameters,
          for (var header in request.headers.entries)
            if (header.key == 'Authorization')
              header.key: _ellipsisCenter(header.value, maxLength: 15)
            else
              header.key: header.value,
        },
      );
    }
    try {
      var response = await inner.send(request);
      dynamic body = '<unknown>';
      if (response.headers['content-type']?.contains('json') ?? false) {
        var responseBytes = await response.stream.toBytes();
        if (responseBytes.isNotEmpty) {
          body = Utf8Decoder().fuse(JsonDecoder()).convert(responseBytes);
        }
        // Recreate the response since the body was read
        response = StreamedResponse(
            ByteStream.fromBytes(responseBytes), response.statusCode,
            contentLength: response.contentLength,
            request: response.request,
            headers: response.headers,
            isRedirect: response.isRedirect,
            persistentConnection: response.persistentConnection,
            reasonPhrase: response.reasonPhrase);
      }

      for (var devbar in _instances) {
        if (response.statusCode < 300) {
          devbar.maybeNetwork?.response(id, body: body);
        } else {
          devbar.maybeNetwork?.responseError(
            id,
            code: response.statusCode,
            reason: response.reasonPhrase ?? '',
            message: '$body',
          );
        }
      }

      return response;
    } catch (e) {
      for (var devbar in _instances) {
        devbar.maybeNetwork?.responseError(
          id,
          code: -1,
          reason: '${e.runtimeType}',
          message: '$e',
        );
      }

      rethrow;
    }
  }
}

String _ellipsisCenter(String input,
    {required int maxLength, String ellipsis = '..'}) {
  if (ellipsis.length > maxLength) {
    throw Exception('Ellipsis is longer than max length');
  }
  if (input.length <= maxLength) return input;

  var takeLength = maxLength - ellipsis.length;

  var before = (takeLength / 2).ceil();
  var after = takeLength - before;

  return '${input.substring(0, before)}$ellipsis${input.substring(input.length - after)}';
}

extension on DevbarState {
  LogNetworkPlugin? get maybeNetwork => maybePlugin<LogNetworkPlugin>();
}
