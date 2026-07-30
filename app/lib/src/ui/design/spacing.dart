import 'package:flutter/widgets.dart';

/// Spacing rhythm for the app. The scale captures the gaps already in use so
/// new components stay on the same beat instead of inventing one-off literals.
class FwSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 8.0; // workhorse gap
  static const lg = 12.0;
  static const xl = 16.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

/// A square spacer — works in both [Row] and [Column] since the cross axis is
/// constrained by the parent. `Gap(FwSpacing.md)` reads better than a bare
/// `SizedBox(width/height: 8)` and removes the axis guesswork.
class Gap extends StatelessWidget {
  final double size;

  const Gap(this.size, {super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size);
}
