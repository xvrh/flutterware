import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// The embedder guest's VM service — enough to push a kernel delta into the
/// live isolate and have the framework rebuild.
///
/// Wraps `package:vm_service`, the generated client the Dart team ships,
/// rather than hand-rolling JSON-RPC. The spike this grew from did hand-roll
/// it, which was fine for one call and stops being fine as soon as anything
/// needs **events** — guest stdout, stderr, and `Extension` streams all arrive
/// as server-initiated notifications with no request id, which a
/// request/response-only client drops on the floor.
class GuestVmService {
  GuestVmService._(this.service, this.isolateId);

  /// The underlying client, for calls this wrapper does not name.
  final VmService service;

  /// The guest's main isolate, captured once at connect.
  final String isolateId;

  /// Connects to the `http://` URI the guest prints on stdout at startup.
  static Future<GuestVmService> connect(String httpUri) async {
    var ws = httpUri.replaceFirst('http://', 'ws://');
    var service = await vmServiceConnectUri('${ws}ws');
    try {
      var vm = await service.getVM();
      var isolates = vm.isolates;
      if (isolates == null || isolates.isEmpty) {
        throw StateError('the guest reported no isolates');
      }
      return GuestVmService._(service, isolates.first.id!);
    } catch (_) {
      await service.dispose();
      rethrow;
    }
  }

  /// Loads [dillPath] into the live isolate and asks the framework to rebuild.
  ///
  /// [dillPath] is the whole trick: without it the VM tries to start its own
  /// kernel-compiler isolate, which the embedder guest does not have, and every
  /// reload fails with `Error while starting Kernel isolate task`. It is what
  /// `flutter_tools` does at `run_hot.dart:1272`.
  Future<void> reload(String dillPath) async {
    var report = await service.reloadSources(isolateId, rootLibUri: dillPath);
    if (report.success != true) {
      // The VM's message names what the delta *wanted* and never what was
      // there — `lookup Failed: <name> in @method in file:///...` says a
      // library is not in the running program the way the delta expects, which
      // cannot be acted on without knowing which of the two is wrong.
      throw StateError(
        'reloadSources refused ${p.basename(dillPath)}: ${report.json}\n'
        'The isolate holds:\n${await _catalogLibraries()}',
      );
    }
    await service.callServiceExtension(
      'ext.flutter.reassemble',
      isolateId: isolateId,
    );
  }

  /// Calls one of the guest's own service extensions and decodes its JSON.
  ///
  /// Returns null when the extension is not registered — a guest from before
  /// the extension existed, or one whose first frame has not run yet. That is
  /// an answer, not a failure: a panel asking what knobs a demo has, of a demo
  /// that has not built, should show nothing rather than an error.
  ///
  /// Use it only where "not registered" is genuinely one of the answers. For a
  /// call that has no meaning if it did not land — anything that *writes* —
  /// use [requireExtension], which is the same call without the excuse.
  Future<Map<String, dynamic>?> callExtension(
    String method, {
    Map<String, String>? args,
  }) async {
    try {
      return await _call(method, args);
    } on RPCError catch (e) {
      if (_isMethodNotFound(e)) return null;
      rethrow;
    }
  }

  /// Calls an extension that must exist, and throws when it does not.
  ///
  /// The counterpart to [callExtension], and it exists because of a bug it
  /// would have caught. `setParameter` was renamed to `setParameters`; two
  /// callers were missed; and because every call went through the tolerant form
  /// the misses were invisible — `--knobs` on a screenshot applied nothing and
  /// reported success, and the harness assertion that should have caught it
  /// compared `null != true` and passed.
  ///
  /// A guest too old to have the extension is a real case, which is why the
  /// tolerant form stays. It is just not the right form for a write.
  Future<Map<String, dynamic>?> requireExtension(
    String method, {
    Map<String, String>? args,
  }) async {
    try {
      return await _call(method, args);
    } on RPCError catch (e) {
      if (!_isMethodNotFound(e)) rethrow;
      throw StateError(
        'the guest has no $method. It registers: '
        '${(await _registeredExtensions()).join(', ')}',
      );
    }
  }

  Future<Map<String, dynamic>?> _call(
    String method,
    Map<String, String>? args,
  ) async {
    var response = await service.callServiceExtension(
      method,
      isolateId: isolateId,
      args: args,
    );
    return response.json;
  }

  /// 32601 is JSON-RPC's "method not found", which is what an unregistered
  /// extension is. Sign varies with who wrapped it.
  static bool _isMethodNotFound(RPCError e) => e.code.abs() == 32601;

  /// What the isolate does register, for the error above — an extension that is
  /// missing is nearly always one that was renamed.
  Future<List<String>> _registeredExtensions() async {
    try {
      var isolate = await service.getIsolate(isolateId);
      return [
        for (var rpc in isolate.extensionRPCs ?? const <String>[])
          if (rpc.startsWith('ext.flutterware.')) rpc,
      ]..sort();
    } catch (_) {
      return const ['(could not read the isolate)'];
    }
  }

  /// The catalog-relevant libraries the isolate currently holds, for the error
  /// above. Best effort: a diagnostic must not fail louder than the fault.
  Future<String> _catalogLibraries() async {
    try {
      var isolate = await service.getIsolate(isolateId);
      var uris = [
        for (var library in isolate.libraries ?? const <LibraryRef>[])
          if (library.uri case var uri?)
            if (uri.contains('/build/catalog/') ||
                uri.contains('/demo/') ||
                uri.contains('/demos/'))
              '  $uri',
      ];
      return uris.isEmpty ? '  (none from this catalog)' : uris.join('\n');
    } catch (e) {
      return '  (could not read the isolate: $e)';
    }
  }

  Future<void> close() => service.dispose();
}
