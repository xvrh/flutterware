import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

import 'profile.dart';
import 'run_args.dart';
import 'run_listener.dart';
import 'settle.dart';
import 'target.dart';

/// A scenario: a widget test with per-step screenshots.
///
/// `scenario` is `testWidgets` plus a [ScenarioTester] — so every scenario is
/// an ordinary widget test, runnable by a bare `flutter test` with no daemon
/// and no GUI. Design: `docs/superpowers/specs/2026-07-30-scenarios-design.md`.
///
/// ```dart
/// scenario('Onboarding', (s) async {
///   await s.pumpWidget(MyApp());
///   await s.tap('NEXT');
///   await s.enterText('Email', 'x@example.com', shot: Shot('Filled form'));
///   await s.screen('Home');
///   expect(find.text('Done'), findsOneWidget);
/// });
/// ```
/// Collects the names `scenario()` declares, while the harness declares one
/// file.
///
/// The harness runs *every* declared test in the group it walks, and a
/// `test/scenarios/` folder may hold ordinary `testWidgets` too — which
/// produce no steps, cannot be opened in the panel, and were being run
/// invisibly. Knowing which tests are scenarios cannot be done by looking at
/// the built group (a test is a test), and reading it off the source would
/// mean the runner and the syntactic scan disagreeing about non-literal
/// names. Recording it as it is declared is the one answer that is true by
/// construction.
///
/// Null outside the harness, where nothing is collecting.
List<String>? scenarioDeclarationSink;

@isTest
void scenario(
  String description,
  Future<void> Function(ScenarioTester s) body, {
  Shots shots = Shots.auto,
  Settle settle = Settle.standard,
  bool? skip,
  Timeout? timeout,
  Object? tags,
}) {
  // Captured as the scenario is *declared*, not read when it runs: a matrix
  // declares this same body once per assignment, and each declaration keeps
  // the one it was made under.
  var assignment = scenarioAmbientAssignment;
  var name =
      scenarioAmbientIsMatrix && assignment != null && !assignment.isEmpty
      ? '$description [${assignment.label}]'
      : description;

  scenarioDeclarationSink?.add(name);

  testWidgets(name, skip: skip, timeout: timeout, tags: tags, (tester) async {
    var origin = scenarioRunArgs?.clockOrigin ?? _scenarioClockOrigin;
    if (origin == null) {
      return _runScenario(tester, description, body, shots, settle, assignment);
    }
    // Pinned, but still ticking with FakeAsync: the offset from where this
    // scenario's fake clock started is what `s.wait` moves, so a flow that
    // waits a day still reads a day later — from a date that is the same on
    // every run.
    var started = tester.binding.clock.now();
    return withClock(
      Clock(() => origin.add(tester.binding.clock.now().difference(started))),
      () => _runScenario(tester, description, body, shots, settle, assignment),
    );
  });
}

/// What `clock.now()` reads at the start of every scenario, from the host —
/// a dart-define first, then the environment, the same pair
/// `screenshots-destination` uses.
DateTime? get _scenarioClockOrigin {
  const define = String.fromEnvironment('fw.clock');
  var raw = define.isNotEmpty ? define : Platform.environment['FW_CLOCK'];
  if (raw == null || raw.isEmpty) return null;
  return DateTime.parse(raw);
}

