import 'dart:typed_data';

import 'package:flutterware_app/src/comparison/pixel_diff.dart';
import 'package:test/test.dart';

/// Two frames compared as pixels: the percentage for the row, the clusters for
/// the eye, and the size delta that stops a 24px shift reading as "everything
/// changed".
void main() {
  /// A [width]×[height] frame of one colour.
  Uint8List frame(int width, int height, [int value = 0]) =>
      Uint8List(width * height * 4)..fillRange(0, width * height * 4, value);

  void paint(
    Uint8List frame,
    int frameWidth,
    int x,
    int y,
    int width,
    int height,
    int value,
  ) {
    for (var row = y; row < y + height; row++) {
      for (var column = x; column < x + width; column++) {
        var index = (row * frameWidth + column) * 4;
        for (var channel = 0; channel < 4; channel++) {
          frame[index + channel] = value;
        }
      }
    }
  }

  PixelDiff diff(
    Uint8List base,
    Uint8List head, {
    int width = 40,
    int height = 40,
    int headWidth = 0,
    int headHeight = 0,
  }) => PixelDiff.of(
    base: base,
    baseWidth: width,
    baseHeight: height,
    head: head,
    headWidth: headWidth == 0 ? width : headWidth,
    headHeight: headHeight == 0 ? height : headHeight,
  );

  test('two identical frames are not a change', () {
    var result = diff(frame(40, 40), frame(40, 40));

    expect(result.changedPixels, 0);
    expect(result.fraction, 0);
    expect(result.changed, isFalse);
    expect(result.clusters, isEmpty);
  });

  // The same code rasterized twice is bit-identical; *nearly* the same code
  // repaints antialiased edges everywhere, and a 1/255 fringe is not a
  // finding.
  test('a fringe under the epsilon is not a change', () {
    var head = frame(40, 40)
      ..fillRange(0, 40 * 40 * 4, PixelDiff.channelEpsilon);

    expect(diff(frame(40, 40), head).changedPixels, 0);
  });

  test('a channel past the epsilon is a change', () {
    var head = frame(40, 40)
      ..fillRange(0, 40 * 40 * 4, PixelDiff.channelEpsilon + 1);

    expect(diff(frame(40, 40), head).changedPixels, 40 * 40);
  });

  test('a changed block is one cluster, located and measured', () {
    var head = frame(40, 40);
    paint(head, 40, 10, 12, 8, 6, 255);

    var result = diff(frame(40, 40), head);

    expect(result.changedPixels, 48);
    expect(result.clusters, hasLength(1));
    expect(result.clusters.single.x, 10);
    expect(result.clusters.single.y, 12);
    expect(result.clusters.single.width, 8);
    expect(result.clusters.single.height, 6);
    expect(result.clusters.single.pixels, 48);
  });

  test('two separated changes are two clusters, largest first', () {
    var head = frame(40, 40);
    paint(head, 40, 1, 1, 2, 2, 255);
    paint(head, 40, 20, 20, 6, 6, 255);

    var clusters = diff(frame(40, 40), head).clusters;

    expect(clusters, hasLength(2));
    expect(clusters.first.pixels, 36);
    expect(clusters.last.pixels, 4);
  });

  // A hollow change — a card border — has the changes inside it as separate
  // components, whose boxes would draw over its box.
  test('clusters whose boxes overlap are folded into one', () {
    var head = frame(40, 40);
    // A ring…
    paint(head, 40, 10, 10, 12, 1, 255);
    paint(head, 40, 10, 21, 12, 1, 255);
    paint(head, 40, 10, 10, 1, 12, 255);
    paint(head, 40, 21, 10, 1, 12, 255);
    // …and a separate change inside it.
    paint(head, 40, 14, 14, 4, 4, 255);

    var clusters = diff(frame(40, 40), head).clusters;

    expect(clusters, hasLength(1));
    var box = clusters.single;
    expect(box.x, 10);
    expect(box.y, 10);
    expect(box.width, 12);
    expect(box.height, 12);
    // The ring's 44 plus the block's 16: folding sums the real counts.
    expect(box.pixels, 60);
  });

  // Eight-connected would join two changes touching only at a corner, which
  // for antialiased text is most of them.
  test('regions touching at a corner stay two clusters', () {
    var head = frame(40, 40);
    paint(head, 40, 4, 4, 2, 2, 255);
    paint(head, 40, 6, 6, 2, 2, 255);

    expect(diff(frame(40, 40), head).clusters, hasLength(2));
  });

  // A single stray pixel is under both thresholds and no eye would find it.
  test('one pixel is below the noise floor', () {
    var head = frame(200, 200);
    paint(head, 200, 100, 100, 1, 1, 255);

    var result = diff(frame(200, 200), head, width: 200, height: 200);

    expect(result.changedPixels, 1);
    expect(result.changed, isFalse);
  });

  // A moved icon is a tiny fraction of a tall screen and is exactly what the
  // fraction threshold alone would miss.
  test('a small cluster in a large frame still counts', () {
    var head = frame(400, 800);
    paint(head, 400, 20, 20, 10, 10, 255);

    var result = diff(frame(400, 800), head, width: 400, height: 800);

    expect(result.fraction, lessThan(PixelDiff.fractionThreshold));
    expect(result.changed, isTrue);
  });

  group('a frame that changed size', () {
    // The finding is the size, not the 97%: a card that grew 24px taller
    // shifts every pixel below it, and answering "nearly everything changed"
    // is arithmetically right and useless.
    test('is a change on its own, with no changed pixels at all', () {
      var result = diff(
        frame(40, 40),
        frame(40, 64),
        headWidth: 40,
        headHeight: 64,
      );

      expect(result.sizeChanged, isTrue);
      expect(result.changed, isTrue);
      expect(result.changedPixels, 0);
    });

    test('is compared over the region the two frames share', () {
      var head = frame(40, 64);
      paint(head, 40, 0, 50, 40, 14, 255);

      var result = diff(frame(40, 40), head, headWidth: 40, headHeight: 64);

      expect(result.height, 40);
      expect(result.comparedPixels, 40 * 40);
      // The painted band is below the shared region, so it is not counted
      // twice: the size delta already says content was added down there.
      expect(result.changedPixels, 0);
    });
  });

  test('the mask is only kept when it is asked for', () {
    var head = frame(4, 4);
    paint(head, 4, 0, 0, 1, 1, 255);

    expect(
      PixelDiff.of(
        base: frame(4, 4),
        baseWidth: 4,
        baseHeight: 4,
        head: head,
        headWidth: 4,
        headHeight: 4,
      ).mask,
      isNull,
    );
    var withMask = PixelDiff.of(
      base: frame(4, 4),
      baseWidth: 4,
      baseHeight: 4,
      head: head,
      headWidth: 4,
      headHeight: 4,
      wantMask: true,
    );
    expect(withMask.mask, hasLength(16));
    expect(withMask.mask!.first, 1);
  });

  // A recursive flood fill overflows the stack on the first entry that changes
  // its background colour; this is the regression test for that.
  test(
    'a frame that changed everywhere is one cluster and does not blow up',
    () {
      var result = diff(
        frame(300, 300),
        frame(300, 300, 255),
        width: 300,
        height: 300,
      );

      expect(result.clusters, hasLength(1));
      expect(result.clusters.single.pixels, 300 * 300);
      expect(result.fraction, 1);
    },
  );
}
