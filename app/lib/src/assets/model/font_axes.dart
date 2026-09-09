// What a variable font can be moved along, read out of the file itself.
//
// A variable face declares its axes in the `fvar` table: a four-letter tag,
// and the minimum, default and maximum it accepts. That is exactly what a
// slider needs, and the alternative — asking an author to type `wght` and
// guess its range — is not a design tool. So the studio opens the font.
//
// Deliberately small. `fvar` is a fixed-layout table at a known offset in a
// table directory every sfnt has, which is thirty lines of `ByteData`; a
// font-parsing dependency for four numbers per axis would be a poor trade.
// Named instances and the `STAT` table are not read: an axis with a range is
// the whole of what the panel draws.
import 'dart:typed_data';

/// One axis a face declares.
class FontAxis {
  const FontAxis(
    this.tag, {
    required this.min,
    required this.def,
    required this.max,
  });

  /// The four-letter tag the font names it by: `wght`, `wdth`, `slnt`, `opsz`
  /// and the registered rest, plus whatever the designer invented.
  final String tag;

  final double min;
  final double def;
  final double max;

  /// What the panel calls it. The registered tags have names everyone knows;
  /// a custom one is shown as its tag, which is what a type designer calls it
  /// anyway.
  String get label => switch (tag) {
    'wght' => 'Weight',
    'wdth' => 'Width',
    'slnt' => 'Slant',
    'ital' => 'Italic',
    'opsz' => 'Optical size',
    'GRAD' => 'Grade',
    _ => tag,
  };

  @override
  String toString() => 'FontAxis($tag, $min..$max, default $def)';
}

/// The axes [bytes] declares, or an empty list when it declares none — which
/// is what a static face and an unreadable file both answer, because a panel
/// draws the same thing for either.
List<FontAxis> readFontAxes(Uint8List bytes) {
  var b = ByteData.sublistView(bytes);
  // A collection holds several faces and needs a face index to mean
  // anything; nothing here asks for one, so it is left alone.
  if (b.lengthInBytes < 12 || _tagAt(b, 0) == 'ttcf') return const [];
  var tables = b.getUint16(4);
  int? fvar;
  for (var i = 0; i < tables; i++) {
    var record = 12 + i * 16;
    if (record + 16 > b.lengthInBytes) return const [];
    if (_tagAt(b, record) == 'fvar') fvar = b.getUint32(record + 8);
  }
  if (fvar == null || fvar + 16 > b.lengthInBytes) return const [];

  var axes = fvar + b.getUint16(fvar + 4);
  var count = b.getUint16(fvar + 8);
  var size = b.getUint16(fvar + 10);
  // 20 is the size the spec fixes; a bigger one is legal and the extra bytes
  // are skipped, a smaller one is not a table this can read.
  if (size < 20 || axes + count * size > b.lengthInBytes) return const [];
  return [for (var i = 0; i < count; i++) ?_axisAt(b, axes + i * size)];
}

FontAxis? _axisAt(ByteData b, int at) {
  var tag = _tagAt(b, at);
  if (tag.length != 4) return null;
  // Fixed 16.16 throughout the record.
  double fixed(int o) => b.getInt32(o) / 65536.0;
  var min = fixed(at + 4);
  var def = fixed(at + 8);
  var max = fixed(at + 12);
  // A range the wrong way round, or a default outside it, is a font this
  // cannot draw a slider for — and clamping it would put the handle
  // somewhere the face never goes.
  if (min > max || def < min || def > max) return null;
  return FontAxis(tag, min: min, def: def, max: max);
}

String _tagAt(ByteData b, int at) =>
    String.fromCharCodes([for (var i = 0; i < 4; i++) b.getUint8(at + i)]);
