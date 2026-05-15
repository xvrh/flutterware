import 'dart:convert';
import 'dart:typed_data';

/// Wire protocol shared with the embedder guest process (`app/native/`).
///
/// Each frame on the socket is `[uint32 LE length][uint8 type][payload]`,
/// where `length` counts the type byte plus the payload. Integers are
/// little-endian; doubles are IEEE-754 little-endian.

/// Message type tags. Must match the `kMsg*` enum in `app/native/ipc.h`.
enum MessageType {
  ready(1),
  surfacesAllocated(2),
  frameReady(3),
  error(4),
  resize(5),
  pointerEvent(6),
  keyEvent(7),
  shutdown(8);

  const MessageType(this.tag);
  final int tag;

  static MessageType fromTag(int tag) => values.firstWhere(
        (t) => t.tag == tag,
        orElse: () => throw FormatException('Unknown message tag: $tag'),
      );
}

/// Pointer phases; the index order matches `FlutterPointerPhase` in
/// `flutter_embedder.h` so the guest can cast the index directly.
enum PointerPhase { cancel, up, down, move, add, remove, hover }

enum KeyEventKind { down, up, repeat }

sealed class EmbedderMessage {
  const EmbedderMessage();
}

class ReadyMessage extends EmbedderMessage {
  const ReadyMessage();
}

class SurfacesAllocatedMessage extends EmbedderMessage {
  const SurfacesAllocatedMessage({
    required this.generation,
    required this.width,
    required this.height,
    required this.rowBytes,
    required this.surfaceIds,
  });

  final int generation;
  final int width;
  final int height;
  final int rowBytes;
  final List<int> surfaceIds;
}

class FrameReadyMessage extends EmbedderMessage {
  const FrameReadyMessage({required this.ringIndex, required this.frameId});

  final int ringIndex;
  final int frameId;
}

class ErrorMessage extends EmbedderMessage {
  const ErrorMessage(this.message);

  final String message;
}

class ResizeMessage extends EmbedderMessage {
  const ResizeMessage({
    required this.width,
    required this.height,
    required this.pixelRatio,
  });

  final int width;
  final int height;
  final double pixelRatio;
}

class PointerEventMessage extends EmbedderMessage {
  const PointerEventMessage({
    required this.phase,
    required this.x,
    required this.y,
    required this.buttons,
    required this.scrollDeltaX,
    required this.scrollDeltaY,
    required this.timestampMicros,
  });

  final PointerPhase phase;
  final double x;
  final double y;
  final int buttons;
  final double scrollDeltaX;
  final double scrollDeltaY;
  final int timestampMicros;
}

class KeyEventMessage extends EmbedderMessage {
  const KeyEventMessage({
    required this.kind,
    required this.physicalKey,
    required this.logicalKey,
    required this.modifiers,
    required this.timestampMicros,
  });

  final KeyEventKind kind;
  final int physicalKey;
  final int logicalKey;
  final int modifiers;
  final int timestampMicros;
}

class ShutdownMessage extends EmbedderMessage {
  const ShutdownMessage();
}

void _u32(BytesBuilder b, int value) {
  var d = ByteData(4)..setUint32(0, value, Endian.little);
  b.add(d.buffer.asUint8List());
}

void _u64(BytesBuilder b, int value) {
  var d = ByteData(8)..setUint64(0, value, Endian.little);
  b.add(d.buffer.asUint8List());
}

void _f64(BytesBuilder b, double value) {
  var d = ByteData(8)..setFloat64(0, value, Endian.little);
  b.add(d.buffer.asUint8List());
}