Future<void> _runScenario(
  WidgetTester tester,
  String description,
  Future<void> Function(ScenarioTester s) body,
  Shots shots,
  Settle settle,
  ScenarioAssignment? assignment,
) async {
  var restore = _applyRunArgs(tester, assignment);
  _countFrames(tester);
  var state = _ReplayState();
  try {
    // The split-replay loop: the body runs once per path through its
    // `split`s, depth-first — a body with none runs once. Every replay
    // starts from the top, so its `pumpWidget` rebuilds the app from
    // scratch; steps already captured on a shared prefix are recognised by
    // position and not captured again.
    var first = true;
    do {
      state.plan.beginRun();
      if (!first) {
        // Tear the tree down first: re-pumping the same app widget over
        // its previous self keeps every State alive — the navigator stack
        // included — and a replay must start from nothing.
        await tester.pumpWidget(const SizedBox.shrink());
      }
      first = false;
      var s = ScenarioTester._(
        tester,
        description,
        shots,
        settle,
        state,
        assignment,
      );
      try {
        await body(s);
      } catch (error, stack) {
        // One catch for the whole body, so every failure has a picture of
        // the frame it broke on — whatever raised it: a verb, a bare
        // `expect`, the app's own build. A capture that fails in turn is
        // swallowed: it may never mask what it was called about.
        try {
          await s._captureFailure(error);
        } catch (_) {}
        // Rethrown with the original stack, so the report still points at
        // the user's line; only the message gains its split branch.
        Error.throwWithStackTrace(s._inContext(error), stack);
      }
    } while (state.plan.advance());
  } finally {
    // Both before the body ends, not in a tearDown: the binding checks its
    // debug variables — and complains about a live semantics handle — at
    // the end of the body, before tearDowns run.
    state.disposeSemantics();
    restore?.call();
  }
}

/// A failure raised inside a `split` branch, wrapping the real error with the
/// path that reached it — `'a cappuccino › large cup'`. Without it a failing
/// branch reports only the scenario's name, and which of the paths broke is
/// nowhere in the output.
class ScenarioFailure implements Exception {
  ScenarioFailure(this.branch, this.error);

  /// The split choices taken to reach the failure, outermost first.
  final List<String> branch;

  final Object error;

  String get path => branch.join(' › ');

  @override
  String toString() => 'in split branch "$path": $error';
}

/// A verb's target that names no widget, or several — raised before the
/// action rather than after, so the message can say what to do about it.
class ScenarioTargetError implements Exception {
  ScenarioTargetError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Frames drawn under the test binding since the process started.
///
/// Counted by a persistent frame callback registered **once per binding** —
/// they cannot be unregistered, and the harness runs thousands of scenarios
/// through one binding, so one is all there may ever be. What it buys: a step
/// can tell how many frames happened outside the scenario's verbs, which is
/// how a flow says it has a gap in it.
///
/// It counts frames that were actually *drawn*: the test binding's `pump`
/// skips the frame entirely when nothing is scheduled, so an idle pump is not
/// a gap and does not read as one. Only the raw tester making the app do
/// something the flow then misses does.
int _frames = 0;
var _countingFrames = false;

void _countFrames(WidgetTester tester) {
  if (_countingFrames) return;
  _countingFrames = true;
  tester.binding.addPersistentFrameCallback((_) => _frames++);
}

/// What survives across a scenario's replays: which paths ran, which step
/// positions were already captured, and the global step numbering.
class _ReplayState {
  final plan = _SplitPlan();

  SemanticsHandle? _semantics;

  /// Holds the semantics tree open for the rest of the scenario, and pumps
  /// once so the frame the finder reads actually has one.
  ///
  /// `testWidgets` passes `semanticsEnabled: true` by default, so this is a
  /// guarantee rather than a fix: `find.bySemanticsLabel` throws outright
  /// where semantics are off, and a scenario asking for a label should not
  /// rest on someone else's default. Lazy because semantics are not free and their
  /// presence changes what some widgets build — a scenario that never asks
  /// for a label captures exactly what it captured before.
  Future<void> ensureSemantics(WidgetTester tester) async {
    if (_semantics != null) return;
    _semantics = tester.ensureSemantics();
    await tester.pump();
  }

  void disposeSemantics() {
    _semantics?.dispose();
    _semantics = null;
  }

  /// Position key → the emitted step's index. A position seen again on a
  /// later replay's shared prefix is skipped without rendering anything.
  final emitted = <String, int>{};

  var stepCount = 0;
}

/// Depth-first enumeration of a scenario's `split` choices.
///
/// One entry per split encountered along the current path, in order: replay
/// the recorded prefix, then explore `0` at every split found beyond it.
/// [advance] bumps the deepest split that still has an unvisited branch and
/// drops everything after it.
class _SplitPlan {
  final _stack = <({int choice, int count})>[];
  var _cursor = 0;

  void beginRun() => _cursor = 0;

  /// The branch to take at the next split of the current run.
  int choose(int count) {
    if (_cursor < _stack.length) return _stack[_cursor++].choice;
    _stack.add((choice: 0, count: count));
    _cursor++;
    return 0;
  }

