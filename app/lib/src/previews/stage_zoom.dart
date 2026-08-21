/// Magnifying the preview: one transform over the whole staged device, and the
/// guest's pixel ratio following it.
///
/// The magnification is the stage's, and the sharpness is the guest's. An
/// `InteractiveViewer` scales everything on the stage — the phone body, the
/// notch, the screen — which is what makes zooming *into a framed preview* look
/// like zooming into a photograph of a phone rather than into a rectangle that
/// happens to sit inside one. On its own that would be a magnified picture, so
/// the scale is handed back down to the guest as pixel ratio: the demo lays out
/// on the same screen it always had and simply renders more pixels into it, and
/// the texture that comes back has as many pixels as the stage is now drawing.
///
/// Layout is untouched, which is the whole promise. Only [guestRatioFor]
/// moves; the logical size the guest is given never does. So `MediaQuery.size`,
/// every breakpoint and every `LayoutBuilder` inside the demo read exactly what
/// they read at 1×, and nothing about magnifying can change what the preview is
/// a preview *of*.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How many device pixels the guest may be asked to render.
///
/// This is the one real cost of zooming the frame. Magnifying the body
/// means the screen inside it grows too, and every pixel of that screen has to
/// exist somewhere — the guest renders its whole surface, not the part that
/// happens to be on your monitor. So the bytes go up with the square of the
/// scale: an iPhone 16 is 3.0 Mpx at 1× and 48 Mpx at 4×.
///
/// 64 Mpx is ~256 MB of texture, which is where the trade stops being worth it.
/// Nothing stops zooming there — the ratio simply stops climbing and the
/// picture goes gradually soft, the way any viewer does past its source
/// resolution. That is a much better wall than a gesture that refuses.
const zoomPixelBudget = 64 * 1000 * 1000;

/// Past life-size, but by less than this, is not a zoom anyone asked for.
///
/// A trackpad emits a pan-zoom sequence for every incidental two-finger touch,
/// and without a floor the stage ends up parked at 1.02× — visibly soft, for a
/// magnification nobody can see.
const zoomFloor = 1.02;

/// The pixel ratio to render [logical] at when the stage is drawing it [scale]
/// times life-size, given the ratio the device itself declares.
///
/// Capped by [zoomPixelBudget], never refused.
double guestRatioFor(Size logical, double deviceRatio, double scale) {
  var wanted = deviceRatio * math.max(1, scale);
  var area = logical.width * logical.height;
  if (area <= 0) return wanted;
  var ceiling = math.sqrt(zoomPixelBudget / area);
  return math.min(wanted, math.max(deviceRatio, ceiling));
}

/// Pan and zoom over the whole stage.
///
/// Nothing below this rebuilds while you zoom. The transform lives above
/// the child and the guest's ratio is pushed by a listener, so a gesture moves
/// one matrix and sends at most one resize — where an earlier cut rebuilt the
/// body, the texture and a `LayoutBuilder` on every frame of a pinch, which is
/// most of what "it doesn't feel smooth" was.
class ZoomableStage extends StatefulWidget {
  const ZoomableStage({
    super.key,
    required this.controller,
    required this.onInteracting,
    required this.child,
  });

  final TransformationController controller;

  /// Called with true while a pan is actually moving the stage.
  ///
  /// The guest is driven by a `Listener`, which is not a gesture recognizer and
  /// therefore never loses an arena: without being told, the demo underneath
  /// receives the whole pan as a drag and scrolls its own lists while you are
  /// moving the stage over them.
  final ValueChanged<bool> onInteracting;

  final Widget child;

  @override
  State<ZoomableStage> createState() => _ZoomableStageState();
}

class _ZoomableStageState extends State<ZoomableStage> {
  /// Mirrors the controller's scale, so the stage below rebuilds on a zoom and
  /// not on a pan.
  late final _scale = ValueNotifier(_scaleOf(widget.controller.value));

  /// Where a trackpad gesture started, so a pan-zoom sequence — whose values
  /// are cumulative rather than incremental — can be read as a delta.
  double _gestureStartScale = 1;
  Offset _gestureFocus = Offset.zero;

