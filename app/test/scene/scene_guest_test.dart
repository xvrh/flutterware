// What the editor sends its guest. Scene time rides every push, and a
// document that paints with the clock is pushed when only the playhead moved:
// a motion that animates nothing but a shader's `uTime` flushes no document,
// so without that it would never reach the canvas.
//
// And what the guest tells a capture: busy until the host first answers,
// while a push is out, and while the canvas's last answer named shader
// programs still loading — a pass paints nothing until its program lands, so
// that picture is honest and wrong.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/previews/catalog_session.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/guest.dart';

/// A session whose guest only answers `callGuestExtension`, and remembers
/// what it was asked.
class _Session extends CatalogSession {
  _Session() : super(appPackageRoot: '', flutterSdkRoot: '', projectRoot: '');

  final calls = <Map<String, String>>[];

  /// What the host names as still loading, as it would put it on the wire.
  Object? pendingShaders;

  /// Held open, the push is in flight until it completes.
  Completer<void>? gate;

  void announce() => notifyListeners();

  /// How many more pushes fail the way they do before the host's extension
  /// is registered.
  var unregistered = 0;

  @override
  Future<Map<String, dynamic>?> callGuestExtension(
    String method, {
    Map<String, String> args = const {},
  }) async {
    calls.add(args);
    await gate?.future;
    if (unregistered > 0) {
      unregistered--;
      throw StateError('ext.fw.scene.apply is not registered');
    }
    return {
      'rects': <String, dynamic>{},
      'frameMs': 1.0,
      'pendingShaders': ?pendingShaders,
    };
  }
}

const _shader = FillLayer(paint: ShaderPaint('shaders/glow.frag'));