  /// The choices consumed so far this run — the position key's path half.
  String get path =>
      [for (var entry in _stack.take(_cursor)) entry.choice].join('.');

  /// Moves to the next unvisited path; false when every path has run.
  bool advance() {
    while (_stack.isNotEmpty && _stack.last.choice + 1 >= _stack.last.count) {
      _stack.removeLast();
    }
    if (_stack.isEmpty) return false;
    _stack.last = (choice: _stack.last.choice + 1, count: _stack.last.count);
    return true;
  }
}

/// Applies the harness's axis assignment through the test binding's own test
/// values, exactly as a hand-written widget test would — so a scenario under
/// an axis and a test that sets `tester.view.physicalSize` itself are the
/// same machinery, and bare `flutter test` (null args) pays nothing.
///
/// Returns the reset, which the caller must run **inside the test body** — a
/// tearDown is too late: the binding verifies its foundation debug variables
/// (`debugDefaultTargetPlatformOverride` among them) at the end of the body,
/// before tearDowns run.
VoidCallback? _applyRunArgs(WidgetTester tester, ScenarioAssignment? ambient) {
  // The runner's assignment wins where there is one: it is answering a request
  // that named its axes. The ambient one is the other lane — a bare
  // `flutter test`, where the folder's profile is the only thing that spoke.
  var args =
      scenarioRunArgs ??
      (ambient == null || ambient.isEmpty
          ? null
          : ScenarioRunArgs.forAssignment(ambient));
  if (args == null) return null;

  var view = tester.view;
  var dispatcher = tester.platformDispatcher;

  var ratio = args.pixelRatio ?? view.devicePixelRatio;
  if (args.pixelRatio != null) view.devicePixelRatio = ratio;
  if (args.size case var size?) view.physicalSize = size * ratio;
  if (args.padding case var padding?) {
    // FakeViewPadding speaks physical pixels; the args speak logical, like
    // the device table they come from.
    var fake = FakeViewPadding(
      left: padding.left * ratio,
      top: padding.top * ratio,
      right: padding.right * ratio,
      bottom: padding.bottom * ratio,
    );
    view.padding = fake;
    view.viewPadding = fake;
  }
  if (args.platform case var platform?) {
    debugDefaultTargetPlatformOverride = platform;
  }
  if (args.locale case var locale?) {
    dispatcher.localeTestValue = locale;
    dispatcher.localesTestValue = [locale];
  }
  if (args.textScale case var scale?) {
    dispatcher.textScaleFactorTestValue = scale;
  }
  if (args.brightness case var brightness?) {
    dispatcher.platformBrightnessTestValue = brightness;
  }
  if (!args.accessibility.isDefault) {
    dispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      boldText: args.accessibility.boldText,
      highContrast: args.accessibility.highContrast,
      invertColors: args.accessibility.invertColors,
    );
  }

  return () {
    debugDefaultTargetPlatformOverride = null;
    view.reset();
    dispatcher.clearAllTestValues();
  };
}

/// Whether a scenario captures a screenshot after every high-level action, or
/// only where a [Shot] or [ScenarioTester.screen] asks for one.
enum Shots { auto, manual }

/// Per-call override of a scenario's screenshot behaviour.
///
/// `Shot('Name')` captures and names the step — a named shot is a primary
/// node in the flow graph, an automatic one is collapsible detail.
/// [Shot.skip] suppresses the capture entirely.
class Shot {
  const Shot(String this.name, {this.tags = const []});

  const Shot._skip() : name = null, tags = const [];

  /// Suppresses the automatic screenshot for one call.
  static const skip = Shot._skip();

  final String? name;
  final List<String> tags;
}

/// Drives one scenario. Wraps the real [WidgetTester] — every method here
/// settles and then captures per the scenario's [Shots] policy; anything done
/// through [tester] directly is plain `flutter_test` and captures nothing.
///
/// Waiting is the same [Settle] policy for every verb, bounded by default, so
/// a screen that animates forever is captured rather than thrown on.
class ScenarioTester {
  ScenarioTester._(
    this.tester,
    this._description,
    this.shots,
    this.settle,
    this._state,
    this.assignment,
  );

