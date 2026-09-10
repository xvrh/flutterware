import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/embedder/embedded_engine.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';

/// Whether the texture on screen has anything in it — which is not the same
/// question as whether the guest is running, and the difference was a black
/// phone in every screenshot of a project that settled quickly.
///
/// The ring is mapped and the texture is in the widget tree from the moment
/// the guest announces its surfaces, several hundred milliseconds before it
/// draws into them. Anything photographing the panel has to wait for the
/// frame, not for the plumbing.
void main() {
  const channel = MethodChannel('flutterware/embedder_texture');

  late List<MethodCall> calls;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'createTexture' => 7,
            'updateSurfaces' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  EmbeddedEngine engine() =>
      EmbeddedEngine(appPackageRoot: '/app', flutterSdkRoot: '/sdk');

  SurfacesAllocatedMessage surfaces(int generation) => SurfacesAllocatedMessage(
    generation: generation,
    width: 900,
    height: 700,
    rowBytes: 3600,
    surfaces: const ['1', '2', '3'],
  );

  FrameReadyMessage frame(int generation, {int frameId = 1}) =>
      FrameReadyMessage(ringIndex: 0, frameId: frameId, generation: generation);

  test('a mapped ring nobody has drawn into has not painted', () async {
    var subject = engine();
    expect(subject.hasPainted, isFalse, reason: 'nothing has happened yet');

    await subject.handleMessage(surfaces(0));
    expect(subject.phase, EmbeddedEnginePhase.running);
    expect(
      subject.hasPainted,
      isFalse,
      reason: 'the texture exists and is empty',
    );

    await subject.handleMessage(frame(0));
    expect(subject.hasPainted, isTrue);
  });

  test('a resize drops the picture until the new ring is drawn', () async {
    var subject = engine();
    await subject.handleMessage(surfaces(0));
    await subject.handleMessage(frame(0));

    // What the previews panel does on its first layout: the guest is running
    // at the panel's size and is asked for the device's.
    await subject.handleMessage(surfaces(1));
    expect(
      subject.hasPainted,
      isFalse,
      reason: 'the frame belonged to surfaces that are gone',
    );

    await subject.handleMessage(frame(1, frameId: 2));
    expect(subject.hasPainted, isTrue);
  });

  test(
    'a frame against superseded surfaces neither paints nor is marked',
    () async {
      var subject = engine();
      await subject.handleMessage(surfaces(0));
      await subject.handleMessage(surfaces(1));
      calls.clear();

      await subject.handleMessage(frame(0));
      expect(subject.hasPainted, isFalse);
      expect(calls, isEmpty, reason: 'that ring slot is no longer mapped');
    },
  );

  test('the first frame of a generation notifies, the rest do not', () async {
    var subject = engine();
    var notifications = 0;
    subject.addListener(() => notifications++);

    await subject.handleMessage(surfaces(0));
    var afterSurfaces = notifications;

    await subject.handleMessage(frame(0));
    expect(notifications, afterSurfaces + 1);

    // A guest animating at 60fps must not rebuild every listener at 60fps.
    await subject.handleMessage(frame(0, frameId: 2));
    await subject.handleMessage(frame(0, frameId: 3));
    expect(notifications, afterSurfaces + 1);
  });
}
