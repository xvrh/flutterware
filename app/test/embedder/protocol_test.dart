import 'dart:typed_data';

import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:test/test.dart';

void main() {
  T roundTrip<T extends EmbedderMessage>(T message) {
    var reader = FrameReader();
    var decoded = reader.addBytes(encodeMessage(message)).toList();
    expect(decoded, hasLength(1));
    return decoded.single as T;
  }

  test('round-trips Ready', () {
    expect(roundTrip(const ReadyMessage()), isA<ReadyMessage>());
  });

  test('round-trips Shutdown', () {
    expect(roundTrip(const ShutdownMessage()), isA<ShutdownMessage>());
  });

  test('round-trips SurfacesAllocated', () {
    var msg = roundTrip(const SurfacesAllocatedMessage(
      generation: 7,
      width: 800,
      height: 600,
      rowBytes: 3200,
      surfaceIds: [11, 22, 33],
    ));
    expect(msg.generation, 7);
    expect(msg.width, 800);
    expect(msg.height, 600);
    expect(msg.rowBytes, 3200);
    expect(msg.surfaceIds, [11, 22, 33]);
  });

  test('round-trips FrameReady with a large frameId', () {
    var msg =
        roundTrip(const FrameReadyMessage(ringIndex: 2, frameId: 0x100000001));
    expect(msg.ringIndex, 2);
    expect(msg.frameId, 0x100000001);
  });

  test('round-trips Error', () {
    var msg = roundTrip(const ErrorMessage('engine failed: 42'));
    expect(msg.message, 'engine failed: 42');
  });

  test('round-trips Resize', () {
    var msg = roundTrip(
        const ResizeMessage(width: 1024, height: 768, pixelRatio: 2.0));
    expect(msg.width, 1024);
    expect(msg.height, 768);
    expect(msg.pixelRatio, 2.0);
  });

  test('round-trips PointerEvent', () {
    var msg = roundTrip(const PointerEventMessage(
      phase: PointerPhase.down,
      x: 12.5,
      y: 64.25,
      buttons: 1,
      scrollDeltaX: 0.0,
      scrollDeltaY: -3.5,
      timestampMicros: 123456,
    ));
    expect(msg.phase, PointerPhase.down);
    expect(msg.x, 12.5);
    expect(msg.y, 64.25);
    expect(msg.buttons, 1);
    expect(msg.scrollDeltaY, -3.5);
    expect(msg.timestampMicros, 123456);
  });

  test('round-trips KeyEvent', () {
    var msg = roundTrip(const KeyEventMessage(
      kind: KeyEventKind.down,
      physicalKey: 0x00070004,
      logicalKey: 0x00000061,
      modifiers: 0,
      timestampMicros: 999,
    ));
    expect(msg.kind, KeyEventKind.down);
    expect(msg.physicalKey, 0x00070004);
    expect(msg.logicalKey, 0x00000061);
    expect(msg.timestampMicros, 999);
  });

  test('FrameReader splits two concatenated frames', () {
    var bytes = BytesBuilder()
      ..add(encodeMessage(const ReadyMessage()))
      ..add(encodeMessage(const FrameReadyMessage(ringIndex: 0, frameId: 1)));
    var decoded = FrameReader().addBytes(bytes.toBytes()).toList();
    expect(decoded, hasLength(2));
    expect(decoded[0], isA<ReadyMessage>());
    expect(decoded[1], isA<FrameReadyMessage>());
  });

  test('FrameReader reassembles a frame delivered byte by byte', () {
    var frame =
        encodeMessage(const FrameReadyMessage(ringIndex: 1, frameId: 9));
    var reader = FrameReader();
    var decoded = <EmbedderMessage>[];
    for (var b in frame) {
      decoded.addAll(reader.addBytes([b]));
    }
    expect(decoded, hasLength(1));
    expect((decoded.single as FrameReadyMessage).frameId, 9);
  });

  test('decodeMessageBody rejects an unknown type tag', () {
    expect(() => decodeMessageBody(Uint8List.fromList([0xFF])),
        throwsFormatException);
  });
}
