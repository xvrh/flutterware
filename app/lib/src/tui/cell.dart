/// Text style bitfield. Combine with bitwise OR.
class TextStyle {
  static const int bold = 1 << 0;
  static const int dim = 1 << 1;
  static const int italic = 1 << 2;
  static const int underline = 1 << 3;
  static const int reverse = 1 << 4;

  // not instantiable
  TextStyle._();
}

/// Color in one of three encodings: terminal default, ANSI named (16-color),
/// or 24-bit RGB. Equality is structural.
class Color {
  final int _kind; // 0 = default, 1 = ansi, 2 = rgb
  final int ansiIndex; // valid when _kind == 1; 0..15
  final int r, g, b; // valid when _kind == 2

  const Color._(this._kind, this.ansiIndex, this.r, this.g, this.b);

  static const Color defaultFg = Color._(0, 0, 0, 0, 0);
  static const Color defaultBg = Color._(0, 1, 0, 0, 0); // sentinel distinct from defaultFg

  // 16 ANSI named colors (indices match the ANSI SGR convention).
  static const Color black = Color._(1, 0, 0, 0, 0);
  static const Color red = Color._(1, 1, 0, 0, 0);
  static const Color green = Color._(1, 2, 0, 0, 0);
  static const Color yellow = Color._(1, 3, 0, 0, 0);
  static const Color blue = Color._(1, 4, 0, 0, 0);
  static const Color magenta = Color._(1, 5, 0, 0, 0);
  static const Color cyan = Color._(1, 6, 0, 0, 0);
  static const Color white = Color._(1, 7, 0, 0, 0);
  static const Color brightBlack = Color._(1, 8, 0, 0, 0);
  static const Color brightRed = Color._(1, 9, 0, 0, 0);
  static const Color brightGreen = Color._(1, 10, 0, 0, 0);
  static const Color brightYellow = Color._(1, 11, 0, 0, 0);
  static const Color brightBlue = Color._(1, 12, 0, 0, 0);
  static const Color brightMagenta = Color._(1, 13, 0, 0, 0);
  static const Color brightCyan = Color._(1, 14, 0, 0, 0);
  static const Color brightWhite = Color._(1, 15, 0, 0, 0);

  const factory Color.rgb(int r, int g, int b) = Color._rgb;
  const Color._rgb(this.r, this.g, this.b) : _kind = 2, ansiIndex = 0;

  bool get isDefault => _kind == 0;
  bool get isAnsi => _kind == 1;
  bool get isRgb => _kind == 2;
  bool get isDefaultFg => _kind == 0 && ansiIndex == 0;
  bool get isDefaultBg => _kind == 0 && ansiIndex == 1;

  @override
  bool operator ==(Object other) =>
      other is Color &&
      _kind == other._kind &&
      ansiIndex == other.ansiIndex &&
      r == other.r &&
      g == other.g &&
      b == other.b;

  @override
  int get hashCode => Object.hash(_kind, ansiIndex, r, g, b);
}

/// A single terminal cell. Immutable.
class Cell {
  final int rune;
  final Color fg;
  final Color bg;
  final int style;
  final int width; // 1 for stage 1; reserved for wide-char support later

  const Cell({
    required this.rune,
    this.fg = Color.defaultFg,
    this.bg = Color.defaultBg,
    this.style = 0,
    this.width = 1,
  });

  static const Cell empty = Cell(rune: 0x20);

  @override
  bool operator ==(Object other) =>
      other is Cell &&
      rune == other.rune &&
      fg == other.fg &&
      bg == other.bg &&
      style == other.style &&
      width == other.width;

  @override
  int get hashCode => Object.hash(rune, fg, bg, style, width);
}