/// Encodes [message] into a complete wire frame (length prefix included).
Uint8List encodeMessage(EmbedderMessage message) {
  var body = BytesBuilder();
  switch (message) {
    case ReadyMessage():
      body.addByte(MessageType.ready.tag);
    case SurfacesAllocatedMessage():
      body.addByte(MessageType.surfacesAllocated.tag);
      _u32(body, message.generation);
      _u32(body, message.surfaceIds.length);
      _u32(body, message.width);
      _u32(body, message.height);
      _u32(body, message.rowBytes);
      for (var id in message.surfaceIds) {
        _u32(body, id);
      }
    case FrameReadyMessage():
      body.addByte(MessageType.frameReady.tag);
      _u32(body, message.ringIndex);
      _u64(body, message.frameId);
    case ErrorMessage():
      body.addByte(MessageType.error.tag);
      var bytes = utf8.encode(message.message);
      _u32(body, bytes.length);
      body.add(bytes);
    case ResizeMessage():
      body.addByte(MessageType.resize.tag);
      _u32(body, message.width);
      _u32(body, message.height);
      _f64(body, message.pixelRatio);
    case PointerEventMessage():
      body.addByte(MessageType.pointerEvent.tag);
      _u32(body, message.phase.index);
      _f64(body, message.x);
      _f64(body, message.y);
      _u32(body, message.buttons);
      _f64(body, message.scrollDeltaX);
      _f64(body, message.scrollDeltaY);
      _u64(body, message.timestampMicros);
    case KeyEventMessage():
      body.addByte(MessageType.keyEvent.tag);
      _u32(body, message.kind.index);
      _u64(body, message.physicalKey);
      _u64(body, message.logicalKey);
      _u32(body, message.modifiers);
      _u64(body, message.timestampMicros);
    case ShutdownMessage():
      body.addByte(MessageType.shutdown.tag);
  }
  var bodyBytes = body.toBytes();
  var frame = BytesBuilder();
  _u32(frame, bodyBytes.length);
  frame.add(bodyBytes);
  return frame.toBytes();
}

/// Decodes one frame body (`[uint8 type][payload]`, no length prefix).
EmbedderMessage decodeMessageBody(Uint8List body) {
  if (body.isEmpty) {
    throw FormatException('Empty message body');
  }
  var type = MessageType.fromTag(body[0]);
  var data = ByteData.sublistView(body, 1);
  switch (type) {
    case MessageType.ready:
      return const ReadyMessage();
    case MessageType.shutdown:
      return const ShutdownMessage();
    case MessageType.surfacesAllocated:
      var generation = data.getUint32(0, Endian.little);
      var count = data.getUint32(4, Endian.little);
      var width = data.getUint32(8, Endian.little);
      var height = data.getUint32(12, Endian.little);
      var rowBytes = data.getUint32(16, Endian.little);
      var ids = [
        for (var i = 0; i < count; i++)
          data.getUint32(20 + i * 4, Endian.little),
      ];
      return SurfacesAllocatedMessage(
        generation: generation,
        width: width,
        height: height,
        rowBytes: rowBytes,
        surfaceIds: ids,
      );
    case MessageType.frameReady:
      return FrameReadyMessage(
        ringIndex: data.getUint32(0, Endian.little),
        frameId: data.getUint64(4, Endian.little),
      );
    case MessageType.error:
      var len = data.getUint32(0, Endian.little);
      var text = utf8.decode(body.sublist(1 + 4, 1 + 4 + len));
      return ErrorMessage(text);
    case MessageType.resize:
      return ResizeMessage(
        width: data.getUint32(0, Endian.little),
        height: data.getUint32(4, Endian.little),
        pixelRatio: data.getFloat64(8, Endian.little),
      );
    case MessageType.pointerEvent:
      return PointerEventMessage(
        phase: PointerPhase.values[data.getUint32(0, Endian.little)],
        x: data.getFloat64(4, Endian.little),
        y: data.getFloat64(12, Endian.little),
        buttons: data.getUint32(20, Endian.little),
        scrollDeltaX: data.getFloat64(24, Endian.little),
        scrollDeltaY: data.getFloat64(32, Endian.little),
        timestampMicros: data.getUint64(40, Endian.little),
      );
    case MessageType.keyEvent:
      return KeyEventMessage(
        kind: KeyEventKind.values[data.getUint32(0, Endian.little)],
        physicalKey: data.getUint64(4, Endian.little),
        logicalKey: data.getUint64(12, Endian.little),
        modifiers: data.getUint32(20, Endian.little),
        timestampMicros: data.getUint64(24, Endian.little),
      );
  }
}

/// Accumulates socket bytes and yields complete messages as frames arrive.
class FrameReader {
  final BytesBuilder _buffer = BytesBuilder();

  Iterable<EmbedderMessage> addBytes(List<int> chunk) sync* {
    _buffer.add(chunk);
    var data = _buffer.toBytes();
    var offset = 0;
    while (data.length - offset >= 4) {
      var len = ByteData.sublistView(data, offset, offset + 4)
          .getUint32(0, Endian.little);
      if (data.length - offset - 4 < len) break;
      var bodyStart = offset + 4;
      yield decodeMessageBody(
          Uint8List.sublistView(data, bodyStart, bodyStart + len));
      offset = bodyStart + len;
    }
    _buffer.clear();
    if (offset < data.length) {
      _buffer.add(data.sublist(offset));
    }
  }
}
