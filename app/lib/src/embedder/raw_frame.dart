import 'dart:typed_data';

import 'package:image/image.dart';

/// The header the C host writes ahead of the pixels — four little-endian
/// `uint32`s.
const _headerBytes = 16;

/// Decodes a raw frame file written by the embedder C host into an [Image].
///
/// File layout: a 16-byte little-endian header (`width`, `height`, `rowBytes`,
/// `order`) followed by `rowBytes * height` pixel bytes. `rowBytes` is a stride
/// and may exceed `width * 4`.
///
/// `order` is `0` for BGRA and `1` for RGBA, and it is in the file because the
/// guest's ring is not the same order on every host: an `IOSurface` feeding a
/// `CVPixelBuffer` is BGRA, and a GL readback feeding an
/// `FlPixelBufferTexture` is RGBA. Assuming either one produces a picture whose
/// layout, type and timing are all perfect and whose blues are orange, which is
/// a bug that survives every check but a human looking at it.
Image decodeRawFrame(Uint8List fileBytes) {
  if (fileBytes.length < _headerBytes) {
    throw FormatException(
      'Raw frame file too short: ${fileBytes.length} bytes',
    );
  }
  var header = ByteData.sublistView(fileBytes, 0, _headerBytes);
  var width = header.getUint32(0, Endian.little);
  var height = header.getUint32(4, Endian.little);
  var rowBytes = header.getUint32(8, Endian.little);
  var order = header.getUint32(12, Endian.little);

  if (rowBytes < width * 4) {
    throw FormatException(
      'Raw frame rowBytes ($rowBytes) is smaller than width*4 '
      '(${width * 4})',
    );
  }
  if (order > 1) {
    throw FormatException('Raw frame has an unknown pixel order: $order');
  }
  var expectedLength = _headerBytes + rowBytes * height;
  if (fileBytes.length != expectedLength) {
    throw FormatException(
      'Raw frame size mismatch: header implies $expectedLength bytes, '
      'file has ${fileBytes.length}',
    );
  }

  return Image.fromBytes(
    width: width,
    height: height,
    bytes: fileBytes.buffer,
    bytesOffset: fileBytes.offsetInBytes + _headerBytes,
    numChannels: 4,
    rowStride: rowBytes,
    order: order == 0 ? ChannelOrder.bgra : ChannelOrder.rgba,
  );
}
