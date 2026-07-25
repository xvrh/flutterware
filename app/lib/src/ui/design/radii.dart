import 'package:flutter/widgets.dart';

/// Corner radii. Provided via [FwTokens]; read through `context.radii`.
@immutable
class FwRadii {
  final double radiusSmall;
  final double radius;
  final double radiusLarge;

  const FwRadii({
    required this.radiusSmall,
    required this.radius,
    required this.radiusLarge,
  });

  FwRadii copyWith({double? radiusSmall, double? radius, double? radiusLarge}) {
    return FwRadii(
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radius: radius ?? this.radius,
      radiusLarge: radiusLarge ?? this.radiusLarge,
    );
  }

  static FwRadii lerp(FwRadii a, FwRadii b, double t) {
    double d(double x, double y) => x + (y - x) * t;
    return FwRadii(
      radiusSmall: d(a.radiusSmall, b.radiusSmall),
      radius: d(a.radius, b.radius),
      radiusLarge: d(a.radiusLarge, b.radiusLarge),
    );
  }
}

const defaultRadii = FwRadii(radiusSmall: 7.0, radius: 9.0, radiusLarge: 12.0);
