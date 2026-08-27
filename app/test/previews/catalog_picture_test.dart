import 'dart:typed_data';

import 'package:flutterware_app/src/previews/catalog_picture.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

/// The stage after a frame exists, tested without one being drawn.
///
/// These used to live in `frame_capture_test.dart` and reached the crop
/// through a fake socket, because the crop lived behind one. It does not any
/// more: framing a picture is the same work whichever engine drew it, so the
/// test is now what it always meant to be — pixels in, pixels out.
void main() {
  img.Image frame(int width, int height) =>
      img.Image(width: width, height: height);

  test('a crop cuts to a node box, in physical pixels', () {
    // Logical coordinates at ratio 2 — the space `InspectLayout` reports, so a
    // node rect from the panel crops its own picture untransformed.
    var image = framePicture(
      frame(20, 20),
      framing: const PictureFraming(
        crop: InspectLayout(x: 1, y: 1, width: 3, height: 2),
      ),
      pixelRatio: 2,
    );

    expect(image.width, 6);
    expect(image.height, 4);
  });

  test('a crop reaching past the frame is clamped, not refused', () {
    // What an overflow *is*, and the one case most worth being able to see.
    var image = framePicture(
      frame(10, 10),
      framing: const PictureFraming(
        crop: InspectLayout(x: 8, y: 8, width: 40, height: 40),
      ),
    );

    expect(image.width, 2);
    expect(image.height, 2);
  });

  test('nothing asked for leaves the frame alone', () {
    var original = frame(10, 10);

    expect(identical(framePicture(original), original), isTrue);
  });

  group('a tester frame', () {
    test('decodes packed rgba, rows in order', () {
      // Two pixels, red then blue. No header and no stride, which is the whole
      // difference from the embedder's `.rawframe`.
      var image = decodeTesterFrame(
        Uint8List.fromList([255, 0, 0, 255, 0, 0, 255, 255]),
        width: 2,
        height: 1,
      );

      expect(image.getPixel(0, 0).r, 255);
      expect(image.getPixel(1, 0).b, 255);
    });

    test('refuses a length the dimensions do not explain', () {
      // The one failure worth catching by hand: a truncated write decodes into
      // a picture that is simply wrong further down, where nothing says why.
      expect(
        () => decodeTesterFrame(Uint8List(7), width: 2, height: 1),
        throwsFormatException,
      );
    });
  });
}
