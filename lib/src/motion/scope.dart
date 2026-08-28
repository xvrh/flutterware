import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'guest.dart';
import 'stage.dart';
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
///
/// A [stage] gives it a second body: the draft scene, placeholders the tool
/// owns. Which of the two builds is the studio's choice rather than the file's
/// — see [MotionHost] — so a motion that has both reads exactly like one that
/// has only the screen. A motion that has only the stage is what `motion new`
/// writes, and it needs no [builder] at all until there is something to bind.
class MotionScope extends StatefulWidget {
  const MotionScope({
    super.key,
    required this.motion,
    this.builder,
    this.stage,
    this.controller,
  }) : assert(
         builder != null || stage != null,
         'A MotionScope needs a builder, a stage, or both.',
       );

  /// The tuned values, normally the `const` from a `<screen>.motion.dart`.
  final MotionValues motion;

  /// Pass one to drive the motion yourself. Omitted, the scope makes and
  /// disposes its own, and [MotionController.autoplay] means an entrance
  /// needs no code at all.
  final MotionController? controller;

  /// The real screen. Omitted only while [stage] stands in for it.
  final Widget Function(Motion m)? builder;

  /// The draft scene, normally the `const` from a `<screen>.stage.dart`.
  ///
  /// Kept beside the real body rather than in a separate entry point, because
  /// the point of a draft is that it is the *same motion* — one playhead, one
  /// set of tuned values, one registry id, so flipping mid-scrub keeps `t` and
  /// a lane tuned on the draft is the lane the screen will run.
  final MotionStage? stage;

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
  /// evidence that anything wired them. See [Motion.offered].
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
  List<MotionHost> get hosts => [
    if (widget.builder != null) MotionHost.real,
    if (widget.stage != null) MotionHost.draft,
  ];

  /// Real wherever there is a real body, because a shipped app must never draw
  /// placeholders — the switch is something the studio does to a running guest,
  /// not a state a file can start in.
  ///
  /// Read through [hosts] rather than off the field: a hot reload can take the
  /// body you are looking at away, and answering with one that no longer exists
  /// would build null.
  @override
  MotionHost get host => hosts.contains(_host) ? _host : hosts.first;

  @override
  set host(MotionHost value) {
    if (_host == value || !hosts.contains(value)) return;
    setState(() => _host = value);
  }

  late MotionHost _host;

  @override
  void initState() {
    super.initState();
    _host = widget.builder != null ? MotionHost.real : MotionHost.draft;
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
    if (widget.stage case var stage? when host == MotionHost.draft) {
      return MotionStageView(stage: stage, motion: _motion);
    }
    // `hosts` cannot report `real` without a builder, and `host` is read
    // through `hosts` — so this is unreachable rather than optimistic.
    return widget.builder!(_motion);
  }
}
