import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';

/// A minimal VM-service JSON-RPC client for the embedder guest — enough to push
/// a kernel delta into the live isolate and have the framework rebuild.
///
/// The connection is held open across reloads rather than reopened per reload.
class GuestVmService {
  GuestVmService._(this._rpc, this.isolateId);

  final _Rpc _rpc;

  /// The guest's main isolate. Captured once at connect.
  final String isolateId;

  /// Connects to the `http://` URI the guest prints on stdout at startup.
  static Future<GuestVmService> connect(String httpUri) async {
    var ws = httpUri.replaceFirst('http://', 'ws://');
    var rpc = _Rpc(IOWebSocketChannel.connect(Uri.parse('${ws}ws')));
    try {
      var vm = await rpc.call('getVM', {});
      var isolates = (vm['isolates']! as List).cast<Map<String, Object?>>();
      if (isolates.isEmpty) {
        throw StateError('the guest reported no isolates');
      }
      return GuestVmService._(rpc, isolates.first['id']! as String);
    } catch (_) {
      await rpc.close();
      rethrow;
    }
  }

  /// Loads [dillPath] into the live isolate and asks the framework to rebuild.
  ///
  /// [dillPath] is **required**, and is the whole trick: without it the VM
  /// tries to start its own kernel-compiler isolate, which the embedder guest
  /// does not have, and every reload fails with
  /// `Error while starting Kernel isolate task`.
  Future<void> reload(String dillPath) async {
    var report = await _rpc.call('reloadSources', {
      'isolateId': isolateId,
      'rootLibUri': dillPath,
    });
    if (report['success'] != true) {
      throw StateError('reloadSources failed: $report');
    }
    await _rpc.call('ext.flutter.reassemble', {'isolateId': isolateId});
  }

  Future<void> close() => _rpc.close();
}

class _Rpc {
  _Rpc(this._channel) {
    _channel.stream.listen(
      (raw) {
        var message = jsonDecode(raw as String) as Map<String, Object?>;
        var completer = _pending.remove(message['id']);
        if (completer == null) return;
        if (message['error'] != null) {
          completer.completeError(StateError('${message['error']}'));
        } else {
          completer.complete(message['result']! as Map<String, Object?>);
        }
      },
      onError: _failAll,
      onDone: () => _failAll(StateError('the guest VM service closed')),
    );
  }

  final IOWebSocketChannel _channel;
  final _pending = <String, Completer<Map<String, Object?>>>{};
  var _nextId = 0;

  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params,
  ) {
    var requestId = '${_nextId++}';
    var completer = Completer<Map<String, Object?>>();
    _pending[requestId] = completer;
    _channel.sink.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': requestId,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(const Duration(seconds: 30));
  }

  void _failAll(Object error) {
    for (var completer in _pending.values.toList()) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  Future<void> close() => _channel.sink.close();
}
