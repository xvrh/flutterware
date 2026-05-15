import 'dart:typed_data';

import 'package:image/image.dart';

/// Decodes a raw frame file written by the embedder C host into an [Image].
///
/// File layout: a 12-byte little-endian header (`width`, `height`, `rowBytes`
/// as `uint32`) followed by `rowBytes * height` pixel bytes in BGRA order.
/// `rowBytes` is a stride and may exceed `width * 4`.
Image decodeRawFrame(Uint8List fileBytes) {
  if (fileBytes.length < 12) {
    throw FormatException(
        'Raw frame file too short: ${fileBytes.length} bytes');
  }
  var header = ByteData.sublistView(fileBytes, 0, 12);
  var width = header.getUint32(0, Endian.little);
  var height = header.getUint32(4, Endian.little);
  var rowBytes = header.getUint32(8, Endian.little);

  if (rowBytes < width * 4) {
    throw FormatException(
        'Raw frame rowBytes ($rowBytes) is smaller than width*4 '
        '(${width * 4})');
  }
  var expectedLength = 12 + rowBytes * height;
  if (fileBytes.length != expectedLength) {
    throw FormatException(
        'Raw frame size mismatch: header implies $expectedLength bytes, '
        'file has ${fileBytes.length}');
  }

  return Image.fromBytes(
    width: width,
    height: height,
    bytes: fileBytes.buffer,
    bytesOffset: fileBytes.offsetInBytes + 12,
    numChannels: 4,
    rowStride: rowBytes,
    order: ChannelOrder.bgra,
  );
}
