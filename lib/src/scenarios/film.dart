import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'aim.dart';
import 'film_cursor.dart';
import 'film_settings.dart';
import 'motion.dart';

export 'film_settings.dart';

/// Records a scenario as a film: every pumped frame, the cursor over it, and
/// the beats that say what each stretch of it is.
///
/// The one sink that is also a *scheduler*. [ScenarioMotionRecorder] follows a
/// settle loop it does not own; this one both follows the settle loops — the
/// same `record:` hook, so no verb had to learn anything — and drives loops of
/// its own between them, which is where a pause, a travel and a press come
/// from. Those beats pump the clock without acting, so a spinner keeps
/// spinning and a game keeps playing while the "user" is doing nothing. That
/// is the whole reason a film is a re-run rather than a post-process: a hold
/// over a run that already happened is one still repeated.
class ScenarioFilm implements ScenarioFrameSink {
  ScenarioFilm(
    this.settings, {
    required this.scenario,
    this.touch = true,
    this.beforePump,
  }) {
    // The checked-mode banner is the app's own widget and a film is of the
    // app, so this is the one thing a film run turns off in the tree it is
    // filming: nobody puts a debug ribbon on a landing page, and asking every
    // project to set `debugShowCheckedModeBanner: false` to be filmable would
    // be asking them to change their app for our benefit. Put back by
    // [finish], because a scenario run after this one is evidence again.
    WidgetsApp.debugAllowBannerOverride = false;
    var directory = Directory(settings.directory);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);
  }

  final FilmSettings settings;

  /// The scenario being filmed, for the timeline and for the refusal a second
  /// one earns.
  final String scenario;

  /// Whether the stage is touched or pointed at — a fingertip or an arrow.
  /// The stage's own answer, never a setting: a film showing an arrow on a
  /// phone is showing something that never happens.
  final bool touch;

  /// Run before every frame the film pumps of its own — the same hook the
  /// settle policies give the keyboard, and for the same reason: a slab that
  /// only moves between a *policy's* frames does not move at all during a
  /// beat, and the keyboard would arrive after the typing it is for.
  final void Function()? beforePump;

  late final _cursor = ScenarioFilmCursor(touch: touch);

  @override
  Duration get interval => settings.frame;

  /// Frames kept so far, which is also the next frame's number.
  int get frames => _frames;
  var _frames = 0;

  /// Frames refused by [FilmSettings.maxFrames].
  int get dropped => _dropped;
  var _dropped = 0;

  final _banked = <_Banked>[];
  final _samples = <Map<String, Object?>>[];
  final _beats = <Map<String, Object?>>[];
  Map<String, Object?>? _beat;

  /// Where the pointer is, in the view's logical pixels — the space
  /// [ScenarioAim] is in, so a target's point needs no transform.
  ///
  /// Null until the first beat gives it somewhere to be: a film that opens on
  /// a cursor parked in the middle of the screen opens on a lie about a user
  /// who has not arrived yet.
  Offset? _pointer;
  var _down = false;

  /// The frame the current press went down on, kept after the finger lifts:
  /// the ripple outlives the press, which is what makes a tap read as a tap
  /// rather than as a cursor that flickered.
  int? _pressedAt;

  int? _width;
  int? _height;

  /// Keeps whatever is on screen, at the film's scale.
  ///
  /// Sync, and deliberately: `toImageSync` rasterises without leaving
  /// `FakeAsync`, so the pump loop pays for a frame's pixels once, later, in
  /// the `runAsync` [flush] opens for a whole batch of them.
  @override
  void capture(WidgetTester tester) {
    if (_frames >= settings.maxFrames) {
      _dropped++;
      return;
    }
    var view = tester.binding.renderViews.singleOrNull;
    if (view == null) return;
    // No root layer before the first paint, which is not an error: it is the
    // film not having started yet.
    var layer = view.debugLayer;
    if (layer is! OffsetLayer) return;
    var dpr = view.flutterView.devicePixelRatio;
    var image = layer.toImageSync(
      Offset.zero & (view.size * dpr),
      pixelRatio: settings.scale / dpr,
    );
    if (_pointer case var at?) {
      _samples.add({
        'frame': _frames,
        'x': _round(at.dx),
        'y': _round(at.dy),
        if (_down) 'down': true,
      });
    }
    _banked.add(
      _Banked(image, _pointer, _down, switch (_pressedAt) {
        null => null,
        var at => (_frames - at) / settings.fps,
      }),
    );
    _frames++;
  }

  /// Writes the bank out when it is full enough to be worth a turn of the real
  /// event loop. Called by the settle loops after every frame they capture.
  @override
  Future<void> flush(WidgetTester tester) async {
    if (_banked.length < settings.batch) return;
    await _write(tester);
  }

  /// The opening hold: the app is on screen and nothing has been touched.
  Future<void> open(WidgetTester tester) async {
    _mark('open');
    await _hold(tester, settings.open);
  }

  /// Flies the cursor to what the verb is about to act on, and presses.
  ///
  /// Runs *between* the target resolving and the gesture firing, which is the
  /// only moment both facts are true: the box has been measured, and the app
  /// has not yet been touched. The frames it pumps are the app's own — it is
  /// still running, and on a screen that animates by itself the travel is not
  /// a still with a dot sliding over it.
  Future<void> approach(
    WidgetTester tester,
    ScenarioAim aim, {
    String? verb,
    String? target,
  }) async {
    var (x, y) = aim.point;
    var to = Offset(x, y);
    var from = _pointer ?? _offstage(tester, to);
    _mark('travel', verb: verb, target: target);
    // What separates a hand from a `lerp`: how long the reach takes, and how
    // the speed is spent along it. See [_travelFor] and [_reach].
    await _hold(
      tester,
      _travelFor((to - from).distance),
      move: (t) => _pointer = _reach(from, to, t),
      // A mouse really moves, and a desktop app answers: rows highlight and
      // buttons tint as the pointer crosses them, which is most of what makes
      // a desktop reel look like somebody using the app rather than a
      // slideshow with an arrow on it. A phone has no hover, so nothing is
      // dispatched there and the mark is the whole of it.
      hover: touch ? null : tester,
    );
    _pointer = to;
    // Arrived, not yet pressed. See [FilmSettings.aim].
    _mark('aim', verb: verb, target: target);
    await _hold(tester, settings.aim);
    _mark('press', verb: verb, target: target);
    _down = true;
    _pressedAt = _frames;
    // A held press is held. `tester.longPress` spends no fake time — it
    // dispatches a down, a delay the fake clock swallows and an up — so
    // without this the two verbs are the same picture, and which one it was
    // is the whole difference between opening a menu and pressing a button.
    await _hold(
      tester,
      verb == 'longPress' && settings.press < _longPress
          ? _longPress
          : settings.press,
    );
    _mark('act', verb: verb, target: target);
  }

  /// Names the stretch about to be filmed — the verb's own frames.
  ///
  /// Marked by every verb, including the ones with no finger: a beat is how
  /// the timeline says what a stretch of film *is*, and a `scrollTo` that
  /// named nothing would leave its frames belonging to whatever came before.
  void act({String? verb, String? target}) =>
      _mark('act', verb: verb, target: target);

  /// How long a `longPress` is held for, when the beat is shorter.
  ///
  /// Material's own threshold is 500ms and this is what a viewer has to *see*
  /// to read the press as held, so it is the floor rather than a setting.
  static const _longPress = Duration(milliseconds: 550);

  /// Types [text] into whatever [set] puts it in, a character at a time.
  ///
  /// `enterText` sets the whole value in one pump, which in a film reads as a
  /// paste — the single most obviously synthetic moment there is. So the verb
  /// hands its setter over and the pacing is decided here, where every other
  /// beat's is.
  ///
  /// The finger lifts first: it tapped the field, and what types is not it.
  Future<void> type(
    WidgetTester tester,
    String text,
    Future<void> Function(String value) set, {

    /// Where the field is *now* — asked every frame while the keyboard
    /// arrives, because it does not arrive alone. A keyboard takes a third of
    /// the screen and the form goes up with it, and a finger left at the
    /// coordinate it tapped ends up parked in the middle of the keyboard,
    /// about to press a key it never presses. It rides the field instead.
    Offset? Function()? follow,
  }) async {
    _down = false;
    // **Focus first, and let the keyboard arrive.** On a phone the field is
    // tapped, the keyboard slides up, and *then* the words appear; typing into
    // a screen with no keyboard on it and raising one afterwards is the order
    // nothing does. The empty value is what focuses the editable — the same
    // call the characters go in through, so there is no second way in.
    await set('');
    _mark('focus', verb: 'enterText');
    await _untilQuiet(tester, follow: follow);
    _mark('type', verb: 'enterText', target: text);
    for (var i = 1; i <= text.length; i++) {
      await set(text.substring(0, i));
      // A word gap. The cheapest unevenness there is, and unevenness is most
      // of what separates typing from a ticker.
      await _hold(
        tester,
        text[i - 1] == ' ' ? settings.typing * 1.6 : settings.typing,
      );
    }
    // Whatever the field does about the text it now has belongs to the verb,
    // not to the typing — the same handover [approach] makes after its press.
    _mark('act', verb: 'enterText');
  }

  /// Drags the finger by [by], a frame at a time, from wherever it is.
  ///
  /// The app moves *because* the finger does, so the two have to move
  /// together: a scenario's own drag dispatches down, move and up with no
  /// frames between them, and a film of it shows a list that teleports.
  ///
  /// [over] is the author's own duration where the verb named one — a fling,
  /// where the velocity is the point — and null otherwise. That difference is
  /// the whole of what happens at the end: a fling lifts while still moving,
  /// and a plain drag holds still first, reporting the same position for long
  /// enough that the velocity tracker estimates zero and the list stops where
  /// the suite's own drag stopped it.
  Future<void> dragBy(WidgetTester tester, Offset by, {Duration? over}) async {
    if (_pointer == null) return;
    _mark('drag', verb: 'drag');
    await _swipe(tester, by, over: over);
    _mark('act', verb: 'drag');
  }

  /// Swipes the pane until [until] says the target is there.
  ///
  /// `scrollTo` is the one verb that acts on a *region* rather than on a point,
  /// and the mark on the step says so — which is right for the step and wrong
  /// for a film: a list that scrolls itself is the one thing in a reel that
  /// reads as a bug rather than as a user. So the finger does what a thumb
  /// does, once per iteration of the walk the verb was going to take anyway:
  /// land in the pane, drag by the step, lift, reach back, again.
  ///
  /// Deliberately no velocity, exactly as [dragBy] has none by default: the
  /// walk moves the list by [by] per iteration and the suite's own does too, so
  /// a filmed `scrollTo` stops on the same iteration and leaves the list where
  /// the suite leaves it.
  Future<void> scroll(
    WidgetTester tester, {
    required Rect pane,
    required Offset by,
    required bool Function() until,
    required int maxScrolls,
  }) async {
    // Centred in the pane, so the whole swipe stays on the thing it scrolls.
    var start = Offset(
      (pane.center.dx - by.dx / 2).clamp(pane.left + 8, pane.right - 8),
      (pane.center.dy - by.dy / 2).clamp(pane.top + 8, pane.bottom - 8),
    );
    for (var swipe = 0; swipe < maxScrolls && !until(); swipe++) {
      var from = _pointer ?? _offstage(tester, start);
      _mark('travel', verb: 'scrollTo');
      await _hold(
        tester,
        // The reach back between swipes is shorter than a reach to a button:
        // the hand is already there, and a thumb returning to swipe again is
        // the quickest movement in the vocabulary.
        swipe == 0
            ? _travelFor((start - from).distance)
            : settings.travel * 0.5,
        move: (t) => _pointer = _reach(from, start, t),
      );
      _pointer = start;
      if (swipe == 0) {
        _mark('aim', verb: 'scrollTo');
        await _hold(tester, settings.aim);
      }
      _mark('swipe', verb: 'scrollTo');
      await _swipe(tester, by);
    }
    _mark('act', verb: 'scrollTo');
  }

  /// One drag: down where the cursor is, along [by] a frame at a time, and up.
  ///
  /// [over] is the author's own duration where the verb named one — a fling,
  /// where the velocity is the point — and null otherwise. That difference is
  /// the whole of what happens at the end: a fling lifts while still moving,
  /// and a plain drag holds still first, reporting the same position for long
  /// enough that the velocity tracker estimates zero and the list stops where
  /// the suite's own drag stopped it.
  Future<void> _swipe(WidgetTester tester, Offset by, {Duration? over}) async {
    var start = _pointer;
    if (start == null) return;
    var length = over ?? settings.drag;
    var frames = math.max(
      1,
      (length.inMicroseconds / interval.inMicroseconds).round(),
    );
    _down = true;
    _pressedAt ??= _frames;
    var gesture = await tester.startGesture(start);
    try {
      for (var i = 1; i <= frames; i++) {
        // Eased like a reach, for the same reason: a finger starts and stops.
        var t = i / frames;
        var e = t * t * t * (10 - 15 * t + 6 * t * t);
        _pointer = start + by * e;
        await gesture.moveTo(_pointer!);
        beforePump?.call();
        await tester.pump(interval);
        capture(tester);
        await flush(tester);
      }
      if (over == null) {
        for (var i = 0; i < _stillFrames; i++) {
          // Stationary *moves*, not stillness: a finger resting on glass keeps
          // reporting, and it is those samples that bring the estimate down.
          // Pumping without them leaves the tracker holding the last velocity
          // it saw and the list flies on.
          await gesture.moveTo(_pointer!);
          beforePump?.call();
          await tester.pump(interval);
          capture(tester);
          await flush(tester);
        }
      }
    } finally {
      await gesture.up();
      _down = false;
    }
  }

  /// How long the finger rests before it lifts from a drag that is not a
  /// fling. A velocity estimate looks back 100ms, so this covers it.
  static const _stillFrames = 4;

  /// The finger comes up. The verb's own frames — the transition it started —
  /// are captured by the settle loop that follows, through [capture].
  void release() => _down = false;

  /// The hold after a verb has settled.
  ///
  /// The first one is [FilmSettings.open] long rather than [FilmSettings.dwell]:
  /// the first verb of a scenario is the `pumpWidget` that puts the app on
  /// screen, and the pause a reader needs there is the one at the top of the
  /// film.
  Future<void> dwell(WidgetTester tester) async {
    var first = !_opened;
    _opened = true;
    _mark(first ? 'open' : 'dwell');
    await _hold(tester, first ? settings.open : settings.dwell);
  }

  var _opened = false;

  /// The last hold, so the clip does not cut on the frame the last verb
  /// happened to land on.
  Future<void> close(WidgetTester tester) async {
    _mark('close');
    await _hold(tester, settings.close);
  }

  /// Writes what is left and the timeline beside it.
  ///
  /// The timeline is written whatever happened, a film cut short included: it
  /// is what the host reads to know how many frames to expect and what they
  /// are, and a run that failed halfway is a fact worth having in a file
  /// rather than a directory of numbers to guess at.
  Future<void> finish(WidgetTester tester) async {
    WidgetsApp.debugAllowBannerOverride = true;
    _closeBeat();
    await _write(tester);
    _writeJson(timelineFileName, {
      'version': 1,
      'scenario': scenario,
      if (settings.branches.isNotEmpty) 'branches': settings.branches,
      'fps': settings.fps,
      'scale': settings.scale,
      'width': _width ?? 0,
      'height': _height ?? 0,
      'format': 'rgba8888',
      'pointer': touch ? 'touch' : 'mouse',
      'frames': _frames,
      if (_dropped > 0) 'dropped': _dropped,
      'composeMs': _composing.elapsedMilliseconds,
      'writeMs': _writing.elapsedMilliseconds,
      'beats': _beats,
      'samples': _samples,
    });
  }

  /// The name of the timeline, beside the frames it describes. Written last:
  /// its existence is how a drain knows the film is complete.
  static const timelineFileName = 'film.json';

  /// The name of the head — the size and the pace, written with the first
  /// frame so an encoder can be opened while the rest are still being drawn.
  static const headFileName = 'film.head.json';

  /// Pumps [length] of film, a frame at a time, keeping every one of them.
  ///
  /// [move] is called *before* each pump with how far through the beat it is,
  /// so the cursor is where it should be on the frame that is about to be
  /// drawn rather than one frame behind it.
  Future<void> _hold(
    WidgetTester tester,
    Duration length, {
    void Function(double t)? move,
    WidgetTester? hover,
  }) async {
    var count = (length.inMicroseconds / interval.inMicroseconds).round();
    for (var i = 0; i < count; i++) {
      move?.call((i + 1) / count);
      if (hover != null && _pointer != null) await _hoverTo(hover, _pointer!);
      beforePump?.call();
      await tester.pump(interval);
      capture(tester);
      await flush(tester);
    }
  }

  /// Pumps until the screen stops asking for frames, or [ceiling] runs out.
  ///
  /// A beat that waits for something the app is *doing* rather than for a
  /// length of time — the keyboard sliding up is the one this exists for. The
  /// ceiling is not optional: a screen with a spinner on it never goes quiet,
  /// and a film must not hold on one until it does.
  Future<void> _untilQuiet(
    WidgetTester tester, {
    Duration ceiling = const Duration(milliseconds: 700),
    Offset? Function()? follow,
  }) async {
    var spent = Duration.zero;
    while (tester.binding.hasScheduledFrame && spent < ceiling) {
      if (follow?.call() case var at?) _pointer = at;
      beforePump?.call();
      await tester.pump(interval);
      spent += interval;
      capture(tester);
      await flush(tester);
    }
  }

  /// Moves a real mouse to [at], so the app under the cursor knows it is under
  /// the cursor.
  ///
  /// One pointer for the whole film, added on the first move: a second
  /// `addPointer` for the same device would be a second mouse, and the
  /// framework tracks them by id.
  Future<void> _hoverTo(WidgetTester tester, Offset at) async {
    var mouse = _mouse ??= await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    if (_mouseAdded) {
      await mouse.moveTo(at);
    } else {
      _mouseAdded = true;
      await mouse.addPointer(location: at);
    }
  }

  TestGesture? _mouse;
  var _mouseAdded = false;

  /// How long a reach of [distance] takes.
  ///
  /// Fitts, roughly: pointing time grows with the *logarithm* of the distance,
  /// not with the distance. A cursor that spends the same 350ms crossing a
  /// whole screen and hopping to the chip beside it is the least human thing
  /// about it — the long move looks hurried and the short one looks like it is
  /// thinking about it.
  ///
  /// [FilmSettings.travel] names the nominal, which is a phone-screen sweep;
  /// the clamp keeps a hop from being instant and a diagonal from dawdling.
  Duration _travelFor(double distance) {
    var factor =
        math.log(1 + distance / 64) / math.log(1 + _nominalTravel / 64);
    return settings.travel * factor.clamp(0.45, 1.6);
  }

  /// The reach [FilmSettings.travel] is quoted for — about a phone screen.
  static const _nominalTravel = 400.0;

  /// Where the cursor is [t] of the way through a reach.
  ///
  /// The speed profile is the **minimum-jerk** polynomial — `10t³ − 15t⁴ +
  /// 6t⁵` — which is the classic model of a human reaching for something and
  /// is visibly gentler at both ends than the `easeInOut` this used to be: it
  /// leaves rest slowly, spends its speed in the middle, and settles onto the
  /// target rather than arriving at it.
  ///
  /// In a straight line, and that was tried the other way: an arm is a pair of
  /// hinges, so a real reach arcs, and a Bézier bowed 7% perpendicular to the
  /// line is what that looks like. Watched, it reads as a drift rather than as
  /// a hand — the owner's call, and the honest one, since the timing and the
  /// speed profile are what carry this and the bow was the least evidenced of
  /// the three.
  Offset _reach(Offset from, Offset to, double t) =>
      Offset.lerp(from, to, t * t * t * (10 - 15 * t + 6 * t * t))!;

  /// Where a cursor that has not arrived yet comes from: off the bottom edge,
  /// under the point it is heading for. A first tap then reads as a hand
  /// coming into frame rather than as a dot fading in over the button.
  Offset _offstage(WidgetTester tester, Offset toward) {
    var size = tester.binding.renderViews.firstOrNull?.size;
    return Offset(toward.dx, (size?.height ?? toward.dy) + 48);
  }

  void _mark(String kind, {String? verb, String? target}) {
    _closeBeat();
    _beat = {'kind': kind, 'frame': _frames, 'verb': ?verb, 'target': ?target};
  }

  void _closeBeat() {
    if (_beat case var beat?) {
      var length = _frames - (beat['frame']! as int);
      // A beat that drew nothing is not in the film — the frames are what a
      // beat is, and an entry claiming none of them would put a caption on a
      // moment nobody can see.
      if (length > 0) _beats.add({...beat, 'frames': length});
    }
    _beat = null;
  }

  /// Rasterises the bank, draws the cursor on it, and writes one file per
  /// frame.
  ///
  /// Every frame is written to a `.part` name and renamed into place, because
  /// the host reads this directory while it is being written: a numbered file
  /// that exists is a whole frame, and there is no other agreement to keep.
  Future<void> _write(WidgetTester tester) async {
    if (_banked.isEmpty) return;
    var banked = List.of(_banked);
    _banked.clear();
    _writing.start();
    await tester.runAsync(() async {
      for (var frame in banked) {
        _composing.start();
        var image = _compose(frame);
        _composing.stop();
        var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        _width ??= image.width;
        _height ??= image.height;
        image.dispose();
        if (data == null) {
          // Fatal rather than skipped. The frames are numbered without gaps
          // and an encoder drains them in order, so a missing one is not a
          // frame lost — it is the rest of the film never arriving.
          throw StateError(
            'frame $_written of the film rasterised to nothing, and a film '
            'with a hole in it cannot be encoded',
          );
        }
        // The first frame is the first moment anything knows how big this
        // film is, and an encoder has to be opened on a size before it can be
        // fed. So the head goes out here rather than waiting for the timeline
        // at the end — that is what lets the encode run *beside* the render
        // instead of after it.
        if (_written == 0) _writeHead();
        var path = p.join(
          settings.directory,
          '${_written.toString().padLeft(6, '0')}.raw',
        );
        File('$path.part')
          ..writeAsBytesSync(data.buffer.asUint8List())
          ..renameSync(path);
        _written++;
      }
    });
    _writing.stop();
  }

  var _written = 0;

  /// What drawing the cursor over the frames costs.
  ///
  /// Reported rather than assumed: the cursor is painted onto the rasterised
  /// frame instead of into the app's tree, and the price of that separation is
  /// a second raster per frame. Worth knowing what it is before anyone trades
  /// it for a layer appended to the tree.
  final _composing = Stopwatch();

  /// And what the whole spill costs — rasterise, read back, write. The
  /// interesting half of [_composing], since `toImageSync` defers the raster
  /// itself to the read back.
  final _writing = Stopwatch();

  /// What an encoder needs before the film is finished: how to cut the stream
  /// into frames, and how fast to play them.
  ///
  /// Raw video carries no header, so a drain cannot open an encoder until it
  /// knows the size — and the timeline that would say so is written at the
  /// end. This is that size, written beside the first frame, and it is what
  /// lets the encode run *beside* the render rather than after it.
  void _writeHead() => _writeJson(headFileName, {
    'version': 1,
    'scenario': scenario,
    'fps': settings.fps,
    'scale': settings.scale,
    'width': _width ?? 0,
    'height': _height ?? 0,
    'format': 'rgba8888',
    'pointer': touch ? 'touch' : 'mouse',
  });

  void _writeJson(String name, Map<String, Object?> body) =>
      File(p.join(settings.directory, name))
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(body));

  /// The app's frame with the cursor over it.
  ///
  /// **Over**, never inside: the cursor is not in the widget tree, so it
  /// cannot change a layout, trip a rebuild or land in a screenshot. The cost
  /// is a second raster per frame, which is the price of that separation and
  /// is measured in the design against appending a layer instead.
  ui.Image _compose(_Banked frame) {
    if (frame.pointer == null) return frame.image;
    var recorder = ui.PictureRecorder();
    var canvas = ui.Canvas(recorder);
    canvas
      ..drawImage(frame.image, Offset.zero, ui.Paint())
      // Scaled once, so the cursor is drawn in the app's own logical points
      // and a fingertip is a fingertip at every film scale.
      ..save()
      ..scale(settings.scale);
    _cursor.paint(
      canvas,
      frame.pointer!,
      down: frame.down,
      sincePress: frame.sincePress,
    );
    canvas.restore();
    var picture = recorder.endRecording();
    var composed = picture.toImageSync(frame.image.width, frame.image.height);
    picture.dispose();
    frame.image.dispose();
    return composed;
  }

  static double _round(double value) => (value * 10).roundToDouble() / 10;
}

class _Banked {
  _Banked(this.image, this.pointer, this.down, this.sincePress);

  final ui.Image image;
  final Offset? pointer;
  final bool down;

  /// Seconds since the last press began, or null before the first one.
  final double? sincePress;
}

/// The film this process is rendering, if any.
///
/// One per run and not one per scenario: the frames are numbered into a single
/// directory and encoded as one clip, so a request whose selector matched two
/// scenarios has asked for something that cannot be made. Refused here, by the
/// second scenario to start, rather than discovered as a video of two flows
/// spliced together.
ScenarioFilm? _filming;

/// Forgets the film in progress, so a test file can render more than one.
@visibleForTesting
void resetFilms() => _filming = null;

ScenarioFilm startFilm(
  FilmSettings settings, {
  required String scenario,
  required bool touch,
  void Function()? beforePump,
}) {
  if (_filming case var already? when already.scenario != scenario) {
    throw ScenarioFilmRefusal(
      'a film is one scenario, and this run matched both '
      '`${already.scenario}` and `$scenario`. Name one with `--scenario=`.',
    );
  }
  return _filming ??= ScenarioFilm(
    settings,
    scenario: scenario,
    touch: touch,
    beforePump: beforePump,
  );
}
