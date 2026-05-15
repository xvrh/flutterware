/// Integer-cell geometry for the TUI paint kit.
library;

/// A position on the cell grid. [row] grows downward, [col] grows rightward.
class CellOffset {
  final int row;
  final int col;

  const CellOffset(this.row, this.col);

  static const CellOffset zero = CellOffset(0, 0);

  CellOffset operator +(CellOffset other) =>
      CellOffset(row + other.row, col + other.col);

  CellOffset operator -(CellOffset other) =>
      CellOffset(row - other.row, col - other.col);

  @override
  bool operator ==(Object other) =>
      other is CellOffset && row == other.row && col == other.col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'CellOffset($row, $col)';
}

/// A size on the cell grid. Non-negative by convention; not enforced.
class CellSize {
  final int rows;
  final int cols;

  const CellSize(this.rows, this.cols);

  static const CellSize zero = CellSize(0, 0);

  bool get isEmpty => rows <= 0 || cols <= 0;

  @override
  bool operator ==(Object other) =>
      other is CellSize && rows == other.rows && cols == other.cols;

  @override
  int get hashCode => Object.hash(rows, cols);

  @override
  String toString() => 'CellSize($rows, $cols)';
}

/// A rectangle on the cell grid. Half-open: covers rows [top, top+height)
/// and cols [left, left+width).
class CellRect {
  final int top;
  final int left;
  final int width;
  final int height;

  /// row-first to match the (row, col) convention used everywhere else.
  const CellRect.fromTLWH(this.top, this.left, this.width, this.height);

  CellRect.fromOffsetSize(CellOffset offset, CellSize size)
      : top = offset.row,
        left = offset.col,
        width = size.cols,
        height = size.rows;

  int get bottom => top + height; // exclusive
  int get right => left + width; // exclusive
  CellOffset get offset => CellOffset(top, left);
  CellSize get size => CellSize(height, width);
  bool get isEmpty => height <= 0 || width <= 0;

  bool contains(CellOffset p) =>
      p.row >= top && p.row < bottom && p.col >= left && p.col < right;

  /// Intersection of two rects. Returns an empty rect if they do not overlap.
  CellRect intersect(CellRect other) {
    var t = top > other.top ? top : other.top;
    var l = left > other.left ? left : other.left;
    var b = bottom < other.bottom ? bottom : other.bottom;
    var r = right < other.right ? right : other.right;
    return CellRect.fromTLWH(t, l, r - l, b - t);
  }

  /// This rect translated by [delta].
  CellRect shift(CellOffset delta) =>
      CellRect.fromTLWH(top + delta.row, left + delta.col, width, height);

  /// This rect inset by [amount] cells on every side. A rect too small to
  /// inset becomes empty (clamped, never negative-sized).
  CellRect deflate(int amount) {
    var w = width - 2 * amount;
    var h = height - 2 * amount;
    return CellRect.fromTLWH(
      top + amount,
      left + amount,
      w < 0 ? 0 : w,
      h < 0 ? 0 : h,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CellRect &&
      top == other.top &&
      left == other.left &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(top, left, width, height);

  @override
  String toString() => 'CellRect.fromTLWH($top, $left, $width, $height)';
}
