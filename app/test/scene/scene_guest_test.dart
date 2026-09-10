// What the editor sends its guest. Scene time rides every push, and a
// document that paints with the clock is pushed when only the playhead moved:
// a motion that animates nothing but a shader's `uTime` flushes no document,
// so without that it would never reach the canvas.
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

  @override
  Future<Map<String, dynamic>?> callGuestExtension(
    String method, {
    Map<String, String> args = const {},
  }) async {
    calls.add(args);
    return {'rects': <String, dynamic>{}, 'frameMs': 1.0};
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
}
