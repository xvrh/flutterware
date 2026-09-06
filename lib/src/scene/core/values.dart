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

/// How a text sits in the box it was given. Flutter's own names, because
/// that is what the file spells and what it becomes.
enum SceneTextAlign { left, right, center, justify }

/// A text style: the text subset of the property table, as one value — what
/// a token names and a `TextNode` takes as `style:`, so five properties are
/// shared in one move and each may still be overridden on the node.
///
/// Every field is nullable, because a style sets what it sets: a style that
/// says only `weight` leaves size and colour to the node. The rule a node
/// applies is `fontSize ?? style?.fontSize ?? 16` — the argument, then the
/// style, then the default — which is also what the file spells: a property
/// written on the node is an override, one absent is inherited, and one
/// written equal to the style's is indistinguishable from inherited and
/// follows the style (master plan §4.3, decided).
class SceneTextStyle {
  const SceneTextStyle({
    this.fontSize,
    this.weight,
    this.color,
    this.align,
    this.maxLines,
  });

  final double? fontSize;
  final SceneFontWeight? weight;
  final SceneColor? color;
  final SceneTextAlign? align;
  final int? maxLines;

  /// The properties this style sets, by the table's name — what an emitter
  /// compares a node against, and what an inspector marks as inherited.
  Map<String, Object> get values => {
    'fontSize': ?fontSize,
    'weight': ?weight,
    'color': ?color,
    'align': ?align,
    'maxLines': ?maxLines,
  };

  bool sets(String prop) => values.containsKey(prop);

  @override
  bool operator ==(Object other) =>
      other is SceneTextStyle &&
      other.fontSize == fontSize &&
      other.weight == weight &&
      other.color == color &&
      other.align == align &&
      other.maxLines == maxLines;

  @override
  int get hashCode => Object.hash(fontSize, weight, color, align, maxLines);

  @override
  String toString() =>
      'SceneTextStyle(${values.entries.map((e) => '${e.key}: ${e.value}').join(', ')})';
}

/// Four numbers that are one when they agree: edges, corners. What the
/// property table needs to spell either as one number or four named parts.
abstract interface class SceneQuad {
  /// The four parts, in the order the file names them.
  List<double> get sides;
  bool get isUniform;
  bool get isZero;
  SceneQuad withSide(int index, double value);

  /// The one number when they agree, the four otherwise.
  Object toWire();
}

/// Space inside a frame, per side.
///
/// One value where there used to be a number, because the number could only
/// ever be uniform and the renderer was quietly making the vertical inset
/// six tenths of the horizontal one — a guess that looked deliberate and was
/// not. A cell in a table wants a different top from its left.
class SceneEdges implements SceneQuad {
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

  @override
  bool get isZero => left == 0 && top == 0 && right == 0 && bottom == 0;

  /// Whether one number says all of it — what the file and the inspector
  /// offer first, because it is what most frames want.
  @override
  bool get isUniform => left == top && top == right && right == bottom;

  @override
  List<double> get sides => [left, top, right, bottom];

  @override
  SceneEdges withSide(int index, double value) => switch (index) {
    0 => copyWith(left: value),
    1 => copyWith(top: value),
    2 => copyWith(right: value),
    _ => copyWith(bottom: value),
  };

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
  @override
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

/// A node's corner radii, one per corner, clockwise from the top left.
///
/// `corner: 16` is still what most nodes want and still what the file
/// spells for them; a tab that is square along its bottom names its
/// corners, the way a padding names its sides.
class SceneCorners implements SceneQuad {
  const SceneCorners({
    this.topLeft = 0,
    this.topRight = 0,
    this.bottomRight = 0,
    this.bottomLeft = 0,
  });

  const SceneCorners.all(double value)
    : topLeft = value,
      topRight = value,
      bottomRight = value,
      bottomLeft = value;

  static const zero = SceneCorners();

  final double topLeft;
  final double topRight;
  final double bottomRight;
  final double bottomLeft;

  @override
  bool get isZero =>
      topLeft == 0 && topRight == 0 && bottomRight == 0 && bottomLeft == 0;

  @override
  bool get isUniform =>
      topLeft == topRight &&
      topRight == bottomRight &&
      bottomRight == bottomLeft;

  @override
  List<double> get sides => [topLeft, topRight, bottomRight, bottomLeft];

  SceneCorners copyWith({
    double? topLeft,
    double? topRight,
    double? bottomRight,
    double? bottomLeft,
  }) => SceneCorners(
    topLeft: topLeft ?? this.topLeft,
    topRight: topRight ?? this.topRight,
    bottomRight: bottomRight ?? this.bottomRight,
    bottomLeft: bottomLeft ?? this.bottomLeft,
  );

  @override
  SceneCorners withSide(int index, double value) => switch (index) {
    0 => copyWith(topLeft: value),
    1 => copyWith(topRight: value),
    2 => copyWith(bottomRight: value),
    _ => copyWith(bottomLeft: value),
  };

  @override
  Object toWire() =>
      isUniform ? topLeft : [topLeft, topRight, bottomRight, bottomLeft];

  static SceneCorners fromWire(Object? value) => switch (value) {
    num n => SceneCorners.all(n.toDouble()),
    List l when l.length == 4 => SceneCorners(
      topLeft: (l[0] as num).toDouble(),
      topRight: (l[1] as num).toDouble(),
      bottomRight: (l[2] as num).toDouble(),
      bottomLeft: (l[3] as num).toDouble(),
    ),
    _ => zero,
  };

  @override
  bool operator ==(Object other) =>
      other is SceneCorners &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() =>
      'SceneCorners($topLeft, $topRight, $bottomRight, $bottomLeft)';
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
