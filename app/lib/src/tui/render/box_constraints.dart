part of 'render.dart';

/// Cell-space insets for the four sides of a box.
class EdgeInsets {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const EdgeInsets.fromLTRB(this.left, this.top, this.right, this.bottom);

  const EdgeInsets.all(int value)
      : left = value,
        top = value,
        right = value,
        bottom = value;

  const EdgeInsets.symmetric({int horizontal = 0, int vertical = 0})
      : left = horizontal,
        right = horizontal,
        top = vertical,
        bottom = vertical;

  const EdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  static const EdgeInsets zero = EdgeInsets.fromLTRB(0, 0, 0, 0);

  int get horizontal => left + right;
  int get vertical => top + bottom;

  @override
  bool operator ==(Object other) =>
      other is EdgeInsets &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'EdgeInsets.fromLTRB($left, $top, $right, $bottom)';
}

/// Immutable layout constraints in cells. [minWidth]/[maxWidth] are column
/// counts and [minHeight]/[maxHeight] are row counts. An axis whose max is
/// [unbounded] imposes no upper bound.
class BoxConstraints {
  final int minWidth;
  final int maxWidth;
  final int minHeight;
  final int maxHeight;

  /// Sentinel max for an unbounded axis. A large int, since cell counts are
  /// integers and there is no integer infinity.
  static const int unbounded = 1 << 30;

  const BoxConstraints({
    this.minWidth = 0,
    this.maxWidth = unbounded,
    this.minHeight = 0,
    this.maxHeight = unbounded,
  });

  /// Requires exactly [size].
  BoxConstraints.tight(CellSize size)
      : minWidth = size.cols,
        maxWidth = size.cols,
        minHeight = size.rows,
        maxHeight = size.rows;

  /// Tight on the axes given a value; unbounded on the others.
  const BoxConstraints.tightFor({int? width, int? height})
      : minWidth = width ?? 0,
        maxWidth = width ?? unbounded,
        minHeight = height ?? 0,
        maxHeight = height ?? unbounded;

  /// Allows any size up to [size].
  BoxConstraints.loose(CellSize size)
      : minWidth = 0,
        maxWidth = size.cols,
        minHeight = 0,
        maxHeight = size.rows;

  bool get hasBoundedWidth => maxWidth < unbounded;
  bool get hasBoundedHeight => maxHeight < unbounded;
  bool get isTight => minWidth == maxWidth && minHeight == maxHeight;

  /// The largest allowed size (axes clamped to a real number if unbounded).
  CellSize get biggest => CellSize(constrainHeight(), constrainWidth());

  /// The smallest allowed size.
  CellSize get smallest => CellSize(minHeight, minWidth);

  int constrainWidth([int width = unbounded]) =>
      width.clamp(minWidth, maxWidth);

  int constrainHeight([int height = unbounded]) =>
      height.clamp(minHeight, maxHeight);

  /// Clamps [size] into the allowed range.
  CellSize constrain(CellSize size) =>
      CellSize(constrainHeight(size.rows), constrainWidth(size.cols));

  /// Shrinks the constraints by [insets] on all sides; min clamps at 0 and
  /// max never drops below the resulting min. Unbounded axes stay unbounded.
  BoxConstraints deflate(EdgeInsets insets) {
    var h = insets.horizontal;
    var v = insets.vertical;
    var dMinW = minWidth - h < 0 ? 0 : minWidth - h;
    var dMinH = minHeight - v < 0 ? 0 : minHeight - v;
    var dMaxW = maxWidth >= unbounded
        ? unbounded
        : (maxWidth - h < dMinW ? dMinW : maxWidth - h);
    var dMaxH = maxHeight >= unbounded
        ? unbounded
        : (maxHeight - v < dMinH ? dMinH : maxHeight - v);
    return BoxConstraints(
      minWidth: dMinW,
      maxWidth: dMaxW,
      minHeight: dMinH,
      maxHeight: dMaxH,
    );
  }

  /// Drops the minimums to zero.
  BoxConstraints loosen() => BoxConstraints(
        minWidth: 0,
        maxWidth: maxWidth,
        minHeight: 0,
        maxHeight: maxHeight,
      );

  /// Clamps every bound into [parent]'s range.
  BoxConstraints enforce(BoxConstraints parent) => BoxConstraints(
        minWidth: minWidth.clamp(parent.minWidth, parent.maxWidth),
        maxWidth: maxWidth.clamp(parent.minWidth, parent.maxWidth),
        minHeight: minHeight.clamp(parent.minHeight, parent.maxHeight),
        maxHeight: maxHeight.clamp(parent.minHeight, parent.maxHeight),
      );

  @override
  bool operator ==(Object other) =>
      other is BoxConstraints &&
      minWidth == other.minWidth &&
      maxWidth == other.maxWidth &&
      minHeight == other.minHeight &&
      maxHeight == other.maxHeight;

  @override
  int get hashCode => Object.hash(minWidth, maxWidth, minHeight, maxHeight);

  @override
  String toString() =>
      'BoxConstraints(w: $minWidth..$maxWidth, h: $minHeight..$maxHeight)';
}
