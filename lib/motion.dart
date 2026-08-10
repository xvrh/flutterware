/// Choreography a tool can edit and a person can read.
///
/// A motion is declared where it is read: you name a target, you read its
/// properties, you plug the values where only you know they go.
///
/// ```dart
/// MotionScope(
///   motion: onboardingMotion,          // a const the editor writes
///   builder: (m) {
///     var title = m.target('title');
///     var cta = m.target('cta');
///     return Column(children: [
///       MotionBox(title, child: const Text('Welcome back')),
///       FilledButton(
///         onPressed: _submit,
///         style: FilledButton.styleFrom(backgroundColor: cta.color ?? Colors.white),
///         child: const Text('Continue'),
///       ),
///     ]);
///   },
/// )
/// ```
///
/// Two things follow from that shape, and both are deliberate.
///
/// **A motion is a pure function of its playhead.** `evaluate(t) → values`, no
/// wall clock in the model. It is what makes scrubbing, playing, capture at an
/// arbitrary `t`, and a golden frame the same code path rather than four.
///
/// **The tuned numbers live in a file no human writes.** Structure comes from
/// your code, values come from `<screen>.motion.dart`, and the editor rewrites
/// that file whole and touches nothing else. With no such file, every property
/// falls back to its resting value and the code still runs — the tool is
/// optional at runtime.
///
/// Scope, stated so it is not discovered an hour in: designed choreography of a
/// fixed duration. Hero transitions, interactive dismiss, velocity-dependent
/// physics and data-driven reorders are outside it.
library;

export 'src/motion/guest.dart'
    show
        MotionRegistry,
        MotionSurface,
        curveByName,
        curveName,
        motionCurveNames;
export 'src/motion/target.dart' show Motion, MotionTarget;
export 'src/motion/controller.dart' show MotionController, MotionSource;
export 'src/motion/motion_box.dart' show MotionBox;
export 'src/motion/scope.dart' show MotionScope, MotionScopeState;
export 'src/motion/values.dart' show MotionValues, Seg;
// Re-exported rather than declared here: the same names have to be reachable
// without Flutter, for the tooling that reads code instead of running it.
export 'motion_vocabulary.dart';
