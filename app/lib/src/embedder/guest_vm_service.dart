import 'dart:async';

import 'package:meta/meta.dart';
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
  GuestVmService._(
    this.service,
    this.isolateId, {
    this.registrationWindow = _defaultRegistrationWindow,
  }) {
    unawaited(service.onDone.then((_) => _gone = true));
  }

  /// A client over a [service] the caller connected, for a test.
  ///
  /// [connect] is the way in for everything real: it is what knows a guest
  /// prints an `http://` URI and that the isolate to talk to is the first one.
  /// A test of [requireExtension]'s wait has neither a guest nor a socket, and
  /// standing one up to watch a retry would be a slower test that proved less.
  @visibleForTesting
  factory GuestVmService.forTesting(
    VmService service,
    String isolateId, {
    Duration registrationWindow = _defaultRegistrationWindow,
  }) => GuestVmService._(
    service,
    isolateId,
    registrationWindow: registrationWindow,
  );

  /// The underlying client, for calls this wrapper does not name.
  final VmService service;

  /// Whether the connection has finished — the guest exited, or it was closed.
  ///
  /// Checked before calling rather than only caught after. A call made after the
  /// client was disposed does not fail cleanly: `VmService` errors the
  /// completers it is *holding* and then clears them, so a later one registers
  /// a completer nothing will ever complete and writes to a closed sink. The
  /// caller waits forever. Only a call already in flight at the moment of
  /// disposal comes back as an error, which is why both halves are handled.
  bool get isGone => _gone;
  var _gone = false;

  /// The guest's main isolate, captured once at connect.
  final String isolateId;

  /// How long [requireExtension] gives the guest to register before it calls
  /// an extension missing. See there for why waiting at all is the fix.
  ///
  /// Generous by default: what waiting costs is a slower error for a typo, and
  /// what not waiting costs is a crash on every cold start.
  final Duration registrationWindow;

  static const _defaultRegistrationWindow = Duration(seconds: 5);

  /// How often [requireExtension] asks again inside that window.
  ///
  /// By re-calling rather than by polling `getIsolate` for the name: the call
  /// is the thing the caller wanted, so a list saying the extension is there
  /// would only be one more fact to then act on.
  static const _registrationPoll = Duration(milliseconds: 25);

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
  /// Null covers a guest that is gone, too, for the same reason and one
  /// more. The same reason: a question put to a guest that no longer exists has
  /// nothing to answer with, and every caller of this form already handles
  /// nothing. The one more: the calls that meet a dead connection are mostly
  /// *teardown* — `unwatch`, `clearLogs` — made from a `dispose` as the guest
  /// goes away, fire-and-forget by nature. `unawaited` silences the lint, not
  /// the error, so the failure they were documented as tolerating arrived as an
  /// unhandled exception and a widget-unmount stack trace in the run's log.
  ///
  /// Use it only where "not registered" is genuinely one of the answers. For a
  /// call that has no meaning if it did not land — anything that *writes* —
  /// use [requireExtension], which is the same call without the excuse.
  Future<Map<String, dynamic>?> callExtension(
    String method, {
    Map<String, String>? args,
  }) async {
    if (_gone) return null;
    try {
      return await _call(method, args);
    } on RPCError catch (e) {
      if (_isMethodNotFound(e) || _isConnectionGone(e)) return null;
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
  ///
  /// Gives the guest [registrationWindow] to register before it believes the
  /// answer. "Not registered" and "not registered *yet*" arrive as the
  /// same JSON-RPC 32601, and nothing but time tells them apart: the VM service
  /// is listening — and its URI printed, and this client connected — well
  /// before the guest's `main` has run, so a host that asks the moment it
  /// connects is asking an isolate that has registered nothing at all. That is
  /// the window a panel mounting at startup lands in, and reporting it as a
  /// missing extension names the wrong fault.
  ///
  /// The strictness is unchanged, only postponed. A renamed extension still
  /// throws, and still lists what the guest does register — it just pays the
  /// wait first, which is only ever paid by a typo.
  Future<Map<String, dynamic>?> requireExtension(
    String method, {
    Map<String, String>? args,
  }) async {
    // Strict here too: a write that cannot land is a failure, and this is the
    // form whose whole point is saying so. What it must not do is *wait* —
    // against a disposed client the call would never come back at all, and a
    // silent forever is the one answer worse than an error.
    if (_gone) throw StateError('the guest is gone — cannot $method');
    var waited = Stopwatch()..start();
    while (true) {
      try {
        return await _call(method, args);
      } on RPCError catch (e) {
        if (!_isMethodNotFound(e)) rethrow;
        if (waited.elapsed >= registrationWindow) {
          throw StateError(
            'the guest has no $method. It registers: '
            '${(await _registeredExtensions()).join(', ')}',
          );
        }
        await Future<void>.delayed(_registrationPoll);
      }
    }
  }

  /// The guest's `postEvent` calls of one kind, decoded.
  ///
  /// The other direction of the extension channel, and the reason this wrapper
  /// is built on `package:vm_service` rather than the hand-rolled JSON-RPC the
  /// spike started with: these arrive as server-initiated notifications with no
  /// request id, which a request/response client drops on the floor.
  ///
  /// The `streamListen` is per-connection rather than per-subscriber, and the
  /// VM answers a repeat with "already subscribed" — an error that means the
  /// thing the caller wanted is true, so it is swallowed rather than reported.
  Stream<Map<String, Object?>> extensionEvents(String kind) async* {
    try {
      await service.streamListen(EventStreams.kExtension);
    } on RPCError catch (e) {
      if (!e.message.contains('already subscribed')) rethrow;
    }
    yield* service.onExtensionEvent
        .where((event) => event.extensionKind == kind)
        .map((event) => event.extensionData?.data ?? const {});
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

  /// What a call already in flight gets when the client is disposed under it.
  ///
  /// By message as well as by code: 32000 is JSON-RPC's *server error*, the
  /// bucket a guest's own extension throwing would land in too, and swallowing
  /// that would hide a real fault. The wording is `package:vm_service`'s own,
  /// from the one place it completes its outstanding calls on `dispose`.
  static bool _isConnectionGone(RPCError e) =>
      e.code.abs() == 32000 &&
      e.message.contains('Service connection disposed');

  /// What the isolate does register, for the error above — an extension that is
  /// missing is nearly always one that was renamed.
  Future<List<String>> _registeredExtensions() async {
    try {
      var isolate = await service.getIsolate(isolateId);
      // Both namespaces: a missing extension is usually one of ours that was
      // renamed, but it can equally be one of the framework's that the VM
      // service has not been told about yet — and a list showing neither says
      // nothing about which.
      return [
        for (var rpc in isolate.extensionRPCs ?? const <String>[])
          if (rpc.startsWith('ext.flutter')) rpc,
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
