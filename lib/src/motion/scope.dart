import 'package:flutter/widgets.dart';

import 'anchor.dart';
import 'controller.dart';
import 'values.dart';

/// Runs a motion over a subtree.
///
/// ```dart
/// MotionScope(
///   motion: onboardingMotion,
///   builder: (m) {
///     var title = m.anchor('title');
///     return MotionBox(title, child: const Text('Welcome back'));
///   },
/// )
/// ```
///
/// The builder reruns every frame while the motion is playing, which for a
/// 400ms entrance is ~24 rebuilds of a subtree — the same cost as a `setState`
/// at the top of a screen. Where that is not acceptable (a looping animation,
/// parallax over a long list), hoist the expensive widget into the *enclosing*
/// build and close over it; Flutter's element update short-circuits on an
/// identical widget instance, which is the mechanism `AnimatedBuilder`'s
/// `child:` relies on. No extra API is needed for it.
///
/// The scope owns the playhead, so two of these — two list items, the same
/// screen pushed twice — each animate independently with no arrangement.
class MotionScope extends StatefulWidget {
  const MotionScope({
    super.key,
    required this.motion,
    required this.builder,
    this.controller,
  });

  /// The tuned values, normally the `const` from a `<screen>.motion.dart`.
  final MotionValues motion;

  /// Pass one to drive the motion yourself. Omitted, the scope makes and
  /// disposes its own, and [MotionController.autoplay] means an entrance
  /// needs no code at all.
  final MotionController? controller;

  final Widget Function(Motion m) builder;

  @override
  State<MotionScope> createState() => MotionScopeState();
}

class MotionScopeState extends State<MotionScope>
    with SingleTickerProviderStateMixin {
  late Motion _motion;
  late MotionController _controller;
  var _ownsController = false;

  /// What the last build read, for a host that is looking. Kept on the state
  /// rather than the [Motion] so it survives the next `beginBuild`.
  Set<String> get reads => _motion.reads;

  /// Properties a blanket reader swept — available on an anchor, but not
  /// evidence that anybody wired them. See [Motion.offered].
  Set<String> get offered => _motion.offered;

  Set<String> get anchorsNamed => _motion.named;

  MotionController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _motion = Motion(widget.motion);
    _adoptController(widget.controller);
  }

  void _adoptController(MotionController? given) {
    _ownsController = given == null;
    _controller = given ?? MotionController();
    _controller
      ..addListener(_onProgress)
      ..attach(this, widget.motion.resolveDuration());
    _motion.position = _controller.position;
  }

  void _releaseController() {
    _controller.removeListener(_onProgress);
    _controller.detach();
    if (_ownsController) _controller.dispose();
  }

  void _onProgress() {
    if (!mounted) return;
    setState(() => _motion.position = _controller.position);
  }

  @override
  void didUpdateWidget(MotionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _releaseController();
      _adoptController(widget.controller);
    }
    if (!identical(widget.motion, oldWidget.motion)) {
      // A hot reload of the values file lands here. The playhead is kept, so
      // an edit does not snap you back to zero.
      _motion.values = widget.motion;
      _controller.updateDuration(widget.motion.resolveDuration());
      _motion.position = _controller.position;
    }
  }

  @override
  void dispose() {
    _releaseController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.beginBuild();
    return widget.builder(_motion);
  }
}
