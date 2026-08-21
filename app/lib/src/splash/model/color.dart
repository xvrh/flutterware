/// Colours, as `flutter_native_splash` itself parses them.
///
/// Plain Dart, so `fw` links it: an ARGB int is not a `Color`, and the one
/// place that needs to be is the panel.
library;

/// Parses a config colour to opaque ARGB, or null when the generator would
/// reject it.
///
/// Transcribed from the package's `parseColor`:
///
/// ```dart
/// colorValue = colorValue.replaceAll('#', '').replaceAll(' ', '');
/// if (colorValue.length == 6) return colorValue;
/// … throw Exception('Invalid color value');
/// ```
///
/// Exactly six hex digits, RGB, no alpha. Eight digits do not mean ARGB
/// here — they throw, and so returning null for them is the honest answer
/// rather than a courtesy. Alpha is always opaque because a splash is drawn on
/// nothing.
int? parseSplashColor(String? value) {
  if (value == null) return null;
  var digits = value.replaceAll('#', '').replaceAll(' ', '');
  if (digits.length != 6) return null;
  var parsed = int.tryParse(digits, radix: 16);
  return parsed == null ? null : 0xFF000000 | parsed;
}

/// The canonical `#RRGGBB` spelling of an ARGB int — what a panel shows beside
/// a swatch and what `describe` prints.
String formatSplashColor(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
