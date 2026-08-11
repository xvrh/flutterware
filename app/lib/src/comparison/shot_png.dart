import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// rgba8888 rows into a PNG.
///
/// The cache stores frames unencoded because encoding is most of what a
/// capture costs — a deliberate choice `PixelDiff`'s doc comment defends. An
/// export is the one place that pays it anyway: a hosted page downloading two
/// and a half megabytes per frame is the worse deal, and an export happens
/// once where a capture happens per entry per run.
Uint8List encodeRgbaPng(
  Uint8List rgba, {
  required int width,
  required int height,
}) => img.encodePng(
  img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  ),
);
