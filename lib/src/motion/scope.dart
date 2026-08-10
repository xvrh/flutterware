import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'guest.dart';
import 'target.dart';
import 'values.dart';

/// Runs a motion over a subtree.
///
/// ```dart
/// MotionScope(
///   motion: onboardingMotion,
///   builder: (m) {
///     var title = m.target('title');
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

/// `TickerProviderStateMixin`, not the `Single` one, and it is not a nicety.
///
/// A scope adopts a controller on mount and again whenever it is handed a
/// different one, and each adoption makes an `AnimationController` — so writing
/// `MotionScope(controller: MotionController(...))` inline in a `build` crashed
/// on the second build with Flutter's generic "multiple tickers were created"
/// assertion, which names neither this class nor the mistake. Every adoption
/// pairs with a `detach` that disposes its ticker, so the plural mixin costs
/// nothing and the inline spelling simply works.
class MotionScopeState extends State<MotionScope>
    with TickerProviderStateMixin
    implements MotionSurface {
  late Motion _motion;
  late MotionController _controller;
  var _ownsController = false;
  String? _registryId;

  /// What the last build read, for a host that is looking. Kept on the state
  /// rather than the [Motion] so it survives the next `beginBuild`.
  @override
  Set<String> get reads => _motion.reads;

  /// Properties a blanket reader swept — available on a target, but not
  /// evidence that anybody wired them. See [Motion.offered].
  @override
  Set<String> get offered => _motion.offered;

  @override
  Set<String> get targetsNamed => _motion.named;

  @override
  MotionController get controller => _controller;

  @override
  MotionValues get motionValues => widget.motion;

  @override
  Object? peek(String target, String property) =>
      _motion.peek(target, property);

  @override
  Rect? extentOf(String target) => _motion.extentOf(target);

  @override
  void initState() {
    super.initState();
    _motion = Motion(widget.motion);
    _adoptController(widget.controller);
    // Registered on mount rather than before `runApp`: a motion lives in
    // somebody's screen, and there is no entrypoint of ours to hang it on.
    _registryId = MotionRegistry.instance.attach(this);
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
    if (_registryId case var id?) MotionRegistry.instance.detach(id);
    _releaseController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.beginBuild();
    return widget.builder(_motion);
  }
}
