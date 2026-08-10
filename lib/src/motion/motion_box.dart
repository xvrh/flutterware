import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'extent.dart';
import 'target.dart';

/// Applies a target's transform-shaped properties in one widget.
///
/// ```dart
/// MotionBox(title, child: const Text('Welcome back'))
/// ```
///
/// Exists because an element that fades *and* moves is otherwise
/// `Opacity(child: Transform.translate(child: …))`, and a five-element screen
/// nests deeply enough to read badly. Taking the target rather than a list of
/// values keeps the call site to one line; the reads still happen through the
/// same getters, so a host watching which properties are wired sees exactly
/// what it would have seen written out by hand.
///
/// **What it applies is frozen**, and is the whole of it:
///
/// `opacity`, `translateX`, `translateY`, `scale`, `scaleX`, `scaleY`,
/// `rotate`, `blur`.
///
/// Growing the vocabulary later must never change what code already written
/// does, so nothing is ever added to that list. Anything outside it stays a
/// read at the call site — which is the honest signal that it is doing
/// something structural rather than cosmetic.
///
/// Each layer is skipped when its property is at rest, so a target that only
/// fades costs one `Opacity` and no `Transform`, and a `blur` of zero adds no
/// image filter at all.
class MotionBox extends StatelessWidget {
  const MotionBox(
    this.target, {
    super.key,
    this.origin = Alignment.center,
    required this.child,
  });

  final MotionTarget target;

  /// The point `rotate` and the scales work about.
  ///
  /// `origin` rather than `alignment`, because this is not where the widget
  /// sits — it is the fixed point the transform is taken about, and `Transform`
  /// only calls it `alignment` for want of a better word.
  final AlignmentGeometry origin;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Read every one of them, every build, whether or not it is used: what a
    // MotionBox applies must not depend on what happens to be tuned right now.
    //
    // Recorded as *offered* rather than read, though. Eight properties swept
    // by one widget are not eight wired properties, and a panel that could not
    // tell the difference would show eight empty lanes for an element that
    // animates one thing.
    var (
      opacity,
      translateX,
      translateY,
      scale,
      scaleX,
      scaleY,
      rotate,
      blur,
    ) = target.motion.offering(
      () => (
        target.opacity,
        target.translateX,
        target.translateY,
        target.scale,
        target.scaleX,
        target.scaleY,
        target.rotate,
        target.blur,
      ),
    );

    // Innermost, so the ring the editor draws is where the child has been moved
    // and scaled *to*: the transform below is an ancestor of this box, and
    // `getTransformTo(null)` walks through it. Registered from out here the
    // rect would be the layout box and would sit still through the one thing a
    // motion editor exists to watch.
    Widget result = MotionExtent(target, child: child);

    if (blur > 0) {
      result = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: result,
      );
    }

    var x = scale * scaleX;
    var y = scale * scaleY;
    if (translateX != 0 || translateY != 0 || rotate != 0 || x != 1 || y != 1) {
      var transform = Matrix4.identity()
        ..translateByDouble(translateX, translateY, 0, 1)
        ..rotateZ(rotate)
        ..scaleByDouble(x, y, 1, 1);
      result = Transform(
        transform: transform,
        alignment: origin,
        child: result,
      );
    }

    if (opacity != 1) {
      result = Opacity(opacity: opacity.clamp(0.0, 1.0), child: result);
    }

    return result;
  }
}
