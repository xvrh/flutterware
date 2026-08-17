import 'dart:io';
import 'dart:typed_data';

/// A PNG of [width]×[height], built here rather than committed.
///
/// A raster asset big enough to be worth decoding is a few hundred kilobytes,
/// and this package publishes everything it ships — so the fixture is a
/// function. What matters to the tests that use it is the pixel count, which is
/// what the engine's decode is paid by; the bytes are gently patterned so the
/// file is neither a solid colour nor incompressible noise.
Uint8List rasterFixture(int width, int height) {
  var stride = width * 3 + 1;
  var raw = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    var row = y * stride + 1;
    for (var x = 0; x < width; x++) {
      var i = row + x * 3;
      raw[i] = (x * 7) & 0xff;
      raw[i + 1] = (y * 11) & 0xff;
      raw[i + 2] = (x + y) & 0xff;
    }
  }
  var png = BytesBuilder();
  png.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    var body = <int>[...type.codeUnits, ...data];
    png.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
    png.add(body);
    png.add((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
  }

  var header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bits per channel
    ..setUint8(9, 2); // truecolour, no alpha
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibCodec(level: 1).encode(raw));
  chunk('IEND', const []);
  return png.takeBytes();
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (var b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
