import 'cell.dart';

/// A grid of cells, addressed by (row, col). Size is fixed at construction.
/// All mutation methods silently clip to bounds.
class CellBuffer {
  final int rows;
  final int cols;
  final List<Cell> _cells;

  CellBuffer(this.rows, this.cols)
      : _cells = List<Cell>.filled(rows * cols, Cell.empty, growable: false);

  bool inBounds(int row, int col) =>
      row >= 0 && row < rows && col >= 0 && col < cols;

  Cell get(int row, int col) {
    if (!inBounds(row, col)) return Cell.empty;
    return _cells[row * cols + col];
  }

  void set(int row, int col, Cell cell) {
    if (!inBounds(row, col)) return;
    _cells[row * cols + col] = cell;
  }

  void writeAt(
    int row,
    int col,
    String text, {
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
  }) {
    var c = col;
    for (final rune in text.runes) {
      if (inBounds(row, c)) {
        _cells[row * cols + c] = Cell(rune: rune, fg: fg, bg: bg, style: style);
      }
      c++;
    }
  }

  void fill(Cell cell) {
    for (var i = 0; i < _cells.length; i++) {
      _cells[i] = cell;
    }
  }

  void fillRect(int row, int col, int rowCount, int colCount, Cell cell) {
    final r0 = row.clamp(0, rows);
    final r1 = (row + rowCount).clamp(0, rows);
    final c0 = col.clamp(0, cols);
    final c1 = (col + colCount).clamp(0, cols);
    for (var r = r0; r < r1; r++) {
      for (var c = c0; c < c1; c++) {
        _cells[r * cols + c] = cell;
      }
    }
  }

  void clear() => fill(Cell.empty);

  void copyFrom(CellBuffer other) {
    if (other.rows != rows || other.cols != cols) {
      throw ArgumentError(
          'size mismatch: $rows×$cols vs ${other.rows}×${other.cols}');
    }
    for (var i = 0; i < _cells.length; i++) {
      _cells[i] = other._cells[i];
    }
  }
}