  /// The real tester — the escape hatch to the full `flutter_test` surface.
  final WidgetTester tester;

  final Shots shots;

  /// How every verb waits before it captures — overridable per call.
  final Settle settle;

  final String _description;

  /// The axes this scenario is running under, when a folder profile or a CI
  /// list assigned any — what keeps a matrix's captures out of each other's
  /// directories, and what a body reads to adapt an expectation to the screen
  /// it is on. Null under the flutterware runner, which assigns axes per
  /// request rather than per declaration.
  final ScenarioAssignment? assignment;

  /// Shared across replays; everything below is this replay's alone.
  final _ReplayState _state;

  /// Captures since the last split (or the start) — the position key's
  /// ordinal half. Two replays walking the same choice prefix count the same
  /// way, which is what makes a position mean "the same step as last time".
  var _ordinal = 0;

  /// The position of the last capture this replay saw — emitted or
  /// recognised — whose step is the next capture's parent.
  String? _lastPosition;

  /// The branch label owed to the next capture, set on entering a split
  /// branch.
  String? _pendingBranch;

  /// The split choices taken to reach here, by name — the failure message's
  /// context, and never popped, for the same reason the plan's choice path is
  /// not: it describes *this replay*.
  final _branchTrail = <String>[];

  /// The error already given a failed step, so the verb that raised it and
  /// the scenario-level backstop do not both capture one.
  Object? _capturedFailure;

  /// The frame count when the last verb finished — the baseline stray frames
  /// are measured from. Set at construction, which is after the replay's
  /// teardown pump, so tearing the tree down is never anybody's stray frame.
  var _framesAtLastStep = _frames;

  Future<void> pumpWidget(Widget widget, {Shot? shot, Settle? settle}) =>
      _step(shot, settle, () => tester.pumpWidget(widget));

  /// Taps [target] — a `Finder`, a `String` (visible text), a `Key`, an
  /// `IconData`, a `Type`, or a [Target] for the rest (a semantics label, a
  /// tooltip, a scope, an index).
  ///
  /// `dynamic` is a deliberate exception to the house no-dynamic preference:
  /// `tap('NEXT')` / `tap(Icons.add)` / `tap(Keys.next)` read too well to give
  /// up, and the auto-write generator emits exactly the string form.
  Future<void> tap(dynamic target, {Shot? shot, Settle? settle}) => _step(
    shot,
    settle,
    // `warnIfMissed: false` on the underlying verbs because `_resolve` has
    // already decided reachability — and loudly, where the SDK's warning is a
    // console line the flow sails past.
    () async => tester.tap(await _resolve(target, 'tap'), warnIfMissed: false),
  );

  Future<void> longPress(dynamic target, {Shot? shot, Settle? settle}) => _step(
    shot,
    settle,
    () async => tester.longPress(
      await _resolve(target, 'longPress'),
      warnIfMissed: false,
    ),
  );

  Future<void> enterText(
    dynamic target,
    String text, {
    Shot? shot,
    Settle? settle,
  }) => _step(
    shot,
    settle,
    () async => tester.enterText(await _resolve(target, 'enterText'), text),
  );

  /// Drags [target] by [by] — a swipe, a dismiss, a slider, a sheet pulled
  /// down. Negative `dy` moves the finger up the screen, the touch convention
  /// `flutter_test` itself uses.
  Future<void> drag(dynamic target, Offset by, {Shot? shot, Settle? settle}) =>
      _step(
        shot,
        settle,
        () async => tester.drag(
          await _resolve(target, 'drag'),
          by,
          warnIfMissed: false,
        ),
      );