  static double _scaleOf(Matrix4 matrix) => matrix.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_follow);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_follow);
    _scale.dispose();
    super.dispose();
  }

  void _follow() => _scale.value = _scaleOf(widget.controller.value);

  /// Applies [factor] to the current scale, holding [focal] still.
  ///
  /// In the viewer's own coordinates, which is what makes it hold: the point
  /// under the cursor is `inverse(matrix) * focal` before and after, so the
  /// translation is solved rather than accumulated — an accumulated one drifts
  /// a little per notch and a lot per gesture.
  void _zoomBy(double factor, Offset focal) {
    var matrix = widget.controller.value.clone();
    var current = _scaleOf(matrix);
    var next = (current * factor).clamp(1.0, 512.0);
    // **Rest is the identity, and getting there is unconditional.** Checking
    // `next == current` first is the bug that stranded a panned stage: zoom
    // out far enough and the scale clamps at 1, every further notch is a
    // no-op, and the translation it was left with can never be undone —
    // panning is off at life-size, so there is nothing that could undo it.
    if (next <= zoomFloor) {
      if (!_isIdentity(widget.controller.value)) {
        widget.controller.value = Matrix4.identity();
      }
      return;
    }
    if (next == current) return;
    var before = _toScene(matrix, focal);
    matrix.scaleByDouble(next / current, next / current, 1, 1);
    var after = _toScene(matrix, focal);
    matrix.translateByDouble(after.dx - before.dx, after.dy - before.dy, 0, 1);
    widget.controller.value = matrix;
  }

  static Offset _toScene(Matrix4 matrix, Offset viewportPoint) {
    var inverted = Matrix4.inverted(matrix);
    var v = inverted.applyToVector3Array([
      viewportPoint.dx,
      viewportPoint.dy,
      0,
    ]);
    return Offset(v[0], v[1]);
  }

  /// A wheel notch, or a trackpad's two fingers moved this far.
  ///
  /// Multiplicative, because zoom is: 1×→2× and 8×→16× are the same flick.
  ///
  /// A mouse and a trackpad are not the same device here. A trackpad sends
  /// a stream of small deltas at frame rate, so anything continuous feels
  /// smooth; a wheel sends one lump of ~100 per notch, and at the rate that
  /// suits a trackpad each notch is a 1.5× jump — which reads as the zoom
  /// snapping between sizes rather than moving.
  static double _factorFor(double dy, {required bool wheel}) =>
      math.exp(-dy * (wheel ? 0.0016 : 0.004));

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !stageOwnsPointer(event)) return;
    _zoomBy(_factorFor(event.scrollDelta.dy, wheel: true), event.localPosition);
  }

  void _panZoomStart(PointerPanZoomStartEvent event) {
    _gestureStartScale = _scaleOf(widget.controller.value);
    _gestureFocus = event.localPosition;
  }

  void _panZoomUpdate(PointerPanZoomUpdateEvent event) {
    // **Two gestures arrive down this one path**, and [stageOwnsPointer] is
    // what decides whether either is ours — asked here rather than restated,
    // because the demo is denied exactly what this acts on. This is also the
    // path that was missing when ⌘-scroll did nothing on a trackpad: a
    // trackpad has not sent `PointerScrollEvent` since Flutter 3.3, so a
    // handler watching only for that is a handler for mice.
    if (!stageOwnsPointer(event)) return;
    if (event.scale != 1.0) {
      // A pinch reports its scale against the start of the sequence, so it is
      // an absolute target rather than a step.
      var target = _gestureStartScale * event.scale;
      var current = _scaleOf(widget.controller.value);
      if (current > 0) _zoomBy(target / current, _gestureFocus);
      return;
    }
    // A two-finger scroll reports its pan cumulatively for the same reason, so
    // reading it raw magnifies by the whole gesture again on every frame.
    var delta = event.pan.dy - _panConsumed;
    _panConsumed = event.pan.dy;
    _zoomBy(_factorFor(-delta, wheel: false), _gestureFocus);
  }

  /// How much of the sequence's cumulative pan has already been spent.
  double _panConsumed = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _signal,
      onPointerPanZoomStart: (e) {
        _panConsumed = 0;
        _panZoomStart(e);
      },
      onPointerPanZoomUpdate: _panZoomUpdate,
      child: ValueListenableBuilder(
        valueListenable: _scale,
        builder: (context, scale, _) {
          var zoomed = scale > zoomFloor;
          return InteractiveViewer(
            transformationController: widget.controller,
            // **Ours, not the viewer's.** Its own scaling is a wheel that
            // zooms unmodified and a pinch it shares with panning, both of
            // which would take gestures the live demo needs.
            scaleEnabled: false,
            // Nothing to pan at life-size, and a drag that panned nothing
            // would still have been taken from the demo.
            panEnabled: zoomed,
            // The stage is a phone on a table, not a document: it may be
            // dragged past the edge, because the corner of a magnified screen
            // is exactly the thing you cannot otherwise get to.
            boundaryMargin: const EdgeInsets.all(double.infinity),
            onInteractionUpdate: (details) {
              if (zoomed && details.pointerCount > 0) {
                widget.onInteracting(true);
              }
            },
            onInteractionEnd: (_) => widget.onInteracting(false),
            child: widget.child,
          );
        },
      ),
    );
  }
}

/// Whether [matrix] is the stage at rest — life-size and centred.
bool isAtRest(Matrix4 matrix) => _isIdentity(matrix);

bool _isIdentity(Matrix4 matrix) => matrix == Matrix4.identity();

/// Whether [event] belongs to the stage rather than to the demo.
///
/// One predicate, read by both sides, because the two answers have to agree
/// exactly: the stage acts on what this claims, and the demo is denied what
/// this claims, and a rule written twice is a rule that drifts. The first
/// version of it drifted immediately — the demo was denied *every* trackpad
/// pan-zoom update, which is also how a list inside a preview is scrolled, so
/// scrolling a demo on a trackpad stopped working altogether.
///
/// A pinch is the stage's on any machine — nothing else uses two fingers
/// converging, and it means zoom in every other application. A scroll is the
/// demo's unless ⌘ (or Ctrl) says otherwise, which is the convention every
/// canvas shares and the only rule that keeps a magnified preview a preview
/// you can still scroll.
bool stageOwnsPointer(PointerEvent event) {
  if (event is PointerScrollEvent) return isStageModifier();
  if (event is PointerPanZoomUpdateEvent) {
    return event.scale != 1.0 || isStageModifier();
  }
  return false;
}

/// Whether the modifier that hands a scroll to the stage is down.
bool isStageModifier() =>
    HardwareKeyboard.instance.isMetaPressed ||
    HardwareKeyboard.instance.isControlPressed;
