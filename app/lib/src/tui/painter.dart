import 'buffer.dart';
import 'cell.dart';
import 'geometry.dart';
import 'text_wrap.dart';

/// Horizontal placement of text within a rect.
enum HorizontalAlign { left, center, right }

/// Vertical placement of text within a rect.
enum VerticalAlign { top, center, bottom }

/// The six glyphs that make up a box border.
class BorderChars {
  final String topLeft;
  final String topRight;
  final String bottomLeft;
  final String bottomRight;
  final String horizontal; // top and bottom edges
  final String vertical; // left and right edges

  const BorderChars({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.horizontal,
    required this.vertical,
  });

  const BorderChars.single()
      : topLeft = '┌',
        topRight = '┐',
        bottomLeft = '└',
        bottomRight = '┘',
        horizontal = '─',
        vertical = '│';

  const BorderChars.double()
      : topLeft = '╔',
        topRight = '╗',
        bottomLeft = '╚',
        bottomRight = '╝',
        horizontal = '═',
        vertical = '║';

  const BorderChars.rounded()
      : topLeft = '╭',
        topRight = '╮',
        bottomLeft = '╰',
        bottomRight = '╯',
        horizontal = '─',
        vertical = '│';

  const BorderChars.thick()
      : topLeft = '┏',
        topRight = '┓',
        bottomLeft = '┗',
        bottomRight = '┛',
        horizontal = '━',
        vertical = '┃';

  const BorderChars.ascii()
      : topLeft = '+',
        topRight = '+',
        bottomLeft = '+',
        bottomRight = '+',
        horizontal = '-',
        vertical = '|';
}

/// A drawing surface over a [CellBuffer], carrying a translation [_origin] and
/// a [_clip] rectangle (both in buffer coordinates).
///
/// [translate] and [clip] return new [Painter]s that share the same buffer —
/// the functional "shared canvas with an offset" model. Every write routes
/// through [_put], so content outside the clip can never be painted.
class Painter {
  final CellBuffer _buffer;
  final CellOffset _origin;
  final CellRect _clip;

  /// A painter over the whole [buffer]: identity offset, clip = full buffer.
  Painter(CellBuffer buffer)
      : _buffer = buffer,
        _origin = CellOffset.zero,
        _clip = CellRect.fromTLWH(0, 0, buffer.cols, buffer.rows);

  Painter._(this._buffer, this._origin, this._clip);

  /// The visible region in *local* coordinates (the clip, un-shifted by the
  /// origin). Helpers that fill "everything" target this.
  CellRect get bounds => _clip.shift(CellOffset(-_origin.row, -_origin.col));

  /// A painter whose local origin is shifted by [offset].
  Painter translate(CellOffset offset) =>
      Painter._(_buffer, _origin + offset, _clip);

  /// A painter clipped to [rect] (in local coordinates), intersected with the
  /// current clip.
  Painter clip(CellRect rect) =>
      Painter._(_buffer, _origin, _clip.intersect(rect.shift(_origin)));

  /// The single write chokepoint: translate local coords by the origin, drop
  /// anything outside the clip, otherwise write to the buffer.
  void _put(int row, int col, Cell cell) {
    var r = row + _origin.row;
    var c = col + _origin.col;
    if (r < _clip.top || r >= _clip.bottom) return;
    if (c < _clip.left || c >= _clip.right) return;
    _buffer.set(r, c, cell);
  }

  /// Fill the entire visible region with [cell].
  void fill(Cell cell) => fillRect(bounds, cell);

  /// Fill [rect] (local coordinates) with [cell].
  void fillRect(CellRect rect, Cell cell) {
    for (var r = rect.top; r < rect.bottom; r++) {
      for (var c = rect.left; c < rect.right; c++) {
        _put(r, c, cell);
      }
    }
  }

  /// Draw a horizontal run of [length] cells starting at [start].
  void drawHLine(
    CellOffset start,
    int length, {
    int rune = 0x2500,
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
  }) {
    var cell = Cell(rune: rune, fg: fg, bg: bg, style: style);
    for (var i = 0; i < length; i++) {
      _put(start.row, start.col + i, cell);
    }
  }

  /// Draw a vertical run of [length] cells starting at [start].
  void drawVLine(
    CellOffset start,
    int length, {
    int rune = 0x2502,
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
  }) {
    var cell = Cell(rune: rune, fg: fg, bg: bg, style: style);
    for (var i = 0; i < length; i++) {
      _put(start.row + i, start.col, cell);
    }
  }
}
