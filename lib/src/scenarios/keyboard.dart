import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../devices.dart';
import '../ui_catalog/fake_keyboard.dart';
import 'staging.dart';

/// The keyboard a scenario raises without being asked.
///
/// **The point of the whole thing.** A scenario taps a field and photographs a
/// screen no phone would ever show: 844 points tall, with a form the user is
/// halfway through typing into. Everything a layout gets wrong about the other
/// 508 is invisible in every tool we have. With this on, a flow that fills a
/// form is a flow a phone could have performed, and its shots are pictures a
/// phone could have taken.
///
/// **No heuristics, because the framework already knows.** An `EditableText`
/// that takes focus asks the platform for a keyboard, and the test binding's
/// stub records the ask — so [TestTextInput.isVisible] *is* the signal, with
/// no cooperation from the app and nothing to guess at. The design's evidence
/// and the SDK line numbers behind it are in
/// `docs/superpowers/specs/2026-08-21-fake-keyboard-design.md`.
///
/// **The numbers go on the view, not on a `MediaQuery`.** A widget can only
/// tell the subtree beneath it; the view tells `MediaQuery.fromView`, which is
/// where every `MediaQuery` in the app ultimately comes from — including the
/// ones a nested `View`, a `MediaQuery.removePadding` or an overlay build for
/// themselves. That is also what a real embedder writes to, so the app cannot
/// tell the difference. The slab is a widget, because a picture has to be
/// somewhere.
class ScenarioKeyboard {
  ScenarioKeyboard(this.tester, {required this.deviceHeight});

  /// How long the raise takes, in **fake** time.
  ///
  /// A real iOS keyboard slides in over ~250ms and Gboard over ~220; one
  /// number for both, because a scenario is not measuring the animation, it is
  /// making sure the layout is seen meeting it. The clock is fake, so this
  /// costs nothing — it buys a motion recording where the keyboard slides the
  /// way a phone's does instead of teleporting.
  static const raise = Duration(milliseconds: 250);

  final WidgetTester tester;

  /// The device's measured keyboard, already turned the way the device is.
  /// Zero for a run staged on nothing, or on a desktop size — where a forced
  /// keyboard raises nothing rather than inventing a height.
  final double deviceHeight;

  /// What the run asked for, over the top of what the app asks for.
  KeyboardMode mode = KeyboardMode.auto;

  /// Where the slide has got to, in logical pixels.
  double get height => _height;
  double _height = 0;

  bool get up => _height > 0;

  /// Whether the app has a field focused — what the framework told the
  /// platform, not something inferred from the tree.
  ///
  /// Guarded on `isRegistered`, because the stub is registered by the binding
  /// per test and reading it before that asserts.
  bool get requested {
    var input = tester.binding.testTextInput;
    return input.isRegistered && input.isVisible;
  }

  /// What the height should be, as a fraction of [deviceHeight].
  double get _want => switch (mode) {
    KeyboardMode.up => 1,
    KeyboardMode.down => 0,
    KeyboardMode.auto => requested ? 1 : 0,
  };

  /// Where the slide is actually run — registered by the host widget in the
  /// pumped tree, and null when there is none.
  ///
  /// **The animation is a real `Ticker`, and it has to be.** A `Settle` loop
  /// asks `hasScheduledFrame` *after* its pump, and a frame scheduled by
  /// writing the view has been consumed by then — so a slide driven from the
  /// between-frames hook alone stops one frame in, with the keyboard a quarter
  /// of the way up and the layout laid out against a screen that never
  /// existed. A ticker keeps the binding asking for frames until it lands,
  /// which is exactly what every settle policy already knows how to wait for.
  void Function(double fraction, {required bool animate})? _run;

  /// Called by the host widget as it mounts and disposes.
  ///
  /// **Nothing is applied here.** Mounting happens inside a build, and writing
  /// the view fires `onMetricsChanged`, which makes `MediaQuery.fromView` call
  /// `setState` — during a build of one of its own descendants. The next
  /// [step] applies it instead, from the between-frames hook where a metrics
  /// change belongs.
  void attach(void Function(double fraction, {required bool animate}) run) =>
      _run = run;

  /// **[_height] is deliberately left alone.** It records what is on the
  /// *view*, and unmounting the tree does not take it off — the host is gone,
  /// so nothing can. Zeroing it here is what made a raised keyboard survive
  /// into the next branch of a `split`: [reset] then believed there was
  /// nothing to put back, and the fresh app was laid out against 336 points of
  /// keyboard nobody had asked for.
  ///
  /// The view itself is not written here either, because this runs from a
  /// `dispose` inside a build and a metrics change there is a `setState` in
  /// `MediaQuery.fromView`. [reset] does it, from between the replays.
  void detach() => _run = null;

