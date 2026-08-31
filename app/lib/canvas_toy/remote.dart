// Disposable spike: the editor half of the remote-canvas pipe. Pushes the
// scene model (as data) to the scene host on every document change over a
// VM-service extension, coalescing while a push is in flight, and reports
// the measured round trip.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'model.dart';

class RemoteSceneLink {
  RemoteSceneLink(this.doc) {
    doc.addListener(_onDoc);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  final SceneDocument doc;
  final status = ValueNotifier('guest: searching…');

  VmService? _svc;
  String? _isolateId;
  String? _uri;
  Timer? _timer;
  var _inflight = false;
  var _dirty = false;

  void _onDoc() => unawaited(_push());

  Future<void> _tick() async {
    if (_svc != null) return;
    var file = File(
      '${Platform.environment['HOME']}/.flutterware/scene_host_uri.txt',
    );
    if (!file.existsSync()) return;
    var uri = file.readAsStringSync().trim();
    if (uri.isEmpty || uri == _uri) return;
    _uri = uri;
    try {
      var svc = await vmServiceConnectUri(uri);
      var vm = await svc.getVM();
      _isolateId = vm.isolates!.first.id;
      _svc = svc;
      unawaited(
        svc.onDone.then((_) {
          _svc = null;
          _uri = null;
          status.value = 'guest: disconnected';
        }),
      );
      status.value = 'guest: connected';
      unawaited(_push());
    } catch (e) {
      _uri = null;
      status.value = 'guest: connect failed';
    }
  }

  Future<void> _push() async {
    var svc = _svc;
    if (svc == null) return;
    if (_inflight) {
      _dirty = true;
      return;
    }
    _inflight = true;
    var clock = Stopwatch()..start();
    try {
      var res = await svc.callServiceExtension(
        'ext.fw.scene.apply',
        isolateId: _isolateId,
        args: {'scene': jsonEncode(doc.toJson())},
      );
      var rtt = clock.elapsedMicroseconds / 1000;
      var frameMs = (res.json?['frameMs'] as num?)?.toDouble();
      var rects = (res.json?['rects'] as Map?)?.length ?? 0;
      var error = res.json?['error'];
      status.value = error != null
          ? 'guest: $error'
          : 'guest ✓ ${rtt.toStringAsFixed(1)}ms rtt'
                ' · ${frameMs?.toStringAsFixed(1)}ms frame · $rects rects';
    } catch (e) {
      status.value = 'guest: push failed';
    }
    _inflight = false;
    if (_dirty) {
      _dirty = false;
      unawaited(_push());
    }
  }

  void dispose() {
    doc.removeListener(_onDoc);
    _timer?.cancel();
  }
}
