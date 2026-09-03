// The scene core's own value vocabulary — the graduation decision
// (2026-09-01-scene-graduation-plan.md): the grammar's allowlist as real
// types, so the model and both grammars stay pure Dart and the whole
// headless surface (fw scene check, MCP tools, codemods) needs no Flutter.
// The *file* spellings (`Color(0xFF…)`, `FontWeight.w700`) are the grammar's
// canon and unchanged; these are the values they parse into. The Flutter
// half converts at the edge (lib/src/scene/flutter_bridge.dart), where a
// test holds every enum's order to Flutter's.

/// An ARGB color. Files spell it `Color(0xAARRGGBB)` — the only accepted
/// color spelling; the mirror carries exactly that.
class SceneColor {
  const SceneColor(this.argb);

  final int argb;

  int get alpha => (argb >> 24) & 0xFF;
  int get red => (argb >> 16) & 0xFF;
  int get green => (argb >> 8) & 0xFF;
  int get blue => argb & 0xFF;

  static SceneColor lerp(SceneColor a, SceneColor b, double t) {
    int ch(int x, int y) => (x + (y - x) * t).round().clamp(0, 255);
    return SceneColor(
      (ch(a.alpha, b.alpha) << 24) |
          (ch(a.red, b.red) << 16) |
          (ch(a.green, b.green) << 8) |
          ch(a.blue, b.blue),
    );
  }

  @override
  bool operator ==(Object other) => other is SceneColor && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() =>
      'Color(0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()})';
}

/// The nine weights, file-spelled `FontWeight.w<value>`.
class SceneFontWeight {
  const SceneFontWeight._(this.index, this.value);

  /// Position in [values] — the wire carries this, and the bridge test pins
  /// it to Flutter's `FontWeight.values` order.
  final int index;

  /// The numeric weight (100–900) the file spells.
  final int value;

  static const w100 = SceneFontWeight._(0, 100);
  static const w200 = SceneFontWeight._(1, 200);
  static const w300 = SceneFontWeight._(2, 300);
  static const w400 = SceneFontWeight._(3, 400);
  static const w500 = SceneFontWeight._(4, 500);
  static const w600 = SceneFontWeight._(5, 600);
  static const w700 = SceneFontWeight._(6, 700);
  static const w800 = SceneFontWeight._(7, 800);
  static const w900 = SceneFontWeight._(8, 900);

  static const values = [w100, w200, w300, w400, w500, w600, w700, w800, w900];

  @override
  String toString() => 'FontWeight.w$value';
}

/// File-spelled `CrossAxisAlignment.<name>`; declaration order matches
/// Flutter's, because the wire carries the index.
enum SceneCrossAxisAlignment { start, end, center, stretch, baseline }

/// Space inside a frame, per side.
///
/// One value where there used to be a number, because the number could only
/// ever be uniform and the renderer was quietly making the vertical inset
/// six tenths of the horizontal one — a guess that looked deliberate and was
/// not. A cell in a table wants a different top from its left.
class SceneEdges {
  const SceneEdges({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  const SceneEdges.all(double value)
    : left = value,
      top = value,
      right = value,
      bottom = value;

  static const zero = SceneEdges();

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isZero => left == 0 && top == 0 && right == 0 && bottom == 0;

  /// Whether one number says all of it — what the file and the inspector
  /// offer first, because it is what most frames want.
  bool get isUniform => left == top && top == right && right == bottom;

  SceneEdges copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) => SceneEdges(
    left: left ?? this.left,
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
  );

  /// `[l, t, r, b]`, or the one number when they agree.
  Object toWire() => isUniform ? left : [left, top, right, bottom];

  /// Reads [toWire], and the plain number older payloads carried.
  static SceneEdges fromWire(Object? value) => switch (value) {
    num n => SceneEdges.all(n.toDouble()),
    List l when l.length == 4 => SceneEdges(
      left: (l[0] as num).toDouble(),
      top: (l[1] as num).toDouble(),
      right: (l[2] as num).toDouble(),
      bottom: (l[3] as num).toDouble(),
    ),
    _ => zero,
  };

  @override
  bool operator ==(Object other) =>
      other is SceneEdges &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'SceneEdges($left, $top, $right, $bottom)';
}

/// A size on its way out to the wire or a file.
///
/// Fill is [double.infinity] in the model, and `jsonEncode` refuses a
/// non-finite double, so it travels as a word. Hug is still null and a fixed
/// size is still its number.
Object? sizeToWire(double? size) =>
    size != null && size.isInfinite ? 'fill' : size;

/// The inverse of [sizeToWire].
double? sizeFromWire(Object? value) => switch (value) {
  'fill' => double.infinity,
  num n => n.toDouble(),
  _ => null,
};

/// Same contract as [SceneCrossAxisAlignment], for the main axis.
enum SceneMainAxisAlignment {
  start,
  end,
  center,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

/// A laid-out rectangle in artboard coordinates — what the renderer measured,
/// never something a file spells.
class SceneRect {
  const SceneRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  bool contains(double x, double y) =>
      x >= left && x < right && y >= top && y < bottom;

  bool overlaps(SceneRect other) =>
      other.left < right &&
      other.right > left &&
      other.top < bottom &&
      other.bottom > top;

  @override
  bool operator ==(Object other) =>
      other is SceneRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'SceneRect($left, $top, $width, $height)';
}