void main() {
  late _Session session;
  late SceneDocument scene;
  late SceneEditor editor;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
    scene = coffeeBannerDraft();
    editor = SceneEditor(scene);
  });

  SceneGuest guest() {
    var g = SceneGuest(session, editor, groupDirectory: 'lib/scenes');
    addTearDown(g.dispose);
    return g;
  }

  TextNode headline() => scene.nodeNamed('headline')! as TextNode;

  test('a push carries the playhead as seconds', () async {
    var g = guest();
    await pumpEventQueue();
    editor.playhead = const Duration(milliseconds: 400);
    g.push();
    await pumpEventQueue();
    expect(session.calls.last['time'], '0.4');
  });

  test(
    'a playhead move pushes nothing for a document without a shader',
    () async {
      guest().push();
      await pumpEventQueue();
      var before = session.calls.length;
      editor.playhead = const Duration(milliseconds: 250);
      await pumpEventQueue();
      expect(session.calls, hasLength(before));
    },
  );

  test('a playhead move pushes a document that paints with a shader', () async {
    headline().layers = [_shader];
    guest().push();
    await pumpEventQueue();
    var before = session.calls.length;
    editor.playhead = const Duration(milliseconds: 250);
    await pumpEventQueue();
    expect(session.calls, hasLength(before + 1));
    expect(session.calls.last['time'], '0.25');
  });

  test('an edit that adds a shader pass starts the playhead pushing', () async {
    guest().push();
    await pumpEventQueue();
    editor.perform('paint', () => headline().layers = [_shader]);
    await pumpEventQueue();
    var before = session.calls.length;
    editor.playhead = const Duration(milliseconds: 250);
    await pumpEventQueue();
    expect(session.calls, hasLength(before + 1));
  });

  group('with no motion open, the time is zero', () {
    // The chevron stops the playback, and a stop zeroes the playhead on its
    // own; these are the ways a motion leaves the drawer without one.
    for (var (label, close) in <(String, void Function(SceneEditor))>[
      ('deleted', (e) => e.removeMotion('BannerIntro')),
      ('a parameter opened over it', (e) => e.openParam = 'tagline'),
      ('its creation undone', (e) => e.undo()),
    ]) {
      test(label, () async {
        headline().layers = [_shader];
        scene.params.add(
          SceneParamDecl('tagline', SceneParamKind.string, 'Fresh'),
        );
        editor = SceneEditor(scene)
          ..addMotion('BannerScene', name: 'BannerIntro');
        editor.playhead = const Duration(milliseconds: 250);
        guest().push();
        await pumpEventQueue();
        close(editor);
        await pumpEventQueue();
        expect(editor.activeMotion, isNull);
        expect(editor.playhead, Duration.zero);
        expect(session.calls.last['time'], '0.0');
      });
    }
  });

  group('busy', () {
    test('while a push is out, and not once it has landed', () async {
      var g = guest()..push();
      await pumpEventQueue();
      expect(g.busyWith, isNull);
      session.gate = Completer();
      g.push();
      await pumpEventQueue();
      expect(g.busyWith, 'drawing the scene');
      session.gate!.complete();
      await pumpEventQueue();
      expect(g.busyWith, isNull);
    });

    test('from the start until the host first answers, through the quiet '
        'between failed pushes', () {
      fakeAsync((async) {
        session.unregistered = 2;
        var g = guest();
        expect(g.busyWith, 'drawing the scene', reason: 'nothing drawn yet');
        g.push();
        async.flushMicrotasks();
        expect(session.calls, hasLength(1));
        expect(
          g.busyWith,
          'drawing the scene',
          reason: 'a failed push is not a canvas',
        );
        async.elapse(const Duration(milliseconds: 500));
        expect(session.calls, hasLength(2));
        expect(g.busyWith, 'drawing the scene');
        async.elapse(const Duration(milliseconds: 500));
        expect(session.calls, hasLength(3));
        expect(g.busyWith, isNull);
      });
    });

    test('not before the first answer when no answer is coming', () {
      var g = guest();
      session.phase = CatalogSessionPhase.error;
      expect(g.busyWith, isNull);
    });

    test('nor when the group declares no host to answer', () {
      var g = guest();
      session
        ..phase = CatalogSessionPhase.ready
        ..announce();
      expect(g.status.value, contains('no scene host'));
      expect(g.busyWith, isNull);
    });

    test('while the canvas names shaders loading, re-pushing every 250ms '
        'until it names none', () {
      fakeAsync((async) {
        session.pendingShaders = ['a.frag'];
        var g = guest();
        g.push();
        async.flushMicrotasks();
        expect(g.busyWith, 'loading a.frag');
        var pushed = session.calls.length;

        async.elapse(const Duration(milliseconds: 249));
        expect(session.calls, hasLength(pushed));
        async.elapse(const Duration(milliseconds: 1));
        expect(session.calls, hasLength(pushed + 1));
        expect(g.busyWith, 'loading a.frag');

        session.pendingShaders = null;
        async.elapse(const Duration(milliseconds: 250));
        expect(session.calls, hasLength(pushed + 2));
        expect(g.busyWith, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(session.calls, hasLength(pushed + 2));
      });
    });

    test('a newer push supersedes the pending re-push', () {
      fakeAsync((async) {
        session.pendingShaders = ['a.frag'];
        var g = guest();
        g.push();
        async.flushMicrotasks();
        var pushed = session.calls.length;

        async.elapse(const Duration(milliseconds: 100));
        g.push();
        async.flushMicrotasks();
        expect(session.calls, hasLength(pushed + 1));
        // The first re-push would have gone out at 250ms; the newer push's
        // own goes out 250ms after it.
        async.elapse(const Duration(milliseconds: 200));
        expect(session.calls, hasLength(pushed + 1));
        async.elapse(const Duration(milliseconds: 50));
        expect(session.calls, hasLength(pushed + 2));
      });
    });

    test('dispose cancels the pending re-push', () {
      fakeAsync((async) {
        session.pendingShaders = ['a.frag'];
        var g = SceneGuest(session, editor, groupDirectory: 'lib/scenes');
        g.push();
        async.flushMicrotasks();
        var pushed = session.calls.length;
        g.dispose();
        async.elapse(const Duration(seconds: 1));
        expect(session.calls, hasLength(pushed));
      });
    });

    for (var (label, wire) in <(String, Object?)>[
      ('absent', null),
      ('not a list', 'a.frag'),
      ('a list of no names', [1, null]),
    ]) {
      test('a pendingShaders that is $label is nothing pending', () async {
        session.pendingShaders = wire;
        var g = guest()..push();
        await pumpEventQueue();
        expect(g.busyWith, isNull);
      });
    }
  });
}
