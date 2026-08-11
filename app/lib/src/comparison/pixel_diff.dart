import 'dart:math' as math;
import 'dart:typed_data';

/// Two frames compared as pixels.
///
/// Raw rgba8888 in, never PNG: encoding is ~80% of a capture's cost at 1×, the
/// comparison reads pixels rather than files, and only the handful of pictures
/// that reach a screen are ever encoded.
///
/// The output is three things at once, computed in one pass, because they are
/// three readings of the same fact: a **percentage** for the row, **clusters**
/// for the eye and for an agent's coordinates, and — when the two frames are
/// not the same height — a **band** saying where content was inserted or
/// removed, which is the difference between "the card grew" and "everything
/// below the card changed".
class PixelDiff {
  const PixelDiff({
    required this.width,
    required this.height,
    required this.changedPixels,
    required this.comparedPixels,
    required this.clusters,
    required this.sizeChanged,
    this.mask,
  });

  /// The compared region — the smaller of the two frames in each dimension.
  final int width;
  final int height;

  final int changedPixels;

  /// How many pixels were in the compared region. The denominator, kept
  /// because [fraction] hides it and a reader deserves both.
  final int comparedPixels;

  /// Where the changes are, as rects, largest first.
  final List<DiffRect> clusters;

  /// Whether the two frames were different sizes.
  ///
  /// **Reported rather than folded into the percentage.** A card that grew
  /// 24px taller shifts every pixel below it; a diff that answers "97%
  /// changed" is arithmetically right and useless. The size delta is the
  /// finding, and the percentage below it describes only the region the two
  /// frames have in common.
  final bool sizeChanged;

  /// One byte per compared pixel, 1 where it changed. Kept only when asked
  /// for — it is the whole frame again, and nothing but a visualiser wants it.
  final Uint8List? mask;

  /// Changed pixels over compared pixels, 0..1.
  double get fraction =>
      comparedPixels == 0 ? 0 : changedPixels / comparedPixels;

  /// Whether this counts as a change at all.
  ///
  /// Two thresholds rather than one, because they catch different lies. A
  /// **fraction** alone misses a moved 8px icon in a tall screen; a **cluster**
  /// alone fires on a single stray pixel that no eye would find. Something has
  /// to pass one of them, or the pictures are the same picture.
  bool get changed =>
      sizeChanged ||
      fraction >= fractionThreshold ||
      clusters.any((c) => c.area >= clusterThreshold);

  /// A pixel counts as changed when a channel moves by more than this.
  ///
  /// Not zero: the same code rasterized twice on the same machine is
  /// bit-identical, but *nearly* the same code — a widget one logical pixel
  /// wider — repaints antialiased edges everywhere, and a 1/255 fringe is not
  /// a finding. Small enough that a real colour change never hides under it.
  static const channelEpsilon = 4;

  /// Below this fraction of the frame, the change has to earn its place with a
  /// cluster instead.
  static const fractionThreshold = 0.0005;

  /// A cluster this big is a change however small the frame's fraction.
  /// 8×8 is roughly the smallest thing a person notices moving.
  static const clusterThreshold = 64;

  /// Compares two rgba8888 buffers.
  ///
  /// Frames of different sizes are compared over their **common** region and
  /// [sizeChanged] is set; the caller decides what to say about the rest, and
  /// there is nothing sensible to say about pixels one side does not have.
  static PixelDiff of({
    required Uint8List base,
    required int baseWidth,
    required int baseHeight,
    required Uint8List head,
    required int headWidth,
    required int headHeight,
    bool wantMask = false,
  }) {
    var width = math.min(baseWidth, headWidth);
    var height = math.min(baseHeight, headHeight);
    var mask = Uint8List(width * height);
    var changed = 0;

    for (var y = 0; y < height; y++) {
      var baseRow = y * baseWidth * 4;
      var headRow = y * headWidth * 4;
      var maskRow = y * width;
      for (var x = 0; x < width; x++) {
        var b = baseRow + x * 4;
        var h = headRow + x * 4;
        if (_differs(base, b, head, h)) {
          mask[maskRow + x] = 1;
          changed++;
        }
      }
    }

    return PixelDiff(
      width: width,
      height: height,
      changedPixels: changed,
      comparedPixels: width * height,
      clusters: _clusters(mask, width, height),
      sizeChanged: baseWidth != headWidth || baseHeight != headHeight,
      mask: wantMask ? mask : null,
    );
  }

  static bool _differs(Uint8List a, int ai, Uint8List b, int bi) {
    for (var channel = 0; channel < 4; channel++) {
      if ((a[ai + channel] - b[bi + channel]).abs() > channelEpsilon) {
        return true;
      }
    }
    return false;
  }

  /// Connected components over the changed mask, merged into bounding rects.
  ///
  /// Iterative rather than recursive: a full-frame change is one component of
  /// a million pixels, and a recursive flood fill overflows the stack on the
  /// first entry that changes its background colour.
  static List<DiffRect> _clusters(Uint8List mask, int width, int height) {
    var seen = Uint8List(width * height);
    var rects = <DiffRect>[];
    var stack = <int>[];

    for (var start = 0; start < mask.length; start++) {
      if (mask[start] == 0 || seen[start] == 1) continue;
      seen[start] = 1;
      stack.add(start);
      var (minX, minY, maxX, maxY) = (
        start % width,
        start ~/ width,
        start % width,
        start ~/ width,
      );
      var area = 0;

      while (stack.isNotEmpty) {
        var index = stack.removeLast();
        var x = index % width;
        var y = index ~/ width;
        area++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;

        // Four-connected. Eight would join two changes that touch only at a
        // corner, which for antialiased text is most of them.
        for (var (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          var next = ny * width + nx;
          if (mask[next] == 0 || seen[next] == 1) continue;
          seen[next] = 1;
          stack.add(next);
        }
      }

      rects.add(
        DiffRect(
          x: minX,
          y: minY,
          width: maxX - minX + 1,
          height: maxY - minY + 1,
          pixels: area,
        ),
      );
    }

    rects.sort((a, b) => b.pixels.compareTo(a.pixels));
    return rects;
  }
}

/// One region that changed.
class DiffRect {
  static DiffRect fromJson(Map<String, Object?> json) => DiffRect(
    x: json['x'] as int? ?? 0,
    y: json['y'] as int? ?? 0,
    width: json['width'] as int? ?? 0,
    height: json['height'] as int? ?? 0,
    pixels: json['pixels'] as int? ?? 0,
  );

  const DiffRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pixels,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  /// How many pixels inside the rect actually changed. A diagonal line's
  /// bounding box is mostly untouched, and a reader ranking regions wants the
  /// count rather than the box.
  final int pixels;

  int get area => width * height;

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'pixels': pixels,
  };

  @override
  String toString() => '$x,$y $width×$height ($pixels px)';
}