  /// Scrolls until [target] is on screen, then captures it there.
  ///
  /// The scrollable is the first one on screen unless [within] names one — a
  /// widget that *is* a `Scrollable` or contains one. [step] is how far each
  /// drag travels toward the end of the list; make it negative to walk back
  /// toward the start.
  ///
  /// Unlike the other verbs this one starts with a target that matches
  /// nothing — being off screen is the whole point — so it says so itself
  /// when the scrolling never finds it.
  Future<void> scrollTo(
    dynamic target, {
    dynamic within,
    double step = 200,
    int maxScrolls = 50,
    Shot? shot,
    Settle? settle,
  }) => _step(shot, settle, () async {
    var scrollable = within == null
        ? find.byType(Scrollable)
        : find.descendant(
            of: finderForTarget(within),
            matching: find.byType(Scrollable),
            matchRoot: true,
          );
    if (scrollable.evaluate().isEmpty) {
      throw ScenarioTargetError(
        within == null
            ? 'nothing on screen scrolls, so `s.scrollTo` has nothing to walk.'
            : 'nothing under $within scrolls, so `s.scrollTo` has nothing to '
                  'walk.',
      );
    }
    try {
      await tester.scrollUntilVisible(
        finderForTarget(target),
        step,
        // The first, as `flutter_test` itself defaults to: nested scrollables
        // are ordinary, and `within` is how a scenario says which one.
        scrollable: scrollable.first,
        maxScrolls: maxScrolls,
      );
    } on StateError {
      throw ScenarioTargetError(
        'scrolled $maxScrolls times by $step without reaching '
        '${target is String ? '"$target"' : target}. '
        'Wrong direction (try a negative step), wrong scrollable (name one '
        'with `within:`), or it is not in this list at all.',
      );
    }
  });

