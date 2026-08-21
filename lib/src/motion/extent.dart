import 'package:flutter/widgets.dart';

import 'target.dart';

/// Says where a target is, and does nothing else.
///
/// ```dart
/// MotionExtent(art, child: const CoverArt())
/// ```
///
/// It applies no values, changes no layout, and adds no layer. It exists so
/// the editor can draw a ring around the thing a lane drives.
///
/// It is needed because a target is not a widget. `art.width` goes on a
/// `SizedBox`, `art.rotate` on a `Transform`, `art.elevation` inside a
/// `BoxShadow` — three call sites, no element that *is* `art`, and nothing to
/// infer from. Something has to point at it, and this is the smallest way.
///
/// Always optional. Skip it and the lane simply has no ring; every other
/// thing the panel does works the same either way.
///
/// [MotionBox] registers on its own, so a target that already goes through one
/// needs nothing here. That is also why this is a separate widget rather than a
/// job for that one: wrapping a target in a `MotionBox` *just* to be pointed at
/// would apply eight transform-shaped properties nobody asked for, and on a
/// target whose `rotate` is already read at its call site it would apply that
/// rotation twice.
class MotionExtent extends StatefulWidget {
  const MotionExtent(this.target, {super.key, required this.child});

  final MotionTarget target;
  final Widget child;

  @override
  State<MotionExtent> createState() => _MotionExtentState();
}

class _MotionExtentState extends State<MotionExtent> {
  @override
  void initState() {
    super.initState();
    _register(widget);
  }

  @override
  void didUpdateWidget(MotionExtent old) {
    super.didUpdateWidget(old);
    // The same element can be handed a different target — a list that rebuilds
    // with its rows reordered does exactly this — and a registration keyed on
    // the old name would point the ring at whatever used to be here.
    if (old.target.name != widget.target.name ||
        !identical(old.target.motion, widget.target.motion)) {
      _unregister(old);
      _register(widget);
    }
  }

  @override
  void dispose() {
    _unregister(widget);
    super.dispose();
  }

  void _register(MotionExtent of) =>
      of.target.motion.addExtent(of.target.name, context);

  void _unregister(MotionExtent of) =>
      of.target.motion.removeExtent(of.target.name, context);

  @override
  Widget build(BuildContext context) => widget.child;
}
