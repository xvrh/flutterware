import 'dart:math' as math;
import 'dart:typed_data';

/// Two frames compared as pixels.
///
/// Raw rgba8888 in, never PNG: the comparison reads pixels rather than files,
/// so a PNG here would be encoded on the way out and decoded straight back in.
/// Only the handful of pictures that reach a screen are ever encoded.
///
/// Measured, the encode is ~7.5ms a picture out and the decode ~0.75ms back,
/// against bytes that cost about nothing to write (489MB at ~70ms, page
/// cache). And `fw compare` is a CLI command, so the decode would have no
/// engine codec to use: it would fall to `package:image`, in pure Dart, on
/// every frame of both sides. This used to say encoding was "~80% of a
/// capture's cost", which was never measured and is not true.
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
  /// because [fraction] hides it and both are worth having.
  final int comparedPixels;

  /// Where the changes are, as rects, largest first.
  ///
  /// Never a tangle: boxes that overlap are folded into their union so none
  /// draws over another, and when there are more than [readableRegions] of
  /// them, changes near each other are grouped until there are few enough to
  /// read. So a font change over a paragraph is the paragraph, not a box per
  /// word.
  final List<DiffRect> clusters;

  /// Whether the two frames were different sizes.
  ///
  /// Reported rather than folded into the percentage. A card that grew
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

  /// How many boxes a reader can take in at once — above this, and only above
  /// this, the boxes are grouped. See [_grouped].
  ///
  /// A number, not a formula: it is the point where a picture stops pointing
  /// somewhere and starts being decorated, and no measurement of the frame
  /// decides that. Deliberately generous, because everything under it is left
  /// exactly as the components came out: five changed fields down a form are
  /// five boxes, and grouping them would lose the finding.
  static const readableRegions = 12;

  /// What grouping aims for once it is needed.
  ///
  /// Lower than [readableRegions], and the two numbers answer different
  /// questions: *when is this a tangle* and *what should be left of it*.
  /// Stopping at the first radius that merely scrapes under a dozen leaves a
  /// picture that reads as an accident — a paragraph cut into four boxes at
  /// the line the descenders happened to touch. A tangle worth grouping at all
  /// is worth grouping into the handful of blocks a person would have drawn.
  static const groupedRegions = 3;

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
  /// Grouped when there are too many boxes to read — see [_grouped].
  static List<DiffRect> _clusters(Uint8List mask, int width, int height) =>
      _grouped(mask, width, height)
        ..sort((a, b) => b.pixels.compareTo(a.pixels));

  /// The components, at the narrowest grouping radius that leaves few enough
  /// boxes to read.
  ///
  /// A change in the *font* does not move a block of pixels, it moves every
  /// glyph in it: a paragraph set 0.4px smaller shatters into a box per word,
  /// seventy of them drawn over the very text they are meant to point at.
  /// Boxes that dense are worse than no boxes at all, because a reader has to
  /// find the change inside the scribble rather than being shown it.
  ///
  /// So changes closer together than a radius count as one region, and the
  /// radius widens until few enough boxes are left. Two numbers, because they
  /// are two questions: nothing at all is grouped below [readableRegions] —
  /// every box there is exactly the component it always was — and a tangle
  /// past it is grouped down to [groupedRegions], the handful of blocks a
  /// person would have drawn.
  ///
  /// What keeps that from answering "somewhere in here": the radii stop
  /// widening ([_radii]), so however hard grouping is pushed, changes further
  /// apart than the widest of them stay separate boxes.
  ///
  /// A single box round the whole tangle then arrives on its own, without
  /// anything having to decide that a paragraph is a paragraph: it is one
  /// dense region, so it collapses to one box, while a change at each end of
  /// the frame is two and stays two.
  ///
  /// Measured on the worst frame there is — a third of a 1170×2532 screen
  /// shattered into 50,000 components — grouping takes the diff from 43ms to
  /// 185ms, in the JIT. A frame that is already readable pays nothing but the
  /// count.
  static List<DiffRect> _grouped(Uint8List mask, int width, int height) {
    var rects = _foldOverlaps(_components(mask, width, height, 0));
    if (rects.length <= readableRegions) return rects;
    for (var radius in _radii(width, height)) {
      rects = _foldOverlaps(_components(mask, width, height, radius));
      if (rects.length <= groupedRegions) break;
    }
    return rects;
  }

  /// The radii tried, narrowest first.
  ///
  /// Proportional to the frame rather than fixed, because the gap the eye
  /// reads is a fraction of the picture: the same screen captured at 3× has
  /// its word gaps three times as wide in pixels, and a constant 4px would
  /// group a paragraph at 1× and nothing at all at 3×.
  static List<int> _radii(int width, int height) {
    var unit = math.max(2, math.min(width, height) ~/ 100);
    return [unit, unit * 2, unit * 4, unit * 8];
  }

  /// Bounding rects of the connected components, taking anything within
  /// [radius] of a change to belong to the same region.
  ///
  /// The grouping is done by dilating the mask and running the components over
  /// *that*, rather than by measuring the gaps between boxes afterwards. Two
  /// reasons: a dilation is one pass over the frame however shattered the diff
  /// is, where comparing every box against every other is quadratic in exactly
  /// the case that has thousands of them; and pixels are what the eye groups —
  /// two boxes can have near edges while their changed pixels are nowhere near
  /// each other.
  ///
  /// The rects are the bounds of the **real** changed pixels, never of the
  /// dilated ones: the radius decides what belongs together, and nothing else.
  ///
  /// Iterative rather than recursive: a full-frame change is one component of
  /// a million pixels, and a recursive flood fill overflows the stack on the
  /// first entry that changes its background colour.
  static List<DiffRect> _components(
    Uint8List mask,
    int width,
    int height,
    int radius,
  ) {
    var reach = radius == 0 ? mask : _dilate(mask, width, height, radius);
    var seen = Uint8List(width * height);
    var rects = <DiffRect>[];
    var stack = <int>[];

    for (var start = 0; start < reach.length; start++) {
      if (reach[start] == 0 || seen[start] == 1) continue;
      seen[start] = 1;
      stack.add(start);
      var (minX, minY, maxX, maxY) = (width, height, -1, -1);
      var area = 0;

      while (stack.isNotEmpty) {
        var index = stack.removeLast();
        var x = index % width;
        var y = index ~/ width;
        if (mask[index] == 1) {
          area++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }

        // Four-connected. Eight would join two changes that touch only at a
        // corner, which for antialiased text is most of them.
        for (var (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          var next = ny * width + nx;
          if (reach[next] == 0 || seen[next] == 1) continue;
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

    return rects;
  }

  /// The mask grown by [radius] in every direction, so that changes with less
  /// than that between them touch.
  ///
  /// Separable — a horizontal pass then a vertical one, each carrying a
  /// running count of set pixels in the window — so the cost is two reads of
  /// the frame whatever the radius, rather than the radius squared per pixel.
  static Uint8List _dilate(Uint8List mask, int width, int height, int radius) {
    var horizontal = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      var row = y * width;
      var count = 0;
      for (var x = 0; x < width + radius; x++) {
        if (x < width && mask[row + x] == 1) count++;
        var left = x - 2 * radius - 1;
        if (left >= 0 && mask[row + left] == 1) count--;
        var centre = x - radius;
        if (centre >= 0 && count > 0) horizontal[row + centre] = 1;
      }
    }

    var dilated = Uint8List(width * height);
    for (var x = 0; x < width; x++) {
      var count = 0;
      for (var y = 0; y < height + radius; y++) {
        if (y < height && horizontal[y * width + x] == 1) count++;
        var top = y - 2 * radius - 1;
        if (top >= 0 && horizontal[top * width + x] == 1) count--;
        var centre = y - radius;
        if (centre >= 0 && count > 0) dilated[centre * width + x] = 1;
      }
    }
    return dilated;
  }

  /// Bounding rects folded together until none overlap.
  ///
  /// Components are disjoint but their boxes are not: a hollow change — a card
  /// border, a ring — has the changes inside it as separate components, whose
  /// boxes then draw *over* its box, and a reader wanting one region gets a
  /// tangle. Touching deliberately does not count as overlap: antialiased
  /// neighbours meet at edges and corners constantly, and folding those would
  /// undo exactly what four-connected components preserve.
  static List<DiffRect> _foldOverlaps(List<DiffRect> rects) {
    // Quadratic, so a diff noisy enough to shatter into thousands of
    // components keeps them as they are for this pass — grouping is what
    // answers that case, and it runs over the mask rather than over the
    // boxes.
    if (rects.length > 2048) return rects;
    var folded = List.of(rects);
    var again = true;
    while (again) {
      again = false;
      for (var i = 0; i < folded.length; i++) {
        for (var j = folded.length - 1; j > i; j--) {
          var a = folded[i];
          var b = folded[j];
          if (a.x < b.x + b.width &&
              b.x < a.x + a.width &&
              a.y < b.y + b.height &&
              b.y < a.y + a.height) {
            folded[i] = a.union(b);
            folded.removeAt(j);
            // The union may reach rects already passed over, so go again.
            again = true;
          }
        }
      }
    }
    return folded;
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

  /// The bounding box of both, their changed pixels summed — exact, because
  /// components never share a pixel.
  DiffRect union(DiffRect other) {
    var left = math.min(x, other.x);
    var top = math.min(y, other.y);
    return DiffRect(
      x: left,
      y: top,
      width: math.max(x + width, other.x + other.width) - left,
      height: math.max(y + height, other.y + other.height) - top,
      pixels: pixels + other.pixels,
    );
  }

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
