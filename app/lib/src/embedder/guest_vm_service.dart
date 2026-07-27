import 'dart:async';

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
      throw StateError('reloadSources failed: ${report.json}');
    }
    await service.callServiceExtension(
      'ext.flutter.reassemble',
      isolateId: isolateId,
    );
  }

  Future<void> close() => service.dispose();
}
