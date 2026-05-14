import 'buffer.dart';
import 'cell.dart';

/// ANSI escape sequences used by the engine.
///
/// Naming convention: constants are static strings; functions build sequences
/// from arguments. All cursor coordinates exposed by this module are 0-indexed
/// (matching CellBuffer); the CSI conversion to 1-indexed happens here.
class Ansi {
  Ansi._();

  static const String esc = '\x1b';
  static const String csi = '\x1b[';

  static const String enterAltScreen = '\x1b[?1049h';
  static const String exitAltScreen = '\x1b[?1049l';
  static const String hideCursor = '\x1b[?25l';
  static const String showCursor = '\x1b[?25h';
  static const String clearScreen = '\x1b[2J';
  static const String resetStyle = '\x1b[0m';

  /// 0-indexed row, col → CSI move sequence (1-indexed).
  static String moveTo(int row, int col) => '$csi${row + 1};${col + 1}H';

  /// SGR parameter for a foreground color. Returns the parameter string only
  /// (e.g. `'31'` or `'38;2;10;20;30'`), without the CSI prefix or final `m`.
  static String sgrForeground(Color c) {
    if (c.isDefaultFg) return '39';
    if (c.isAnsi) {
      final i = c.ansiIndex;
      return i < 8 ? '${30 + i}' : '${90 + (i - 8)}';
    }
    // rgb
    return '38;2;${c.r};${c.g};${c.b}';
  }

  /// SGR parameter for a background color.
  static String sgrBackground(Color c) {
    if (c.isDefaultBg) return '49';
    if (c.isAnsi) {
      final i = c.ansiIndex;
      return i < 8 ? '${40 + i}' : '${100 + (i - 8)}';
    }
    return '48;2;${c.r};${c.g};${c.b}';
  }

  /// SGR parameters for a style bitfield. Empty list if style == 0.
  static List<String> sgrStyle(int style) {
    final out = <String>[];
    if (style & TextStyle.bold != 0) out.add('1');
    if (style & TextStyle.dim != 0) out.add('2');
    if (style & TextStyle.italic != 0) out.add('3');
    if (style & TextStyle.underline != 0) out.add('4');
    if (style & TextStyle.reverse != 0) out.add('7');
    return out;
  }
}

/// Encode the difference between [front] (current screen state) and [back]
/// (desired state) as a string of ANSI escape sequences. Returns an empty
/// string if there are no changes.
///
/// Defined in a later task.
String encodeDiff(CellBuffer front, CellBuffer back) {
  throw UnimplementedError('see Task 4');
}
