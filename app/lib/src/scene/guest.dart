// The guest half of the editor: the app's own process, rendering the scene
// from data, composited back as a texture.
//
// The scene v1 decision the whole editor rests on is that the GUEST IS THE
// ONLY RENDERER — the app's theme, its real external widgets, its measured
// geometry — so this class is what every scene surface mounts: it boots the
// session, pushes the document as JSON on every change, and hands the
// measured rects back to the editor, which is where selection and handles
// read their geometry from.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutterware/scene_authoring.dart';

import '../previews/catalog_session.dart';
import 'editor.dart';

/// The preview entry a project declares to host scenes — the registration,
/// per the scene v1 decision that a preview entry *is* the registration.
const sceneHostEntrySymbol = 'sceneCanvasHost';

/// Pushes one editor's document to one guest, coalescing while a push is in
/// flight, and applies the rects it measures back onto the nodes.
class SceneGuest {
  SceneGuest(this.session, this.editor) {
    editor.doc.addListener(_push);
    editor.addListener(_push);
    session.addListener(_onSession);
    // A session that is already up notifies nobody about it: ask now, or a
    // guest created over a running session shows what it was showing.
    _onSession();
    // Until the guest's extension is registered (entry selected, first
    // build), pushes fail; retry until the first one lands.
    _retry = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_everApplied) {
        _retry?.cancel();
      } else {
        _push();
      }
    });
  }

  final CatalogSession session;
  final SceneEditor editor;

  /// What the toolbar shows: the round trip, or what went wrong.
  final status = ValueNotifier('guest: booting…');

  var _inflight = false;
  var _dirty = false;
  var _everApplied = false;
  Timer? _retry;

  /// Whether the guest has ever rendered — until then the canvas shows the
  /// booting state rather than a blank artboard.
  bool get isLive => _everApplied;

  /// Puts the scene host on the guest whenever it is not already there —
  /// including over whatever the session picked for itself while booting,
  /// which is how a rebooted session came up showing the catalog's first
  /// entry under the scene panel.
  /// The engine last seen: a new one is a host that has forgotten the scene.
  Object? _engine;

  void _onSession() {
    if (session.phase != CatalogSessionPhase.ready) return;
    if (!identical(session.engine, _engine)) {
      _engine = session.engine;
      // A guest that restarted or reloaded holds no scene until it is sent
      // one, and nothing else sends it before the next edit.
      if (_everApplied) _push();
    }
    for (var entry in session.entries) {
      if (entry.symbol == sceneHostEntrySymbol) {
        if (session.wantedEntryId != entry.id) session.wantedEntryId = entry.id;
        return;
      }
    }
    status.value =
        'guest: this project declares no scene host — add a @Preview entry '
        'named $sceneHostEntrySymbol';
  }

  /// Sends the document now — after a guest reload, which remounts the host
  /// with no scene, and otherwise only when the document or the selection
  /// changes.
  void push() => _push();

  void _push() {
    if (_inflight) {
      _dirty = true;
      return;
    }
    _inflight = true;
    var clock = Stopwatch()..start();
    unawaited(
      session
          .callGuestExtension(
            'ext.fw.scene.apply',
            args: {
              'scene': jsonEncode(
                editor.doc.toWire(selected: editor.selectionNames),
              ),
            },
          )
          .then((reply) {
            var rtt = clock.elapsedMicroseconds / 1000;
            if (reply != null && reply['error'] == null) {
              _everApplied = true;
              var frameMs = (reply['frameMs'] as num?)?.toDouble();
              _applyRects((reply['rects'] as Map?)?.cast<String, dynamic>());
              status.value =
                  'guest ✓ ${rtt.toStringAsFixed(1)}ms rtt'
                  ' · ${frameMs?.toStringAsFixed(1)}ms frame';
            } else if (reply != null) {
              status.value = 'guest: ${reply['error']}';
            }
          })
          .catchError((Object e) {
            if (_everApplied) status.value = 'guest: push failed';
          })
          .whenComplete(() {
            _inflight = false;
            if (_dirty) {
              _dirty = false;
              _push();
            }
          }),
    );
  }

  /// The guest is the only renderer, so its laid-out rects are the editor's
  /// geometry: selection, hit targets and handles all read what it measured.
  void _applyRects(Map<String, dynamic>? rects) {
    if (rects == null) return;
    var changed = false;
    for (var (node, _) in editor.doc.walk()) {
      var raw = rects[node.name];
      if (raw is List && raw.length == 4) {
        var rect = SceneRect(
          (raw[0] as num).toDouble(),
          (raw[1] as num).toDouble(),
          (raw[2] as num).toDouble(),
          (raw[3] as num).toDouble(),
        );
        if (node.measured != rect) {
          node.measured = rect;
          changed = true;
        }
      }
    }
    if (changed) editor.doc.geometryEpoch.value++;
  }

  void dispose() {
    _retry?.cancel();
    editor.doc.removeListener(_push);
    editor.removeListener(_push);
    session.removeListener(_onSession);
    status.dispose();
  }
}
