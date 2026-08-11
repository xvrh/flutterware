import 'dart:typed_data';
import 'dart:ui' as ui;

import 'frame_ref.dart';

/// One frame, decoded once and kept.
class Shot {
  const Shot(this.image);

  final ui.Image image;

  double get aspect => image.width / image.height;
}

/// Where a comparison's pictures are opened from.
///
/// The verdict names its frames two ways — a preview row by `ShotCache` key, a
/// scenario step by [FrameRef] — and *whose* bytes those name is the only thing
/// that differs between the two places the comparison widgets run: the panel
/// reads the machine's shot cache off disk, the exported page fetches PNGs
/// from wherever it was served. Everything above this interface is the same
/// code. The same seam `ScenarioArtifacts` cut for the scenario page, cut here
/// for the same reason.
///
/// Absence is a null, never an exception: a row whose frames have been evicted
/// must still open, saying the picture is gone.
abstract interface class ShotStore {
  /// The frame a preview row filed, by `ShotCache` key — or, on an exported
  /// page, by the relative path the export rewrote the key into.
  Future<Shot?> byKey(String key);

  /// The frame a replay wrote, by [FrameRef].
  Future<Shot?> byRef(FrameRef ref);
}

/// rgba8888 rows into a texture.
///
/// **Raw straight to a texture, never through a PNG.** Frames are stored
/// unencoded precisely because encoding is most of what a capture costs;
/// re-encoding to hand `Image.memory` something it recognises would pay that
/// price back, per frame, on every click in a list.
Future<Shot?> decodeRawShot(
  Uint8List bytes, {
  required int width,
  required int height,
}) async {
  if (width <= 0 || height <= 0) return null;
  var buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  var descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  var codec = await descriptor.instantiateCodec();
  var frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return Shot(frame.image);
}

/// An encoded image — the PNG case, which is what an export ships because a
/// hosted page should not download two and a half megabytes per frame.
Future<Shot?> decodeEncodedShot(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  try {
    var codec = await ui.instantiateImageCodec(bytes);
    var frame = await codec.getNextFrame();
    codec.dispose();
    return Shot(frame.image);
  } on Object {
    return null;
  }
}
