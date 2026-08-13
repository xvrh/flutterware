/// The icon ramp.
///
/// **Static const, deliberately — not a [FwTokens] axis like the palette and the
/// radii.** Two reasons, and the second is the decisive one. An icon size is
/// structural rather than expressive: a theme changes what things look like, not
/// how big a chevron is. And `const Icon(Icons.close, size: FwIconSize.sm)` only
/// stays const while the size is a compile-time constant — the same reason
/// [FwSpacing] is static, which 649 lines in this app depend on. A themeable
/// size axis would buy density nobody has asked for and cost const-ness
/// everywhere.
///
/// The five steps are the ones already in use, not an invention: 12, 14, 16, 18
/// and 32 covered 74 of the 94 icons in the app. What they did not cover was
/// 11, 13, 15, 17 and 20 — values a pixel or two off a neighbour, invisible
/// side by side and pure noise in the source. Those are what this collapses.
///
/// Two things stay off it, and both are deliberate. A dot is not an icon:
/// `Icons.circle` at 8 is a status marker, and the 9px close glyph on a lit
/// address-bar segment is an affordance inside a 23px bar — sub-scale shapes,
/// not small icons. And nothing in the launcher-icon and splash renderers is
/// migrated at all: those draw *another platform's* chrome, so their sizes are
/// content, in the same way their hardcoded colours are.
abstract final class FwIconSize {
  /// Inline with dense text — chips, hints, list-row secondaries.
  static const xs = 12.0;

  /// The workhorse: row affordances, buttons, anything beside body text.
  static const sm = 14.0;

  /// Standalone controls, toolbar buttons.
  static const md = 16.0;

  /// Prominent controls — a panel toolbar, a search field's leading icon.
  static const lg = 18.0;

  /// Placeholder art: the muted glyph over an empty state.
  static const xl = 32.0;
}
