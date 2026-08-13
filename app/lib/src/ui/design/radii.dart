import 'package:flutter/widgets.dart';

/// Corner radii. Provided via [FwTokens]; read through `context.radii`.
///
/// Five steps, not three. The scale had no answer for a small chip and none for
/// a pill, so thirty-odd call sites wrote their own — nine different literals
/// between 1 and 20, plus eleven `circular(999)`. A scale that does not cover
/// what people build is not a scale they broke; it is one that was missing two
/// entries.
@immutable
class FwRadii {
  /// Chips, swatches, tags — anything small enough that [radiusSmall] reads as
  /// a circle rather than a rounded corner.
  final double micro;

  final double radiusSmall;
  final double radius;
  final double radiusLarge;

  /// Fully round ends. A token rather than a literal `999` so a theme with
  /// square chrome can flatten its badges along with everything else.
  final double pill;

  const FwRadii({
    required this.micro,
    required this.radiusSmall,
    required this.radius,
    required this.radiusLarge,
    required this.pill,
  });

  FwRadii copyWith({
    double? micro,
    double? radiusSmall,
    double? radius,
    double? radiusLarge,
    double? pill,
  }) {
    return FwRadii(
      micro: micro ?? this.micro,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radius: radius ?? this.radius,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      pill: pill ?? this.pill,
    );
  }

  static FwRadii lerp(FwRadii a, FwRadii b, double t) {
    double d(double x, double y) => x + (y - x) * t;
    return FwRadii(
      micro: d(a.micro, b.micro),
      radiusSmall: d(a.radiusSmall, b.radiusSmall),
      radius: d(a.radius, b.radius),
      radiusLarge: d(a.radiusLarge, b.radiusLarge),
      pill: d(a.pill, b.pill),
    );
  }
}

const defaultRadii = FwRadii(
  micro: 4.0,
  radiusSmall: 7.0,
  radius: 9.0,
  radiusLarge: 12.0,
  pill: 999.0,
);