  /// Samples the app — called between the frames of whatever [Settle] policy
  /// is running.
  ///
  /// Cheap and idempotent: it reads one bool and, when that bool disagrees
  /// with where the slide is heading, points the ticker somewhere else.
  void step() => _run?.call(_want, animate: true);

  /// Puts it where the mode says at once, with no slide — what a scenario's
  /// own `show`/`hide` verb does, since an author asking for it explicitly is
  /// asking about the layout rather than about the animation.
  void jumpTo(KeyboardMode next) {
    mode = next;
    _run?.call(_want, animate: false);
  }

  /// The platform closing the IME without the app being touched — a swipe down
  /// on Android, the dismiss key on an iPad.
  ///
  /// It makes the app **let go**: the focused field is unfocused, which is what
  /// takes the keyboard away rather than the artwork being hidden under a still
  /// focused form. Back to [KeyboardMode.auto] with it, so a keyboard held up
  /// by hand is genuinely dismissed rather than put straight back by the next
  /// sample.
  void dismiss() {
    mode = KeyboardMode.auto;
    primaryFocus?.unfocus();
    var input = tester.binding.testTextInput;
    if (input.isRegistered) input.hide();
    _run?.call(0, animate: false);
  }

  /// Puts everything back — the view included.
  ///
  /// Called when a replay tears its tree down: a split's second branch starts
  /// from a fresh app, and a keyboard left up would be over a form nobody has
  /// touched yet.
  void reset() {
    mode = KeyboardMode.auto;
    write(0);
  }

  /// The three numbers, on the view — through [stageKeyboard], which is the
  /// same call the previews harness stages a canvas's keyboard with. Called by
  /// the host widget on every tick of the slide.
  void write(double height) {
    // Guarded, and not only for speed: the setter fires `onMetricsChanged`
    // whatever it is handed, and a no-op write during the wrong phase is still
    // a `setState` inside `MediaQuery.fromView`.
    if (_height == height) return;
    _height = height;
    if (height <= 0) {
      // Down, which `stageKeyboard` deliberately will not say — it stages a
      // keyboard, and taking one away is putting the device's own safe areas
      // back rather than subtracting nothing from them.
      var view = tester.view;
      var device = view.viewPadding;
      view.viewInsets = FakeViewPadding.zero;
      view.padding = device;
      return;
    }
    stageKeyboard(tester, height);
  }
}

/// The slab, and the ticker that slides it.
///
/// **Both halves in one widget, because both need the tree.** The picture has
/// to be somewhere; the animation has to be a real `Ticker`, and a ticker
/// needs a `TickerProvider`, which is a thing only a `State` in the pumped
/// tree has. What the ticker *writes* is the view — see [ScenarioKeyboard] —
/// so the numbers reach every `MediaQuery` in the app and not only the subtree
/// under this widget.
///
/// Above the app and inside the pumped tree, so **every capture that exists
/// already contains it** — step shots, motion frames, the web export — with no
/// compositing step anywhere.
class ScenarioKeyboardSlab extends StatefulWidget {
  const ScenarioKeyboardSlab({
    super.key,
    required this.driver,
    required this.child,
  });

  final ScenarioKeyboard driver;
  final Widget child;

  @override
  State<ScenarioKeyboardSlab> createState() => _ScenarioKeyboardSlabState();
}

class _ScenarioKeyboardSlabState extends State<ScenarioKeyboardSlab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: ScenarioKeyboard.raise,
  )..addListener(_onTick);

  @override
  void initState() {
    super.initState();
    widget.driver.attach(_to);
  }

  @override
  void dispose() {
    widget.driver.detach();
    _slide.dispose();
    super.dispose();
  }

  /// Points the slide at [fraction]. Idempotent: pointing it where it is
  /// already going does nothing, which is what lets [ScenarioKeyboard.step]
  /// run before every frame without restarting anything.
  void _to(double fraction, {required bool animate}) {
    if (!animate) {
      _target = fraction;
      _slide
        ..stop()
        ..value = fraction;
      return;
    }
    if (_target == fraction) return;
    _target = fraction;
    _slide.animateTo(fraction);
  }

  /// Where the slide is heading, so pointing it there again is free.
  double? _target;

  void _onTick() {
    // The clock the animation runs on is fake, so this whole slide costs a
    // handful of pumps and no wall time at all.
    widget.driver.write(_slide.value * widget.driver.deviceHeight);
  }

  // Off the view's own insets rather than off the controller, so the picture
  // cannot disagree with the layout: they are the same number, and the app met
  // it first. Shared with the previews harness, which stages a keyboard from a
  // canvas and needs the same picture.
  @override
  Widget build(BuildContext context) => ViewKeyboardSlab(child: widget.child);
}
