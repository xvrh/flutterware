import 'package:flutter/widgets.dart';

/// Shadow tokens for raised surfaces — menus, popovers, modals, cards. Three
/// steps; read through `context.elevation`. Provided via [FwTokens] so a theme
/// can ship its own depth.
@immutable
class FwElevation {
  /// Resting lift — dropdowns, hover cards.
  final List<BoxShadow> sm;

  /// Floating surfaces — popovers, menus.
  final List<BoxShadow> md;

  /// Overlay surfaces — modals, dialogs.
  final List<BoxShadow> lg;

  const FwElevation({required this.sm, required this.md, required this.lg});

  static FwElevation lerp(FwElevation a, FwElevation b, double t) {
    return FwElevation(
      sm: BoxShadow.lerpList(a.sm, b.sm, t) ?? const [],
      md: BoxShadow.lerpList(a.md, b.md, t) ?? const [],
      lg: BoxShadow.lerpList(a.lg, b.lg, t) ?? const [],
    );
  }
}

/// Neutral shadow set used unless a theme overrides it.
const defaultElevation = FwElevation(
  sm: [
    BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)),
  ],
  md: [
    BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4)),
  ],
  lg: [
    BoxShadow(color: Color(0x29000000), blurRadius: 28, offset: Offset(0, 12)),
  ],
);
