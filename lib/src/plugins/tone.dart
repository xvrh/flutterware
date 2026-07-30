/// Severity of a piece of plugin state, independent of how it is rendered.
///
/// The GUI maps a tone to a palette colour; the CLI maps it to a glyph or an
/// ANSI colour; an agent reads the name. No renderer is privileged, so the tone
/// is data and never a `Color`.
enum Tone {
  neutral,
  good,
  info,
  warn,
  error;

  static Tone byName(String name) =>
      Tone.values.firstWhere((t) => t.name == name, orElse: () => Tone.neutral);
}
