import 'dart:typed_data';

import 'package:flutterware_app/src/embedder/raw_frame.dart';
import 'package:test/test.dart';

/// Builds a raw frame file: 12-byte LE header + [pixels].
Uint8List _rawFrame(int width, int height, int rowBytes, List<int> pixels) {
  var header = ByteData(12)
    ..setUint32(0, width, Endian.little)
    ..setUint32(4, height, Endian.little)
    ..setUint32(8, rowBytes, Endian.little);
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(pixels))
      .toBytes();
}

void main() {
  test('decodes a tight 2x1 RGBA buffer', () {
    // Pixel 0 = blue (B=255), pixel 1 = red (R=255), RGBA byte order.
    var pixels = [0, 0, 255, 255, 255, 0, 0, 255];
    var image = decodeRawFrame(_rawFrame(2, 1, 8, pixels));

    expect(image.width, 2);
    expect(image.height, 1);
    var p0 = image.getPixel(0, 0);
    expect(p0.r.toInt(), 0);
    expect(p0.g.toInt(), 0);
    expect(p0.b.toInt(), 255);
    var p1 = image.getPixel(1, 0);
    expect(p1.r.toInt(), 255);
    expect(p1.g.toInt(), 0);
    expect(p1.b.toInt(), 0);
  });

  test('honours row-stride padding', () {
    // 1x2 image, rowBytes 8 = 4 pixel bytes + 4 padding bytes per row.
    var row0 = [0, 0, 255, 255, 9, 9, 9, 9]; // blue + padding (RGBA)
    var row1 = [255, 0, 0, 255, 9, 9, 9, 9]; // red + padding (RGBA)
    var image = decodeRawFrame(_rawFrame(1, 2, 8, [...row0, ...row1]));

    expect(image.width, 1);
    expect(image.height, 2);
    var top = image.getPixel(0, 0);
    expect(top.b.toInt(), 255);
    var bottom = image.getPixel(0, 1);
    expect(bottom.r.toInt(), 255);
  });

  test('rejects a truncated file (shorter than the header)', () {
    expect(() => decodeRawFrame(Uint8List(6)), throwsFormatException);
  });

  test('rejects a payload size mismatch', () {
    // Header declares 2x1 with rowBytes 8 (16 payload bytes); supply 4.
    expect(() => decodeRawFrame(_rawFrame(2, 1, 8, [0, 0, 0, 0])),
        throwsFormatException);
  });
}