  /// The platform's back gesture — Android's button, iOS's edge swipe, the
  /// thing that pops a route without a widget to tap.
  ///
  /// Sent as the engine sends it, down `flutter/navigation`, rather than
  /// through the binding's own handler: the message is the public, sanctioned
  /// route, and it exercises the app's `PopScope`s on the way in.
  Future<void> back({Shot? shot, Settle? settle}) => _step(
    shot,
    settle,
    () => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      null,
    ),
  );

  /// Advances the clock by [duration].
  ///
  /// The verbs settle, which waits out *animations*; a pending timer schedules
  /// no frames, so a splash screen that navigates after three seconds needs
  /// the clock moved rather than settled. Instant either way — the clock is
  /// fake.
  Future<void> wait(Duration duration, {Shot? shot, Settle? settle}) =>
      _step(shot, settle, () => tester.pump(duration));

  /// Captures a named screen without performing an action.
  Future<void> screen(
    String name, {
    List<String> tags = const [],
    Settle? settle,
  }) => _step(Shot(name, tags: tags), settle, () async {});

  /// One verb: act, wait per the policy, capture. The settle result rides the
  /// step, so a screen that never stopped animating says so instead of
  /// throwing.
  Future<void> _step(
    Shot? shot,
    Settle? settle,
    Future<void> Function() action,
  ) async {
    // Frames since the previous verb finished: nothing this scenario's verbs
    // drew, so they came from `s.tester` — and whatever they showed is not in
    // the flow. Read before the action, reported on the step it precedes.
    var stray = _frames - _framesAtLastStep;
    bool settled;
    try {
      await action();
      settled = await (settle ?? this.settle).apply(tester);
    } catch (error) {
      // The verb that broke captures its own frame; `scenario`'s catch is the
      // backstop for everything else. Both go through the same once-per-error
      // guard, so an error travelling up the stack yields one failed step.
      await _captureFailure(error);
      rethrow;
    }
    _framesAtLastStep = _frames;
    await _afterStep(shot, settled: settled, stray: stray);
  }

  /// Forks the scenario: every branch runs, each in its own replay of the
  /// whole body — so each branch starts from the exact state this line was
  /// reached with, and the flow graph fans out here.
  ///
  /// ```dart
  /// await s.split({
  ///   'pay by card': () async {
  ///     await s.tap('Pay');
  ///     await s.screen('Receipt');
  ///   },
  ///   'payment fails': () async {
  ///     await s.tap('Pay');
  ///     await s.screen('Error dialog');
  ///   },
  /// });
  /// ```
  ///
  /// Steps before the split are captured once and shared; anything after the
  /// call runs per branch, since by then the paths have genuinely diverged.
  /// Splits nest. Under bare `flutter test` the replays run too, so CI
  /// asserts every path.
  ///
  /// **What a replay does and does not reset.** The widget tree is torn down
  /// and rebuilt from nothing, so each path starts from a fresh app. Anything
  /// *outside* the tree is not: a seeded repository, a registered singleton, a
  /// mock's recorded calls carry from one path into the next.
  ///
  /// The body is what re-runs, so the body is where per-path setup belongs:
  ///
  /// ```dart
  /// scenario('Around the shop', (s) async {
  ///   repo.seed();                          // every path gets a fresh one
  ///   await s.pumpWidget(const ShopApp());
  ///   await s.split({ ... });
  /// });
  /// ```
  ///
  /// A `setUp` will *not* do it. `setUp` runs once per test and a scenario is
  /// one test however many paths it has — which is `package:test`'s own rule,
  /// kept rather than bent: a `setUp` that fired three times for one test
  /// would be a surprise nothing in the file could explain, and its
  /// `tearDown` could not follow it (those run when the test ends).
  Future<void> split(Map<String, Future<void> Function()> branches) async {
    if (branches.isEmpty) return;
    var names = branches.keys.toList();
    var name = names[_state.plan.choose(names.length)];
    // A new segment: positions restart under the extended choice path, and
    // the branch's first capture wears the label.
    _ordinal = 0;
    _pendingBranch = name;
    _branchTrail.add(name);
    try {
      await branches[name]!();
    } catch (error, stack) {
      // Annotated where the branch is, so a failure says which path reached
      // it. The original stack rides along, so the report still points at the
      // user's line; nested splits annotate innermost-first and the outer
      // ones leave the message alone.
      Error.throwWithStackTrace(_inContext(error), stack);
    }
  }

  Future<void> _afterStep(
    Shot? shot, {
    required bool settled,
    required int stray,
  }) async {
    if (identical(shot, Shot.skip)) return;
    if (shot == null && shots == Shots.manual) return;
    await _capture(shot, settled: settled, stray: stray);
  }

  /// [error] with the split branch that reached it, when there was one.
  Object _inContext(Object error) =>
      _branchTrail.isEmpty || error is ScenarioFailure
      ? error
      : ScenarioFailure(List.of(_branchTrail), error);

  /// Resolves a verb's target and insists it names exactly one widget the
  /// pointer can actually reach.
  ///
  /// The same checks the underlying `tap` fails on anyway — made legible, and
  /// made *before* the action, so the message can say what to do rather than
  /// dump the matching render objects.
  Future<Finder> _resolve(dynamic target, String verb) async {
    if (target is Target && target.needsSemantics) {
      await _state.ensureSemantics(tester);
    }
    var finder = finderFor(target);
    var count = finder.evaluate().length;
    var described = target is String ? '"$target"' : '$target';
    if (count == 1) {
      await _ensureReachable(finder, described, verb);
      return finder;
    }
    if (count == 0) {
      throw ScenarioTargetError(
        'nothing matches $described, which `s.$verb` needs. A widget further '
        'down a lazy list is not built yet — `s.scrollTo` walks to it.\n'
        'Visible text: ${_describeVisibleTexts()}',
      );
    }
    throw ScenarioTargetError(
      '$count widgets match $described, and `s.$verb` needs one. '
      'Narrow it: give the widget a Key and use that, or pass a Finder — '
      '`finder.first`, `find.descendant(of: …, matching: …)`.',
    );
  }

  /// Every pointer verb lands at its target's center, so the target must be
  /// reachable there — actionability, checked before the action, where
  /// `flutter_test` prints a console warning after a miss and lets the flow
  /// sail on from the wrong screen.
  ///
  /// Found but unreachable usually means "built but below the fold" — a
  /// `SingleChildScrollView`, a list child inside cache extent — so the verb
  /// first scrolls it into view, as the user it stands in for would. That is
  /// also what keeps one scenario honest across a device matrix: a button
  /// under the fold of the small phone is above it on the tablet, and neither
  /// run should need to say so. What scrolling cannot fix is refused loudly:
  /// covered by another widget, or off screen with nothing scrolling to it.
  Future<void> _ensureReachable(
    Finder finder,
    String described,
    String verb,
  ) async {
    if (_reaches(finder)) return;
    // On a target with no scrollable ancestor `Scrollable.ensureVisible` is a
    // no-op, so the recheck decides — no case to distinguish here.
    await tester.ensureVisible(finder);
    await tester.pump();
    if (_reaches(finder)) return;
    var render = finder.evaluate().single.renderObject! as RenderBox;
    var center = render.localToGlobal(render.size.center(Offset.zero));
    var bounds = Offset.zero & tester.binding.renderViews.single.size;
    throw ScenarioTargetError(
      bounds.contains(center)
          ? '$described is on screen, but `s.$verb` at its center would not '
                'reach it — another widget covers it, or an IgnorePointer/'
                'AbsorbPointer swallows the pointer. `s.tester` is the raw '
                'tester if hitting whatever is on top is the point.'
          : '$described sits off screen at $center and nothing scrolls it '
                'into view.',
    );
  }

  /// Whether a pointer event at the target's center would reach it — the
  /// check `flutter_test`'s `warnIfMissed` makes, as a boolean.
  bool _reaches(Finder finder) {
    var render = finder.evaluate().single.renderObject;
    // No box to aim at: leave it to the underlying verb, whose own errors
    // name the shape problem better than a reachability check can.
    if (render is! RenderBox || !render.hasSize) return true;
    var center = render.localToGlobal(render.size.center(Offset.zero));
    var result = tester.hitTestOnBinding(center);
    return result.path.any(
      (entry) => isRenderObjectAncestorOfTarget(render, entry.target),
    );
  }

  String _describeVisibleTexts() {
    var texts = visibleTexts().where((t) => t.isNotEmpty).toList();
    if (texts.isEmpty) return 'none on screen';
    var shown = texts.take(20).map((t) => '"$t"').join(', ');
    return texts.length > 20 ? '$shown, …' : shown;
  }

  /// Resolves a verb's polymorphic target to a [Finder].
  @visibleForTesting
  Finder finderFor(dynamic target) => finderForTarget(target);

  /// Captures one step.
  ///
  /// Under the flutterware runner the harness listens and receives the bytes.
  /// Standalone (bare `flutter test`), a screenshot is written only when a
  /// destination is configured — via
  /// `--dart-define=screenshots-destination=…` or the
  /// `SCREENSHOTS_DESTINATION` environment variable — and skipped otherwise,
  /// so plain CI runs pay nothing for it.
  Future<void> _capture(
    Shot? shot, {
    bool settled = true,
    int stray = 0,
  }) async {
    // Where this capture sits in the scenario's shape: the split choices
    // taken so far plus the count since the last one. Replays of a shared
    // prefix land on the same position — captured once, recognised after.
    var position = '${_state.plan.path}#${++_ordinal}';
    if (!_capturing) return;
    var parent = _lastPosition == null ? null : _state.emitted[_lastPosition!];
    if (_state.emitted.containsKey(position)) {
      // Already captured on an earlier replay — skip the rendering entirely,
      // but keep our place so the next new step's parent is right.
      _lastPosition = position;
      _pendingBranch = null;
      return;
    }
    var index = ++_state.stepCount;
    _state.emitted[position] = index;
    _lastPosition = position;
    var branch = _pendingBranch;
    _pendingBranch = null;
    await _emit(
      index: index,
      parent: parent,
      branch: branch,
      shot: shot,
      settled: settled,
      stray: stray,
    );
  }

  /// The frame the scenario broke on.
  ///
  /// Captured whatever the shot policy says — a failure is the one step nobody
  /// asked for and everybody wants — and deliberately given no position key:
  /// it belongs to this replay's dead end, never to a shared prefix a later
  /// replay would recognise.
  Future<void> _captureFailure(Object error) async {
    // Compared unwrapped: `split` re-throws the same failure wearing its
    // branch, and that is one failure, not two.
    var root = error is ScenarioFailure ? error.error : error;
    if (!_capturing || identical(_capturedFailure, root)) return;
    _capturedFailure = root;
    await _emit(
      index: ++_state.stepCount,
      parent: _lastPosition == null ? null : _state.emitted[_lastPosition!],
      branch: _pendingBranch,
      shot: null,
      settled: true,
      failure: '${_inContext(error)}',
    );
  }

  bool get _capturing =>
      scenarioRunListener != null || _screenshotsDestination != null;

  Future<void> _emit({
    required int index,
    required int? parent,
    required String? branch,
    required Shot? shot,
    required bool settled,
    int stray = 0,
    String? failure,
  }) async {
    var listener = scenarioRunListener;
    var destination = _screenshotsDestination;
    await tester.runAsync(() async {
      var view = tester.binding.renderViews.single;
      var layer = view.debugLayer! as OffsetLayer;
      // The root layer's coordinates are **physical** pixels — the
      // device-pixel-ratio transform sits inside it — so the capture rect
      // must be the physical frame or a 3× device saves its top-left ninth.
      //
      // The default *output* is logical (1×), measured, not guessed: on a
      // 50-screen scenario, physical 3× costs 22.4s and 56MB where 1× costs
      // 2.4s and 7MB — capture is the whole cost of a FakeAsync run, and 1×
      // is what keeps it feeling instantaneous. `captureScale` (up to the
      // device ratio for a true screenshot) is the host's knob when
      // fidelity is worth the wait.
      var dpr = view.flutterView.devicePixelRatio;
      var scale = (scenarioRunArgs?.captureNative ?? false)
          ? dpr
          : (scenarioRunArgs?.captureScale ?? 1.0);
      var image = await layer.toImage(
        Offset.zero & (view.size * dpr),
        pixelRatio: scale / dpr,
      );
      // Raw when the host asked for it: PNG *encoding* is ~80% of a 1×
      // capture's cost (56ms/step vs 11.5ms raw) and ~96% at 3× — the
      // rasterization itself is nearly free. Standalone runs always get PNG,
      // which everything can open.
      var raw = listener != null && (scenarioRunArgs?.captureRaw ?? false);
      var data = (await image.toByteData(
        format: raw ? ui.ImageByteFormat.rawRgba : ui.ImageByteFormat.png,
      ))!;
      var (width, height) = (image.width, image.height);
      image.dispose();
      var bytes = data.buffer.asUint8List();
      if (listener != null) {
        // The overlay style the app last declared — what the GUI's fake
        // status bar tints itself with. Visible-for-testing is exactly what
        // this is: scenario code only ever runs under the test binding.
        // ignore: invalid_use_of_visible_for_testing_member
        var style = SystemChrome.latestStyle;
        listener(
          ScenarioStepCapture(
            index: index,
            parent: parent,
            branch: branch,
            name: shot?.name,
            tags: shot?.tags ?? const [],
            bytes: bytes,
            format: raw ? 'raw' : 'png',
            width: width,
            height: height,
            texts: visibleTexts(),
            statusBrightness: style?.statusBarIconBrightness?.name,
            navBrightness: style?.systemNavigationBarIconBrightness?.name,
            settled: settled,
            strayFrames: stray,
            failure: failure,
          ),
        );
        return;
      }
      var label = failure != null ? 'failed' : shot?.name ?? 'step $index';
      // The axis above the scenario: a matrix writes every combination under
      // one destination, and without it the last language to run would be the
      // only one on disk.
      var slug = assignment?.slug ?? '';
      var directory = Directory(
        '$destination/'
        '${slug.isEmpty ? '' : '${_fileSafe(slug)}/'}'
        '${_fileSafe(_description)}',
      )..createSync(recursive: true);
      File(
        '${directory.path}/$index-${_fileSafe(label)}.png',
      ).writeAsBytesSync(bytes);
    });
  }

  /// The visible text, in tree order — the projection an agent reads next to
  /// the screenshot. `EditableText` too, or what the user just typed into a
  /// `TextField` would be pixels only.
  List<String> visibleTexts() => [
    for (var widget in tester.widgetList(
      find.byWidgetPredicate((w) => w is Text || w is EditableText),
    ))
      switch (widget) {
        Text(:var data, :var textSpan) => data ?? textSpan?.toPlainText() ?? '',
        EditableText(:var controller) => controller.text,
        _ => '',
      },
  ];

  static String _fileSafe(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  static String? get _screenshotsDestination {
    const define = String.fromEnvironment('screenshots-destination');
    if (define.isNotEmpty) return define;
    var env = Platform.environment['SCREENSHOTS_DESTINATION'];
    if (env != null && env.isNotEmpty) return env;
    return null;
  }
}
