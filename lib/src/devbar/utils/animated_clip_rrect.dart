import 'package:flutter/material.dart';

class AnimatedClipRRect extends ImplicitlyAnimatedWidget {
  AnimatedClipRRect({
    Key? key,
    required this.borderRadius,
    required this.child,
    Curve curve = Curves.linear,
    required Duration duration,
    VoidCallback? onEnd,
  }) : super(key: key, curve: curve, duration: duration, onEnd: onEnd);

  final BorderRadius borderRadius;

  /// The widget below this widget in the tree.
  ///
  /// {@macro flutter.widgets.child}
  final Widget child;

  @override
  AnimatedWidgetBaseState<AnimatedClipRRect> createState() =>
      _AnimatedClipRRectState();
}

class _AnimatedClipRRectState
    extends AnimatedWidgetBaseState<AnimatedClipRRect> {
  BorderRadiusTween? _borderRadius;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _borderRadius = visitor(_borderRadius, widget.borderRadius,
            (dynamic value) => BorderRadiusTween(begin: value as BorderRadius))!
        as BorderRadiusTween;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: _borderRadius!.evaluate(animation)!,
      child: widget.child,
    );
  }
}
