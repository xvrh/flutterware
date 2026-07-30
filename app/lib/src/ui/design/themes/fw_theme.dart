import 'package:flutter/widgets.dart';

import '../elevation.dart';
import '../palette.dart';
import '../radii.dart';
import '../tokens.dart';
import '../typography.dart';

/// A named theme: a display [name] plus its [FwTokens].
///
/// Themes are plain values, not a closed enum — define your own anywhere with
/// [FwTheme.from]. Nothing in the design system needs to change to add one.
@immutable
class FwTheme {
  final String name;

  /// Light token set.
  final FwTokens tokens;

  /// Optional dark token set; null if the theme is light-only.
  final FwTokens? dark;

  const FwTheme({required this.name, required this.tokens, this.dark});

  /// Builds a theme from a light [palette] and an optional [dark] palette; both
  /// share the [radii], [type] and [elevation].
  factory FwTheme.from({
    required String name,
    required FwPalette palette,
    FwPalette? dark,
    FwRadii? radii,
    FwTypeSpec? type,
    FwElevation? elevation,
  }) {
    FwTokens build(FwPalette p) => FwTokens.from(
      palette: p,
      radii: radii,
      type: type,
      elevation: elevation,
    );
    return FwTheme(
      name: name,
      tokens: build(palette),
      dark: dark == null ? null : build(dark),
    );
  }

  bool get hasDark => dark != null;

  /// A copy rebranded with [seed] as the primary colour (see
  /// [FwTokens.branded]), applied to both the light and dark token sets.
  FwTheme branded(String name, Color seed) => FwTheme(
    name: name,
    tokens: tokens.branded(seed),
    dark: dark?.branded(seed),
  );

  // [name] is the identity: themes are equal iff their names match, so names
  // must be unique within a theme list (they're also used as the picker key).
  @override
  bool operator ==(Object other) => other is FwTheme && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
