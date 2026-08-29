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
/// A frame as the guest wrote it: the header read, the pixels untouched.
///
/// The pixels are a **view** into the file's bytes, not a copy — which is the
/// whole point of having this beside [decodeRawFrame]. Turning them into an
/// `Image` costs a full channel swizzle when the order is BGRA, measured at
/// 26ms a frame at phone resolution, and a caller handing the pixels to
/// something that can read BGRA itself pays that for nothing.
class RawFrame {
  RawFrame({
    required this.width,
    required this.height,
    required this.rowBytes,
    required this.order,
    required this.pixels,
  });

  final int width;
  final int height;

  /// The stride. May exceed `width * 4`.
  final int rowBytes;

  /// `0` for BGRA, `1` for RGBA. See [decodeRawFrame].
  final int order;

  /// `rowBytes * height` bytes, viewing the file rather than copying it.
  final Uint8List pixels;

  /// What `ffmpeg -pix_fmt` calls this order.
  String get pixelFormat => order == 0 ? 'bgra' : 'rgba';

  /// Whether rows are packed with no padding, and so can be handed on whole.
  bool get isPacked => rowBytes == width * 4;
}

/// Reads a raw frame's header and returns its pixels unconverted.
RawFrame readRawFrame(Uint8List fileBytes) {
  var header = _header(fileBytes);
  return RawFrame(
    width: header.width,
    height: header.height,
    rowBytes: header.rowBytes,
    order: header.order,
    pixels: Uint8List.sublistView(fileBytes, _headerBytes),
  );
}

({int width, int height, int rowBytes, int order}) _header(
  Uint8List fileBytes,
) {
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
  return (width: width, height: height, rowBytes: rowBytes, order: order);
}

Image decodeRawFrame(Uint8List fileBytes) {
  var (:width, :height, :rowBytes, :order) = _header(fileBytes);
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
