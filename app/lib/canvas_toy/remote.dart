// Disposable spike: the editor half of the remote-canvas pipe. Pushes the
// scene model (as data) to every announced scene host over a VM-service
// extension, coalescing per guest while a push is in flight, and reports the
// measured round trips.
//
// Guests announce by dropping their websocket URI into
// ~/.flutterware/scene_hosts/<name>.txt — the host does it itself on
// desktop; anything (a script, an agent) may drop one for a guest that
// cannot reach this filesystem, like a simulator.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'package:flutterware/scene_authoring.dart';

import '../src/scene/editor.dart';

class RemoteSceneLink {
  RemoteSceneLink(this.doc, {this.editor}) {
    doc.addListener(_onDoc);
    // Selection is editor chrome on the wire; its changes push too.
    editor?.addListener(_onDoc);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  final SceneDocument doc;

  /// When the link belongs to an editor, its selection rides the wire so a
  /// remote host can outline it.
  final SceneEditor? editor;

  Map<String, dynamic> _wire() =>
      doc.toJson(selected: editor?.selectionNames ?? const []);
  final status = ValueNotifier('guests: searching…');

  final _conns = <String, _Conn>{};
  Timer? _timer;
  var _payloadBytes = 0;

  void _onDoc() => _pushAll();

  Directory get _dir =>
      Directory('${Platform.environment['HOME']}/.flutterware/scene_hosts');

  Future<void> _tick() async {
    var dir = _dir;
    if (!dir.existsSync()) return;
    for (var file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.txt')) continue;
      var uri = file.readAsStringSync().trim();
      if (uri.isEmpty || _conns.containsKey(uri)) continue;
      unawaited(_connect(uri, file));
    }
    _report();
  }

  Future<void> _connect(String uri, File announce) async {
    var conn = _Conn(uri);
    _conns[uri] = conn;
    try {
      var svc = await vmServiceConnectUri(uri);
      var vm = await svc.getVM();
      conn.svc = svc;
      conn.isolateId = vm.isolates!.first.id;
      unawaited(
        svc.onDone.then((_) {
          _conns.remove(uri);
          _report();
        }),
      );
      _report();
      unawaited(_push(conn));
    } catch (_) {
      // Stale announcement — a guest that is gone. Remove both.
      _conns.remove(uri);
      try {
        announce.deleteSync();
      } catch (_) {}
    }
  }

  void _pushAll() {
    var scene = jsonEncode(_wire());
    _payloadBytes = scene.length;
    for (var conn in _conns.values) {
      conn.pending = scene;
      unawaited(_push(conn));
    }
  }

  Future<void> _push(_Conn conn) async {
    var svc = conn.svc;
    if (svc == null || conn.inflight) return;
    var scene = conn.pending ?? jsonEncode(_wire());
    conn.pending = null;
    conn.inflight = true;
    var clock = Stopwatch()..start();
    try {
      var res = await svc.callServiceExtension(
        'ext.fw.scene.apply',
        isolateId: conn.isolateId,
        args: {'scene': scene},
      );
      conn.rtt = clock.elapsedMicroseconds / 1000;
      conn.frameMs = (res.json?['frameMs'] as num?)?.toDouble();
      conn.rects = (res.json?['rects'] as Map?)?.length ?? 0;
    } catch (_) {
      conn.rtt = null;
    }
    conn.inflight = false;
    _report();
    if (conn.pending != null) unawaited(_push(conn));
  }

  void _report() {
    if (_conns.isEmpty) {
      status.value = 'guests: none';
      return;
    }
    var parts = [
      for (var c in _conns.values)
        c.rtt == null
            ? '…'
            : '${c.rtt!.toStringAsFixed(0)}/${c.frameMs?.toStringAsFixed(0)}ms'
                  ' ${c.rects}r',
    ];
    status.value =
        'guests: ${_conns.length} · ${parts.join(' · ')}'
        ' · ${(_payloadBytes / 1024).toStringAsFixed(1)}KB';
  }

  void dispose() {
    doc.removeListener(_onDoc);
    editor?.removeListener(_onDoc);
    _timer?.cancel();
  }
}

class _Conn {
  _Conn(this.uri);

  final String uri;
  VmService? svc;
  String? isolateId;
  var inflight = false;
  String? pending;
  double? rtt;
  double? frameMs;
  var rects = 0;
}
