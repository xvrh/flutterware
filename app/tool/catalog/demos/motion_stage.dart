import 'package:flutter/material.dart';
import 'package:flutterware/motion.dart';

/// **Prototype.** The draft scene — what the editor draws before anything is
/// bound to a real widget.
///
/// Deliberately not in `lib/`: this is a shape to look at, not published API.
///
/// A stage is the second file a motion owns. `<name>.motion.dart` says how
/// things move; `<name>.stage.dart` says what there is to move, and both are
/// written by the tool. It exists so that "New motion" and "add an element"
/// have somewhere to write — a target cannot be created by the editor today,
/// because the only place a target is named is a build method the tool may not
/// touch.
///
/// Everything here is const constructor calls, literals and enum values, which
/// is the grammar a parse-and-emit editor can read back.
class MotionStage {
  const MotionStage({
    required this.width,
    required this.height,
    required this.elements,
    this.background = const Color(0xFFF6F7F9),
  });

  final double width;
  final double height;
  final Color background;
  final List<StageElement> elements;
}

enum StageKind { box, text, circle }

/// One placeholder. Positioned absolutely, because a rect is the one layout an
/// editor can offer to a mouse and to an agent in the same words — a drag
/// writes `x`/`y`, and `--x=24 --y=80` writes the same two numbers.
class StageElement {
  const StageElement({
    required this.target,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.kind = StageKind.box,
    this.label,
    this.tint = const Color(0xFFCBD3DC),
    this.radius = 10,
  });

  final String target;
  final StageKind kind;
  final double x;
  final double y;
  final double width;
  final double height;

  /// Shown inside a `text` placeholder, and under any other kind as its name.
  final String? label;

  final Color tint;
  final double radius;
}

/// Renders a stage under a motion.
///
/// The same `MotionValues` that drives a real screen drives this, which is the
/// claim worth checking by eye: a motion does not know what it is animating.
///
/// **A placeholder can be animated more ways than a real widget can**, and that
/// is the trap rather than a feature. `color` and `borderRadius` land here
/// because the tool owns the box; on a bound `TextFormField` nothing outside it
/// can impose either. A lane tuned against a placeholder can therefore go
/// silent the moment it is bound, which is the case for judging a lane by
/// running it rather than by reading the file.
class MotionStageView extends StatelessWidget {
  const MotionStageView({
    super.key,
    required this.stage,
    required this.motion,
    this.controller,
    this.showNames = true,
  });

  final MotionStage stage;
  final MotionValues motion;
  final MotionController? controller;

  /// Draft affordance: every placeholder wears its target name, so the thing
  /// you are tuning and the lane you are dragging carry the same word.
  final bool showNames;

  @override
  Widget build(BuildContext context) {
    return MotionScope(
      motion: motion,
      controller: controller,
      builder: (m) => Center(
        child: SizedBox(
          width: stage.width,
          height: stage.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: stage.background,
              border: Border.all(color: const Color(0xFFDBE0E6)),
            ),
            child: Stack(
              children: [
                for (var element in stage.elements)
                  Positioned(
                    left: element.x,
                    top: element.y,
                    width: element.width,
                    height: element.height,
                    child: MotionBox(
                      m.target(element.target),
                      child: _Placeholder(
                        element: element,
                        target: m.target(element.target),
                        showName: showNames,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _outline = Color(0x33566072);

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.element,
    required this.target,
    required this.showName,
  });

  final StageElement element;
  final MotionTarget target;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    // Intrinsic properties are imposable here only because the tool owns this
    // box. See the class doc — this is the half that does not survive a bind.
    var fill = target.color ?? element.tint;
    var radius = target.borderRadius ?? element.radius;
    var elevation = target.elevation;

    Widget body = switch (element.kind) {
      // `SizedBox.expand`, not a bare `DecoratedBox`: a decoration with no
      // child has no size of its own, and inside the `Stack` below it
      // collapses to nothing. Cost one render to find.
      StageKind.circle => SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: _outline),
          ),
        ),
      ),
      StageKind.box => SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            // Always outlined. A placeholder whose tuned fill happens to match
            // the stage background is one you cannot see and therefore cannot
            // grab — and `email.color` animating to white on a white stage is
            // not a corner case, it is the first thing anybody tunes.
            border: Border.all(color: _outline),
            boxShadow: elevation > 0
                ? [
                    BoxShadow(
                      color: const Color(0x22000000),
                      blurRadius: elevation * 2,
                      offset: Offset(0, elevation / 2),
                    ),
                  ]
                : null,
          ),
        ),
      ),
      StageKind.text => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          element.label ?? element.target,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: target.fontSize ?? element.height * 0.62,
            height: 1.1,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF3D4650),
          ),
        ),
      ),
    };

    if (!showName || element.kind == StageKind.text) return body;

    // No `StackFit.expand`: it would force the label to fill too, and a Text
    // given tight constraints aligns itself top-left instead of centring. The
    // `Positioned` already hands this Stack a tight box.
    return Stack(
      alignment: Alignment.center,
      children: [
        body,
        Text(
          element.target,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 0.4,
            fontWeight: FontWeight.w600,
            color: Color(0x99384049),
          ),
        ),
      ],
    );
  }
}
