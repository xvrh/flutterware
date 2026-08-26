import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/opaque_png.dart';
import 'package:image/image.dart' as img;

/// Google Play takes "JPEG or 24-bit PNG (no alpha)", and a scenario capture is
/// always RGBA — `Image.toByteData(format: png)` gives no other shape. So the
/// store lane's last act before writing a file is to take the alpha channel
/// off, and the only interesting question is what happens underneath a pixel
/// that was actually transparent.
void main() {
  Uint8List rgbaPng({required int alpha}) => img.encodePng(
    img.Image(width: 4, height: 4, numChannels: 4)
      ..clear(img.ColorRgba8(255, 0, 0, alpha)),
  );

  test('takes the alpha channel off a capture', () {
    var flattened = img.decodePng(flattenPng(rgbaPng(alpha: 255)))!;
    expect(flattened.numChannels, 3);
    var pixel = flattened.getPixel(0, 0);
    expect([pixel.r, pixel.g, pixel.b], [255, 0, 0]);
  });

  test('composites a transparent pixel over the ground rather than dropping '
      'the channel under it', () {
    // The failure this exists to prevent: strip the channel instead of
    // compositing and a fully transparent pixel keeps whatever RGB sat under
    // it, which is usually black — so a screen the app had not finished
    // painting ships with black holes where the viewer saw white.
    var flattened = img.decodePng(flattenPng(rgbaPng(alpha: 0)))!;
    var pixel = flattened.getPixel(0, 0);
    expect([pixel.r, pixel.g, pixel.b], [255, 255, 255]);
  });

  test('composites half-transparency proportionally', () {
    var flattened = img.decodePng(flattenPng(rgbaPng(alpha: 128)))!;
    var pixel = flattened.getPixel(0, 0);
    expect(pixel.r, 255);
    expect(pixel.g, closeTo(127, 2));
    expect(pixel.b, closeTo(127, 2));
  });

  test('hands back a PNG that already has no alpha untouched', () {
    var already = img.encodePng(
      img.Image(width: 2, height: 2, numChannels: 3)
        ..clear(img.ColorRgb8(1, 2, 3)),
    );
    expect(flattenPng(already), same(already));
  });

  test('hands back bytes it cannot decode rather than corrupting them', () {
    var notAPng = Uint8List.fromList([1, 2, 3, 4]);
    expect(flattenPng(notAPng), same(notAPng));
  });
}
