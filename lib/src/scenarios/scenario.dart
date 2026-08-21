import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../drive/resolve.dart';
import '../translations/index.dart';
import 'aim.dart';
import 'asset_bundle.dart';
import 'async_watchdog.dart';
import '../app_events/events.dart';
import '../devices.dart';
import 'keyboard.dart';
import 'motion.dart';
import 'notification.dart';
import 'profile.dart';
import 'real_work.dart';
import 'run_args.dart';
import 'run_listener.dart';
import 'settle.dart';
import 'shots.dart';
import 'staging.dart';
import 'target.dart';
import 'harness.dart' show scenarioFileSafe, scenarioNameMax;

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

/// What a scenario that names no [Timeout] of its own gets.
///
/// Null here, so a bare `flutter test` keeps `flutter_test`'s answer. The
/// harness sets it at startup, because `testWidgets` stamps every test with the
/// binding's ten minutes and a runner that wants its own deadline has no other
/// way to say so — the metadata it reads back cannot tell a default apart from
/// an author who wrote ten minutes on purpose.
Timeout? scenarioDefaultTimeout;

@isTest
void scenario(
  String description,
  Future<void> Function(ScenarioTester s) body, {
  Shots? shots,
  Settle settle = Settle.standard,
  bool? skip,
  Timeout? timeout,
  Object? tags,
}) {
  // Captured as the scenario is *declared*, not read when it runs: a matrix
  // declares this same body once per assignment, and each declaration keeps
  // the one it was made under.
  var assignment = scenarioAmbientAssignment;
  // The folder's policy, where a `runScenarios(shots: ...)` set one — read
  // here for the same reason, and beaten by anything this scenario said for
  // itself. Nobody having spoken is `auto`, which is what it always was.
  var policy = shots ?? scenarioAmbientShots ?? Shots.auto;
  // The folder's keyboard policy, captured as this scenario is declared for
  // the reason the shots policy is: a matrix declares one body once per
  // assignment, and each declaration keeps what it was made under. On unless
  // the folder said otherwise — see [scenarioAmbientKeyboard] for what off
  // restores.
  var keyboard = scenarioAmbientKeyboard ?? true;
  var name =
      scenarioAmbientIsMatrix && assignment != null && !assignment.isEmpty
      ? '$description [${assignment.label}]'
      : description;

  scenarioDeclarationSink?.add(name);

  // Only the standalone lane needs it, and only it pays for it: under the
  // runner the harness knows the file it generated the group from, and a suite
  // that configures no destination captures nothing to file at all.
  var source = ScenarioTester._screenshotsDestination == null
      ? null
      : scenarioDeclaringFile(StackTrace.current);

  testWidgets(
    name,
    skip: skip,
    timeout: timeout ?? scenarioDefaultTimeout,
    tags: tags,
    (tester) async {
      var origin = scenarioRunArgs?.clockOrigin ?? _scenarioClockOrigin;
      if (origin == null) {
        return _runScenario(
          tester,
          description,
          body,
          policy,
          settle,
          assignment,
          source,
          keyboard,
        );
      }
      // Pinned, but still ticking with FakeAsync: the offset from where this
      // scenario's fake clock started is what `s.wait` moves, so a flow that
      // waits a day still reads a day later — from a date that is the same on
      // every run.
      var started = tester.binding.clock.now();
      return withClock(
        Clock(() => origin.add(tester.binding.clock.now().difference(started))),
        () => _runScenario(
          tester,
          description,
          body,
          policy,
          settle,
          assignment,
          source,
          keyboard,
        ),
      );
    },
  );
}

/// The test file a `scenario()` call was made from, `/`-separated and relative
/// to the package when it sits under it, or null when the frame says nothing.
///
/// Read off the declaring stack because nothing else can say it: a bare
/// `flutter test` tells a test nothing about which file it is, and a scenario
/// must not have to repeat its own path to get its screenshots filed under it.
/// The runner's lane never asks — the harness generated the group and knows.
@visibleForTesting
String? scenarioDeclaringFile(StackTrace stack) {
  for (var line in stack.toString().split('\n')) {
    var location = _frameLocation.firstMatch(line)?.group(1);
    if (location == null) continue;
    // This library's own frames sit above the caller — `scenario()` itself,
    // and anything it is reached through — whether the runtime spells them as
    // a package uri or as a path into a checkout.
    if (location.endsWith('flutterware/src/scenarios/scenario.dart') ||
        location.endsWith('flutterware/lib/src/scenarios/scenario.dart')) {
      continue;
    }
    var uri = Uri.tryParse(location);
    if (uri == null || uri.scheme != 'file') return null;
    var path = uri.toFilePath();
    var root = Directory.current.path;
    return p.url.joinAll(
      p.split(p.isWithin(root, path) ? p.relative(path, from: root) : path),
    );
  }
  return null;
}

/// The `(uri:line:column)` a stack frame ends with, in either of the two
/// spellings a Dart trace uses.
final _frameLocation = RegExp(r'\((.+?\.dart):\d+(?::\d+)?\)\s*$');

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
  String? source,
  bool wantsKeyboard,
) async {
  // The runner's assignment wins, like its args do below: the declaration
  // captured the ambient one, which under the runner is null — and a body
  // reading `s.assignment?.language` has to see the language the request
  // named, the same as it would under `flutter test` with `FW_LANGUAGES`.
  assignment = scenarioRunArgs?.assignment ?? assignment;
  var restore = _applyRunArgs(tester, assignment);
  var restoreErrors = _installExpansionOverflowFilter();
  // **The measurement, read off the device the run is staged as.** Zero when
  // the folder turned the keyboard off, when the run is staged on nothing, and
  // on every desktop size — and zero is the whole of "off": no insets, no
  // slab, and no refusal for a target under a band that is not there.
  //
  // One driver for the scenario, not one per replay: a split's branches share
  // a tester and a view, so a keyboard raised on the first path has to be put
  // back before the second one starts.
  var keyboard = ScenarioKeyboard(
    tester,
    deviceHeight: wantsKeyboard
        ? (assignment?.orientedDevice?.keyboard ?? 0)
        : 0,
  );
  // Whatever the scenario before this one left memoized on `rootBundle`
  // belongs to *its* FakeAsync zone. A read still in flight when that scenario
  // ended can never complete again — nothing will ever flush that zone — and
  // this scenario awaiting it waits forever. Cleared at the top rather than at
  // the bottom, so a run also survives whatever ran before the first scenario:
  // the harness loads the app's fonts through `rootBundle` at startup.
  rootBundle.clear();
  // The same shape one counter further out: the image cache is process-wide
  // and `testWidgets` never empties it, so a scenario that ended with a decode
  // still in flight would have this one waiting out its whole allowance on
  // work that is not its own.
  resetAnnouncedWork();
  var assets = ScenarioAssetBundle();
  _countFrames(tester);
  var state = _ReplayState();
  // Under the runner only: every exception the binding sees goes into the
  // harness's buffer *before* the binding aggregates. Two exceptions in one
  // test otherwise reach the report as the sentence "Multiple exceptions (2)
  // were detected…" with no stack — the real ones exist only as console
  // dumps. Chained, not replaced: the binding's handler is what fails the
  // test, and it asserts at the end that it got its handler back.
  var caught = scenarioCaughtErrors;
  var priorOnError = FlutterError.onError;
  if (caught != null) {
    FlutterError.onError = (details) {
      caught.add(
        ScenarioCaughtError(
          details.exception,
          details.exceptionAsString(),
          details.stack,
        ),
      );
      priorOnError?.call(details);
    };
  }
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
        // With the tree goes the keyboard: the next branch starts from a fresh
        // app, and one left up would be over a form nobody has touched yet.
        keyboard.reset();
      }
      first = false;
      var s = ScenarioTester._(
        tester,
        description,
        shots,
        settle,
        state,
        assignment,
        source,
        assets,
        keyboard,
      );
      try {
        await body(s);
        s._flushPending();
      } catch (error, stack) {
        var inContext = s._inContext(error);
        // The binding reports this rethrow only after the body — after the
        // `finally` below has unchained the handler — so it has to be
        // buffered here, with the stack it actually broke on. Skipped when
        // the chain already saw this same object reported mid-body.
        if (caught != null &&
            !caught.any((c) => identical(c.exception, error))) {
          caught.add(ScenarioCaughtError(inContext, '$inContext', stack));
        }
        // One catch for the whole body, so every failure has a picture of
        // the frame it broke on — whatever raised it: a verb, a bare
        // `expect`, the app's own build. A capture that fails in turn is
        // swallowed: it may never mask what it was called about.
        try {
          await s._captureFailure(error);
        } catch (_) {}
        // Rethrown with the original stack, so the report still points at
        // the user's line; only the message gains its split branch.
        Error.throwWithStackTrace(inContext, stack);
      }
    } while (state.plan.advance());
  } finally {
    if (caught != null) FlutterError.onError = priorOnError;
    // Both before the body ends, not in a tearDown: the binding checks its
    // debug variables — and complains about a live semantics handle — at
    // the end of the body, before tearDowns run.
    state.disposeSemantics();
    restore?.call();
    restoreErrors?.call();
  }
}

/// Layout overflow errors swallowed since the last capture, drained per step
/// into [ScenarioStepCapture.overflowErrors]. Only ever counts under the
/// expansion filter below, so it stays zero on every ordinary run.
int _overflowsSinceLastCapture = 0;

/// Under a budget probe, an overflow is the *measurement*, not a failure.
///
/// Every value on screen was just deliberately expanded, so a `RenderFlex`
/// running out of room is data the pass exists to collect — and left to the
/// binding it fails the scenario, which would make every fragile screen
/// unmeasurable past its first break. Installed inside the test body, over the
/// binding's own handler, and restored before the body ends; anything that is
/// not an overflow report still goes where it always went.
///
/// Design: `2026-08-19-translation-max-lengths-design.md`.
VoidCallback? _installExpansionOverflowFilter() {
  if (TranslationIndex.expandPercent == null) return null;
  var prior = FlutterError.onError;
  FlutterError.onError = (details) {
    // The one stable word in every "RenderFlex overflowed by … pixels"
    // report, and in its cousins (constrained boxes overflow the same way).
    if (details.exception.toString().contains('overflowed')) {
      _overflowsSinceLastCapture++;
      return;
    }
    prior?.call(details);
  };
  return () => FlutterError.onError = prior;
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
/// through one binding, so one is all there may ever be. It lets a step tell
/// how many frames happened outside the scenario's verbs, which is how a flow
/// reports a gap in itself.
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

/// Applies the harness's axis assignment, when there is one to apply.
///
/// The application itself is [applyScenarioRunArgs], which is also what
/// `tester.applyDevice` calls — one implementation, so a scenario on an axis
/// and a plain widget test staged by hand cannot end up on subtly different
/// surfaces. Only the *resolution* is here, because only a scenario has two
/// places an assignment can come from.
///
/// Null args are a bare `flutter test` with no profile, which pays nothing.
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
  return applyScenarioRunArgs(tester, args);
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
    this._settle,
    this._state,
    this.assignment,
    this._source,
    this.assets,
    this._keyboard,
  );

  /// The real tester — the escape hatch to the full `flutter_test` surface.
  final WidgetTester tester;

  /// The bundle this scenario reads assets through, installed over whatever
  /// [pumpWidget] pumps — so `DefaultAssetBundle.of(context)`, and everything
  /// built on it, is already this one.
  ///
  /// It caches values where `rootBundle` caches futures, which is what makes an
  /// asset the app has already read safe to read again from inside
  /// [runAsync]. Pass it wherever a widget takes a bundle explicitly:
  ///
  /// ```dart
  /// SvgPicture.asset('assets/logo.svg', bundle: s.assets);
  /// ```
  ///
  /// One per scenario, shared by every replay of its splits.
  final ScenarioAssetBundle assets;

  /// What raises and lowers the software keyboard — shared across replays for
  /// the same reason [assets] is.
  final ScenarioKeyboard _keyboard;

  /// The software keyboard, for a scenario that wants to say it explicitly.
  ///
  /// Nothing here is needed to get one. A scenario that taps a text field
  /// already renders with a keyboard over the bottom of the screen, because
  /// that is what a phone does and the framework says when. This is for the
  /// other cases: a layout you want to see under one with nothing focused, a
  /// user who swipes it away, a screen you want photographed without it.
  ///
  /// Every one of them is a **no-op on a stage with no keyboard** — a run on
  /// a desktop size or on nothing, and a folder that turned the feature off.
  /// Raising one there would mean inventing a height, which is the one thing
  /// the measured table exists not to do, and a matrix crossing a phone with a
  /// window must not fail on the window.
  late final keyboard = ScenarioKeyboardVerbs._(this);

  final Shots shots;

  /// How every verb waits before it captures — overridable per call.
  final Settle _settle;

  final String _description;

  /// The test file this scenario was declared in, when the standalone lane
  /// looked it up — the directory above [_description] in a destination, so
  /// that two files naming the same screen do not write into each other.
  final String? _source;

  /// The axes this scenario is running under, when anything assigned any —
  /// what keeps a matrix's captures out of each other's directories, and what
  /// a body reads to adapt an expectation to the screen it is on.
  ///
  /// Both lanes answer here: a folder profile or a CI list (`FW_LANGUAGES`)
  /// under `flutter test`, and the request's own axes (`--language`,
  /// `--device`) under the flutterware runner. That agreement is the point —
  /// a base class keying its locale off `assignment.language` was silently
  /// running every `scenarios run --language=nl` in English, because the
  /// runner used to leave this null.
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
  /// teardown pump, so tearing the tree down never counts as a stray frame.
  var _framesAtLastStep = _frames;

  /// Collects the frames of the transition being walked, when the run asked
  /// for motion and there is a listener to hand them to.
  ///
  /// Not created for a standalone `flutter test` writing PNGs to a
  /// destination: a folder of screenshots has nowhere to put a movie, and
  /// nobody asked that lane to slow down.
  late final ScenarioMotionRecorder? _recorder =
      scenarioRunListener != null && scenarioRunArgs?.record != null
      ? ScenarioMotionRecorder(scenarioRunArgs!.record!)
      : null;

  Future<void> pumpWidget(Widget widget, {Shot? shot, Settle? settle}) => _step(
    shot,
    settle,
    () async {
      // Wrapped in the scenario's own bundle, so every `Image.asset`,
      // `AssetImage` and `SvgPicture.asset` under the app reads through
      // something that caches values rather than futures — see [assets]. An
      // app that installs a `DefaultAssetBundle` of its own still wins, since
      // its is the nearer ancestor.
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: assets,
          // The slab, above the app and inside the pumped tree, so every
          // capture that exists already contains it — step shots, motion
          // frames, the web export — with no compositing step anywhere. The
          // *insets* are on the view rather than here; see [ScenarioKeyboard].
          child: _keyboard.deviceHeight > 0
              ? ScenarioKeyboardSlab(driver: _keyboard, child: widget)
              : widget,
        ),
      );
      await _realAsyncTurn();
      await tester.pump();
    },
    verb: 'pumpWidget',
    target: '${widget.runtimeType}',
  );

  /// `tester.runAsync` with a watchdog on it: real async work, and a sentence
  /// rather than a hang when it turns out not to be work at all.
  ///
  /// Everything a scenario waits on for real — a database, a socket, an http
  /// call, an asset the app has not read yet — needs a turn of the real event
  /// loop, and this is the turn. The catch is that no pump can run while it is
  /// open, so awaiting a future that was made *outside* it, and that only a
  /// pump could complete, deadlocks the whole run silently. The watchdog
  /// reports that within seconds, and names the cache usually behind it.
  ///
  /// ```dart
  /// var bytes = await s.runAsync(() => report.generatePdf());
  /// ```
  Future<T?> runAsync<T>(Future<T> Function() callback) =>
      watchRunAsync(() => tester.runAsync(callback));

  /// Lets whatever the app started on its first frame actually happen.
  ///
  /// A scenario runs under fake time, where a real asset read — the shape
  /// every app that loads translations or a font manifest at boot has —
  /// completes on an event loop no pump reaches. So the tree builds with
  /// nothing in it and every screen after this captures blank.
  ///
  /// The alternative was answering `flutter/assets` from Dart, which is what
  /// `flutter test` does with `UNIT_TEST_ASSETS`. Measured against a real
  /// suite, that deadlocks a `tester.runAsync` that loads an asset itself —
  /// `flutter test` hangs where this does not. A turn of the real event loop
  /// costs a few milliseconds once per pumped app and has no such edge.
  ///
  /// Deliberately not on every verb: this is about *boot*, and a scenario
  /// that needs real async mid-flow says so with its own [runAsync].
  Future<void> _realAsyncTurn() => tester.runAsync(() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  });

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
    () async {
      var finder = await _resolve(target, 'tap');
      _aimAt(finder);
      await tester.tap(finder, warnIfMissed: false);
    },
    verb: 'tap',
    target: describeTarget(target),
  );

  Future<void> longPress(dynamic target, {Shot? shot, Settle? settle}) => _step(
    shot,
    settle,
    () async {
      var finder = await _resolve(target, 'longPress');
      _aimAt(finder);
      await tester.longPress(finder, warnIfMissed: false);
    },
    verb: 'longPress',
    target: describeTarget(target),
  );

  Future<void> enterText(
    dynamic target,
    String text, {
    Shot? shot,
    Settle? settle,
  }) => _step(
    shot,
    settle,
    // `editableWithin` rather than the finder itself: `tester.enterText`
    // searches down for the editable, and a point target — `Target.at`, and
    // the `item:` an agent spells it with — resolves to a render object below
    // it, where down finds nothing.
    () async => tester.enterText(
      editableWithin(await _resolve(target, 'enterText')),
      text,
    ),
    verb: 'enterText',
    target: describeTarget(target),
  );

  /// Drags [target] by [by] — a swipe, a dismiss, a slider, a sheet pulled
  /// down. Negative `dy` moves the finger up the screen, the touch convention
  /// `flutter_test` itself uses.
  Future<void> drag(dynamic target, Offset by, {Shot? shot, Settle? settle}) =>
      _step(
        shot,
        settle,
        () async {
          var finder = await _resolve(target, 'drag');
          _aimAt(finder, by: by);
          await tester.drag(finder, by, warnIfMissed: false);
        },
        verb: 'drag',
        target: describeTarget(target),
      );

  /// Scrolls until [target] is on screen, then captures it there.
  ///
  /// The scrollable is the first one on screen unless [within] names one — a
  /// widget that *is* a `Scrollable` or contains one. A target that is built
  /// but behind the viewport is jumped to directly, whichever direction and
  /// axis that is. [step] is how far each drag travels toward the end of the
  /// list when the target is not built yet; make it negative to walk back
  /// toward the start.
  ///
  /// A target already on screen is a no-op, whether or not anything scrolls
  /// — so the verb is safe inside a loop over pages of varying length, where
  /// which pages scroll depends on the device. Unlike the other verbs this
  /// one may start with a target that matches nothing — being off screen is
  /// the reason to call it — so it reports the miss itself when the scrolling
  /// never finds it, and when nothing scrolls and the target is absent or off
  /// screen.
  Future<void> scrollTo(
    dynamic target, {
    dynamic within,
    double step = 200,
    int maxScrolls = 50,
    Shot? shot,
    Settle? settle,
  }) => _step(
    shot,
    settle,
    () async {
      var scrollable = within == null
          ? find.byType(Scrollable)
          : find.descendant(
              of: finderForTarget(within),
              matching: find.byType(Scrollable),
              matchRoot: true,
            );
      if (scrollable.evaluate().isEmpty) {
        var refusal = refusalWhenNothingScrolls(
          finderForTarget(target),
          describeTarget(target),
          within,
          _messages,
        );
        // A target already on screen is the step's whole point achieved:
        // capture it there, scroll nothing. Which pages scroll varies with
        // the device, so a walking scenario cannot know statically.
        if (refusal == null) return;
        throw ScenarioTargetError(refusal.message);
      }
      var finder = finderForTarget(target);
      // Built but behind the viewport: the walk only drags one way, so a
      // target the list has already scrolled past is unreachable however
      // long it walks. `Scrollable.ensureVisible` reads the target's own
      // position and jumps — both directions, both axes. The walk stays for
      // what it was built for: a lazy list whose target is not built yet.
      if (finder.evaluate().isEmpty) {
        if (scrolledPastTarget(finder, scrollable) case var behind?) {
          await Scrollable.ensureVisible(behind);
          await tester.pump();
          // Not revealed means it was never in this viewport's reach — an
          // `Offstage` under the list, say. The walk's own exhaustion
          // message below is the one that says what to try.
          if (finder.evaluate().isNotEmpty) return;
        }
      }
      try {
        await tester.scrollUntilVisible(
          finder,
          step,
          // The first, as `flutter_test` itself defaults to: nested scrollables
          // are ordinary, and `within` is how a scenario says which one.
          scrollable: scrollable.first,
          maxScrolls: maxScrolls,
        );
      } on StateError {
        throw ScenarioTargetError(
          _messages.scrollExhausted(maxScrolls, step, describeTarget(target)),
        );
      }
    },
    verb: 'scrollTo',
    target: describeTarget(target),
  );

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
    verb: 'back',
  );

  /// Advances the clock by [duration].
  ///
  /// The verbs settle, which waits out *animations*; a pending timer schedules
  /// no frames, so a splash screen that navigates after three seconds needs
  /// the clock moved rather than settled. Instant either way — the clock is
  /// fake.
  Future<void> wait(Duration duration, {Shot? shot, Settle? settle}) => _step(
    shot,
    settle,
    () => tester.pump(duration),
    verb: 'wait',
    target: '$duration',
  );

  /// Waits per the scenario's [Settle] policy — or [policy] — and captures
  /// nothing.
  ///
  /// The wait without the step: what a bridge maps a legacy `pumpAndSettle()`
  /// onto, and what a scenario wants after work it pumped itself through
  /// [tester]. Same budget, same "give up quietly on a screen that never
  /// stops animating" as every verb — where a raw `tester.pumpAndSettle`
  /// throws on the first spinner and leaves the budget to be re-derived by
  /// hand.
  Future<void> settle([Settle? policy]) =>
      _step(Shot.skip, policy, () async {}, verb: 'settle');

  /// Names the screen as it stands, without performing an action.
  ///
  /// Where nothing has moved since the last verb captured — the ordinary
  /// `tap` then `screen` pair — this **names that capture** rather than
  /// photographing the same frame a second time:
  ///
  /// ```dart
  /// await s.tap(Keys.search);
  /// await s.screen('Cases');   // one step, named 'Cases', verb `tap`
  /// ```
  ///
  /// So a name costs nothing, and an author never has to weigh writing one
  /// against the picture it would duplicate. Where something *has* moved —
  /// a `pump`, a completer, a rebuild from outside the tree — there is a new
  /// frame to photograph and this captures it, which is the whole reason the
  /// verb exists:
  ///
  /// ```dart
  /// await s.tap(Keys.takePicture, pumpFrames: false);
  /// await s.screen('Capturing');        // names the tap's frame
  /// await s.wait(const Duration(seconds: 5));
  /// await s.screen('Captured');         // a new frame: its own step
  /// ```
  ///
  /// A name never overwrites a name: two `screen` calls on one frame stay two
  /// steps. [force] declines the adoption outright, for a deliberate second
  /// picture of a frame that already has a name on it.
  Future<void> screen(
    String name, {
    List<String> tags = const [],
    Settle? settle,
    bool force = false,
  }) => _step(
    Shot(name, tags: tags),
    settle,
    () async {},
    verb: 'screen',
    adopt: !force,
  );

  /// A beat of the flow that is not a screen: the PDF it just generated, the
  /// email body it queued, the payload it posted.
  ///
  /// A step like any other — named, positioned, carrying the events that led
  /// to it — whose picture is the document rather than the app:
  ///
  /// ```dart
  /// await s.tap('Export');
  /// var bytes = await s.runAsync(() => report.generatePdf());
  /// await s.document('receipt', bytes!, fileName: 'receipt.pdf',
  ///     mimeType: 'application/pdf');
  /// ```
  ///
  /// A flow that exists to produce a document was otherwise a scenario that
  /// stopped one step short: you could screenshot the button and
  /// prove nothing about what it made. Deliberately one verb rather than one
  /// per format — the format is [mimeType]'s job, and a viewer shows what it
  /// can and offers the rest as a download.
  ///
  /// It renders nothing, so it costs no capture: there is no screen here to
  /// photograph, which is why it is its own kind of step rather than a file
  /// attached to another one.
  Future<void> document(
    String name,
    List<int> bytes, {
    String? fileName,
    String? mimeType,
    List<String> tags = const [],
  }) => _beat(
    kind: ScenarioCaptureKind.document,
    verb: 'document',
    name: name,
    tags: tags,
    payload: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    fileName: fileName,
    mimeType: mimeType,
  );

  /// A push the flow's backend would have sent — a beat the recipient sees,
  /// drawn the way their phone would draw it.
  ///
  /// ```dart
  /// await s.tap('Pay');
  /// await s.notification("Your cappuccino is ready — counter 3",
  ///     title: "Barista's");
  /// ```
  ///
  /// Like [document] it has no frame of its own. A viewer draws it over the
  /// nearest screen before it — which is what a real banner does — and
  /// supplies everything the payload leaves out: the project's own launcher
  /// icon, the banner's "now", the brightness the scenario ran under.
  ///
  /// Deliberately unnamed as a step. A notification's words are the app's
  /// user-facing text, so they are translated and reworded; keying a
  /// comparison on them would read one flow under two languages as two
  /// different flows. The same reasoning the aligner already applies to a
  /// verb's visible-text target.
  Future<void> notification(
    String body, {
    String? title,
    String? appName,
    List<String> tags = const [],
  }) => _beat(
    kind: ScenarioCaptureKind.notification,
    verb: 'notification',
    tags: tags,
    notification: ScenarioNotification(
      title: title,
      body: body,
      appName: appName,
    ),
  );

  /// Emits a step that has no frame — see [document] and [notification].
  ///
  /// Everything a captured step does about position, parent, branch and
  /// replay, and none of what it does about pixels. It deliberately does
  /// **not** hand over the capture being held: nothing was drawn here, so a
  /// `screen` after this beat may still name the frame before it, and the
  /// chain stays linear because the position map records the chain's head
  /// rather than the step a name landed on.
  Future<void> _beat({
    required ScenarioCaptureKind kind,
    required String verb,
    String? name,
    List<String> tags = const [],
    Uint8List? payload,
    String? fileName,
    String? mimeType,
    ScenarioNotification? notification,
  }) async {
    var position = '${_state.plan.path}#${++_ordinal}';
    if (!_capturing) return;
    var parent = _lastPosition == null ? null : _state.emitted[_lastPosition!];
    if (_state.emitted.containsKey(position)) {
      // Recognised from an earlier replay of a shared prefix, exactly as a
      // captured step is: the beat was emitted on the first pass with that
      // pass's events, and appending these would multiply the prefix.
      appEventBuffer?.discard();
      _lastCaptureFresh = false;
      _lastPosition = position;
      _pendingBranch = null;
      return;
    }
    var index = ++_state.stepCount;
    _state.emitted[position] = index;
    _lastPosition = position;
    var branch = _pendingBranch;
    _pendingBranch = null;
    var (events, dropped) = appEventBuffer?.drain() ?? (const <AppEvent>[], 0);
    _pendingBeats.add(
      _PendingEmit(
        index: index,
        parent: parent,
        branch: branch,
        kind: kind,
        name: name,
        tags: tags,
        payload: payload,
        fileName: fileName,
        mimeType: mimeType,
        notification: notification,
        verb: verb,
        target: null,
        position: position,
        events: List.of(events),
        eventsDropped: dropped,
        settled: true,
        landed: true,
        strayFrames: 0,
        failure: null,
        frames: _frames,
      ),
    );
    _lastCaptureFresh = true;
  }

  /// Whether the last capture this replay saw was emitted by this replay —
  /// false when it was recognised from an earlier pass over a shared `split`
  /// prefix, which leaves something older held.
  var _lastCaptureFresh = false;

  /// What the verb now running aimed at, measured by [_aimAt] the moment
  /// after its target resolved and before it acted. Cleared per step, so a
  /// verb that aims at nothing never inherits the last one's box.
  ScenarioAim? _aim;

  /// Records the box [finder] resolved to, in the same space every other rect
  /// in a report is in.
  ///
  /// Measured before the verb acts, because after it the widget may be gone —
  /// and read off the render object the actionability ladder just proved is
  /// there, so it costs a transform and no searching.
  ///
  /// Never throws. A picture of where the finger went is a nicety; a scenario
  /// that failed because it could not measure the thing it just tapped would
  /// be a bad trade.
  void _aimAt(Finder finder, {Offset? by}) {
    var render = finder.evaluate().firstOrNull?.renderObject;
    if (render is! RenderBox || !render.hasSize || !render.attached) return;
    // The whole rect through the transform, for the reason `_layoutOf` gives
    // at length: an origin from `localToGlobal` beside a raw `render.size` are
    // in different spaces the moment any ancestor scales, and a box drawn from
    // the two of them disagrees with the picture it is drawn on.
    var bounds = MatrixUtils.transformRect(
      render.getTransformTo(null),
      Offset.zero & render.size,
    );
    _aim = ScenarioAim(
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
      dx: by?.dx,
      dy: by?.dy,
    );
  }

  /// One verb: act, wait per the policy, capture. The settle result rides the
  /// step, so a screen that never stopped animating is reported instead of
  /// throwing.
  Future<void> _step(
    Shot? shot,
    Settle? settle,
    Future<void> Function() action, {
    String? verb,
    String? target,
    bool adopt = false,
  }) async {
    // Frames since the previous verb finished: nothing this scenario's verbs
    // drew, so they came from `s.tester` — and whatever they showed is not in
    // the flow. Read before the action, reported on the step it precedes.
    var stray = _frames - _framesAtLastStep;
    _aim = null;
    bool settled;
    bool landed;
    try {
      // The frame the transition starts from, banked before the verb acts —
      // otherwise a movie of a tap opens on the frame after the tap and the
      // "before" is nowhere in it.
      _recorder?.capture(tester);
      await action();
      var policy = settle ?? _settle;
      // One purse for the whole step: the policy's frames draw whatever has
      // announced itself as they go — otherwise fake time runs the transition
      // out in a few real milliseconds and every frame of the movie behind the
      // step is a hole — and the landing below spends what is left.
      var budget = RealWorkBudget();
      settled = await policy.apply(
        tester,
        record: _recorder,
        // The keyboard rides the same between-frames hook the real work does,
        // and for a related reason: it has to move *between* the policy's
        // frames or the slide is not in them. Writing the view schedules a
        // forced frame, so a bounded policy keeps pumping until it lands
        // rather than stopping halfway down.
        land: () async {
          _keyboard.step();
          await budget.land(tester, assets);
        },
      );
      // Frames are all a policy follows; work on the real event loop
      // schedules none while it is in flight. See [landRealWork].
      (settled: settled, landed: landed) = await landRealWork(
        tester,
        policy,
        settled: settled,
        budget: budget,
        assets: assets,
        record: _recorder,
        beforePump: _keyboard.step,
      );
    } catch (error) {
      // The verb that broke captures its own frame; `scenario`'s catch is the
      // backstop for everything else. Both go through the same once-per-error
      // guard, so an error travelling up the stack yields one failed step.
      await _captureFailure(error, verb: verb, target: target);
      rethrow;
    }
    _framesAtLastStep = _frames;
    await _afterStep(
      shot,
      settled: settled,
      landed: landed,
      stray: stray,
      verb: verb,
      target: target,
      aim: _aim,
      adopt: adopt,
    );
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
  /// What a replay does and does not reset. The widget tree is torn down
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
    required bool landed,
    required int stray,
    String? verb,
    String? target,
    ScenarioAim? aim,
    bool adopt = false,
  }) async {
    // Nothing captures, so nothing drains: what the app did during this verb
    // belongs to whichever step captures next, which is the transition a
    // reader of that step will be looking at.
    if (identical(shot, Shot.skip)) return;
    if (shot == null && shots == Shots.manual) return;
    await _capture(
      shot,
      settled: settled,
      landed: landed,
      stray: stray,
      verb: verb,
      target: target,
      aim: aim,
      adopt: adopt,
    );
  }

  /// [error] with the split branch that reached it, when there was one.
  Object _inContext(Object error) =>
      _branchTrail.isEmpty || error is ScenarioFailure
      ? error
      : ScenarioFailure(List.of(_branchTrail), error);

  /// The scenario flavor of the shared refusal wording: verbs read as `s.tap`,
  /// and `s.tester` is offered as the covered escape hatch.
  static const _messages = TargetMessages(
    prefix: 's.',
    coveredEscapeHatch:
        ' Use `s.tester` if you meant to hit whatever is on top.',
    blankScreenHint:
        'Nothing has rendered — there is no text on screen at all, so this '
        'is not something `s.scrollTo` can reach. A scenario runs under fake '
        'time: anything the app waits on for real — a database, a socket, an '
        'http call — never completes between pumps. Give it a turn with '
        '`await s.runAsync(() async { … })`.',
  );

  /// The actionability ladder every pointer verb climbs — shared with the
  /// live drive engine (`lib/src/drive/resolve.dart`), which runs the same
  /// checks with the same wording against a running app.
  late final TargetResolver _targetResolver = TargetResolver(
    tester,
    messages: _messages,
    pump: () => tester.pump(),
    ensureSemantics: () => _state.ensureSemantics(tester),
    describeScreen: _describeVisibleTexts,
    namedCovering: _keyboardOver,
  );

  /// The refusal for a target under the keyboard, or null when the keyboard is
  /// not what is over it.
  ///
  /// The refusal is deliberate. Without it the tap lands on the slab,
  /// which absorbs it, and the flow sails on: the verb reported success, the
  /// button was never pressed, and the failure surfaces three steps later as a
  /// screen that did not change. The generic covered sentence would be true —
  /// something absorbs the pointer — and would send the reader looking for an
  /// overlay that is not in their code.
  ///
  /// It does not offer `scrollTo`, and that was measured rather than
  /// assumed. `Scrollable.ensureVisible` stops the moment the target is
  /// inside the *viewport*, and in the app this refusal actually fires on —
  /// one that does not resize — the viewport runs under the keyboard. So the
  /// scroll succeeds, the target is still covered, and the very next verb is
  /// refused again. That is faithful: a row parked at the bottom of a list
  /// under a real keyboard is not reachable on a real phone either. The way
  /// past is to dismiss the keyboard.
  String? _keyboardOver(Offset center, String verb, String described) {
    if (!_keyboard.up || center.dy < _keyboardTop) return null;
    return '$described is behind the software keyboard, which covers the '
        'bottom ${_keyboard.height.round()} points of the screen, so '
        '`s.$verb` at its centre lands on the keyboard instead. If the app is '
        'meant to reach this while the keyboard is up, that is a layout '
        'problem: a `Scaffold` that resizes moves it out of the way. To carry '
        'the flow on: `await s.keyboard.dismiss()`.';
  }

  /// Where the keyboard's top edge is, in the logical pixels every box in a
  /// scenario is measured in.
  double get _keyboardTop {
    var view = tester.binding.renderViews.firstOrNull;
    var height = view?.size.height ?? 0;
    return height - _keyboard.height;
  }

  /// Resolves a verb's target and checks it names exactly one widget the
  /// pointer can actually reach.
  ///
  /// The same checks the underlying `tap` fails on anyway — made legible, and
  /// made *before* the action, so the message can say what to do rather than
  /// dump the matching render objects.
  Future<Finder> _resolve(dynamic target, String verb) async {
    try {
      return await _targetResolver.resolve(target, verb);
    } on TargetError catch (error) {
      throw ScenarioTargetError(error.message);
    }
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

  /// The capture that has been rendered but not yet handed over.
  ///
  /// Held for exactly one step, because a [screen] that follows without
  /// moving the screen adopts its name — and adoption has to land before
  /// anything is written, every artifact's file name being built from the
  /// step's label. Handing over one step late is what allows it, and that is
  /// the only cost: a host drawing the flow live sees each step as the next
  /// one is taken, and the last is flushed when the body ends.
  _PendingEmit? _pending;

  /// Frameless beats — [document]s and [notification]s — emitted since
  /// [_pending] was rendered, still waiting behind it.
  ///
  /// They cannot go out first: their indices are higher than the held frame's,
  /// and a host drawing the flow live reads the order it is given. And they
  /// must not force the frame out, because nothing they do draws — so a
  /// `screen` after them still names the frame before them.
  final _pendingBeats = <_PendingEmit>[];

  /// Whether the capture being taken is the frame [_pending] already took.
  ///
  /// The frame counter carries it, and exactly rather than approximately: the
  /// binding draws no frame at all for a pump with nothing scheduled, so an
  /// untouched settled screen does not move it. Counted from the
  /// pending *capture* rather than from the last step, because the two are not
  /// the same line — a `Shot.skip` verb between them draws its frames like any
  /// other, and they are frames this screen would otherwise adopt away.
  ///
  /// Read here rather than at the top of the verb, so it spans the verb's own
  /// settle too: a `screen` acts on nothing, but its settle still lands work
  /// the verb before it left in flight, and an image arriving there is a
  /// different picture.
  ///
  /// The rest is bookkeeping that keeps a real second picture, or an unrelated
  /// step, from being swallowed by a name.
  bool _canAdopt({required bool settled}) {
    var pending = _pending;
    return pending != null &&
        // Nothing has been drawn since that capture, so the frame still
        // stands as it photographed it.
        _frames == pending.frames &&
        // Neither that capture nor this one is parked mid-flight: a settle
        // that gave up leaves an animation running, and *that* is one pump
        // away from different pixels.
        pending.settled &&
        settled &&
        // A name never overwrites a name.
        pending.name == null &&
        // A failure's own picture is nobody's to rename.
        pending.failure == null &&
        // The pending capture is this replay's immediately preceding step —
        // false where that step was recognised from an earlier pass over a
        // shared `split` prefix, which leaves something older pending.
        _lastCaptureFresh &&
        // And this is not a branch's first capture, whose parent is the
        // shared step before the fork: a branch-local name has no business on
        // a step every other branch shows too.
        _pendingBranch == null;
  }

  /// Puts [shot]'s name on the capture waiting to be handed over, with
  /// everything the flow produced on the way to it.
  void _adoptOntoPending(Shot shot) {
    var pending = _pending!;
    pending.name = shot.name;
    pending.tags = shot.tags;
    // The events belong to the step wearing the name rather than to whichever
    // step captures next: they happened on the way to *this* frame, and this
    // frame is the pending capture. Rolling them forward — what a
    // non-capturing verb does with them — would file the request the flow
    // made here under a screen two taps later.
    var (events, dropped) = appEventBuffer?.drain() ?? (const <AppEvent>[], 0);
    // One step keeps one step's worth. The buffer caps each drain, and this
    // step is now the far side of two of them — so the overflow is counted
    // here the way the buffer counts its own, rather than quietly making one
    // step's `events.json` twice the size every other step's may be.
    var room = (maxAppEventsPerStep - pending.events.length).clamp(
      0,
      maxAppEventsPerStep,
    );
    if (events.length > room) {
      dropped += events.length - room;
      events = events.take(room).toList();
    }
    pending.events.addAll(events);
    pending.eventsDropped += dropped;
    // Frames of a transition that did not happen. The movie behind the merged
    // step is the one its own verb recorded.
    _recorder?.discard();
  }

  /// Hands the held capture over, to the listener or to disk.
  ///
  /// Nothing can adopt it afterwards: the name it has here is the name its
  /// files are called after.
  void _flushPending() {
    var frame = _pending;
    _pending = null;
    var beats = List.of(_pendingBeats);
    _pendingBeats.clear();
    for (var pending in [?frame, ...beats]) {
      _hand(pending);
    }
  }

  /// One held step, out.
  void _hand(_PendingEmit pending) {
    if (scenarioRunListener case var listener?) {
      listener(pending.toCapture());
      return;
    }
    var destination = _screenshotsDestination;
    if (destination == null) return;
    var label = pending.failure != null
        ? 'failed'
        : pending.name ?? pending.verb ?? 'step ${pending.index}';
    // The axis above the scenario: a matrix writes every combination under
    // one destination, and without it the last language to run would be the
    // only one on disk. The file above the scenario for the same reason, and
    // spelled the way the harness spells it (`<file>/<name>`): a name is
    // unique per file, not per suite, so two files naming the same screen
    // were overwriting each other step for step.
    var slug = assignment?.slug ?? '';
    var directory = Directory(
      '$destination/'
      '${slug.isEmpty ? '' : '${scenarioFileSafe(slug)}/'}'
      '${_source == null ? '' : '${scenarioFileSafe(_source)}/'}'
      '${scenarioFileSafe(_description)}',
    )..createSync(recursive: true);
    var prefix = '${pending.index}-';
    var base =
        '${directory.path}/$prefix'
        '${scenarioFileSafe(label, max: scenarioNameMax - prefix.length - '.png'.length)}';
    // What the step is a picture of, written as itself. This lane writes only
    // what a person would look at — no trees, no events — so a beat that is
    // not a screen writes its own content and nothing else.
    switch (pending.kind) {
      case ScenarioCaptureKind.screen:
        File('$base.png').writeAsBytesSync(pending.bytes!);
      case ScenarioCaptureKind.document:
        var name = (pending.fileName ?? pending.name ?? 'document').replaceAll(
          RegExp(r'[^A-Za-z0-9._-]+'),
          '_',
        );
        File('$base.$name').writeAsBytesSync(pending.payload!);
      case ScenarioCaptureKind.notification:
        // Three strings and no picture. Written anyway rather than skipped: a
        // destination directory that silently omits a beat reads as a flow
        // that never had one.
        File(
          '$base.notification.json',
        ).writeAsBytesSync(pending.notification!.encode());
    }
  }

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
    bool landed = true,
    int stray = 0,
    String? verb,
    String? target,
    ScenarioAim? aim,
    bool adopt = false,
  }) async {
    // Where this capture sits in the scenario's shape: the split choices
    // taken so far plus the count since the last one. Replays of a shared
    // prefix land on the same position — captured once, recognised after.
    var position = '${_state.plan.path}#${++_ordinal}';
    if (!_capturing) return;
    var parent = _lastPosition == null ? null : _state.emitted[_lastPosition!];
    if (_state.emitted.containsKey(position)) {
      // Already captured on an earlier replay — skip the rendering entirely,
      // but keep our place so the next new step's parent is right. The events
      // this replay collected on the way go with it: the step they belong to
      // was emitted on the first pass, with the events of *that* pass, and
      // appending these would multiply a shared prefix once per branch.
      appEventBuffer?.discard();
      _recorder?.discard();
      _lastCaptureFresh = false;
      _lastPosition = position;
      _pendingBranch = null;
      return;
    }
    // Nothing has moved since the last capture, so this is that capture with
    // a name on it. Adopting rather than rendering is the point: the second
    // picture is never taken, and the name lands on the step that already
    // carries the verb which produced the frame.
    //
    // Keyed like an emitted step so a later replay recognises the position
    // and skips it. The value is the *chain head* — what the step after this
    // one should call its parent — which is what every entry in this map has
    // always meant. Usually that is the step the name landed on; where a
    // frameless beat has been emitted since, it is the beat, and recording
    // the adopted step instead would fork the chain in two and leave the
    // aligner walking only one of them.
    if (adopt && shot != null && _canAdopt(settled: settled)) {
      _adoptOntoPending(shot);
      _state.emitted[position] = _state.stepCount;
      _lastPosition = position;
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
      landed: landed,
      stray: stray,
      verb: verb,
      target: target,
      aim: aim,
      position: position,
    );
    _lastCaptureFresh = true;
  }

  /// The frame the scenario broke on.
  ///
  /// Captured whatever the shot policy says, since a failure is the step most
  /// worth having a picture of, and deliberately given no position key: it
  /// belongs to this replay's dead end, never to a shared prefix a later
  /// replay would recognise.
  Future<void> _captureFailure(
    Object error, {
    String? verb,
    String? target,
  }) async {
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
      // The position this step *would* have had. A failure is never captured
      // twice, so nothing is keyed on it — but a comparison aligning two runs
      // needs somewhere to put it, and "the place the flow stopped" is the
      // only honest answer.
      position: '${_state.plan.path}#${_ordinal + 1}',
      // The verb that broke, on the step that records the break — a failed
      // step used to be the one step in a flow that could not say what it was
      // trying to do.
      verb: verb,
      target: target,
      aim: _aim,
      failure: '${_inContext(error)}',
    );
    // Handed over at once rather than held: a failure's picture is nobody's
    // to rename, and this replay is over — nothing is coming that could.
    _flushPending();
  }

  bool get _capturing =>
      scenarioRunListener != null || _screenshotsDestination != null;

  Future<void> _emit({
    required int index,
    required int? parent,
    required String? branch,
    required Shot? shot,
    required bool settled,
    bool landed = true,
    int stray = 0,
    String? verb,
    String? target,
    ScenarioAim? aim,
    required String position,
    String? failure,
  }) async {
    var listener = scenarioRunListener;
    // Whatever was being held goes now: this capture is about to take a frame
    // of its own, so it is not the name of the held one and nothing else can
    // be either.
    _flushPending();
    // Drained here rather than inside `runAsync`: the capture itself sends
    // platform messages (and the spy records them), and those belong to the
    // *next* transition, not to the one being closed.
    var (events, dropped) = appEventBuffer?.drain() ?? (const <AppEvent>[], 0);
    var overflowErrors = _overflowsSinceLastCapture;
    _overflowsSinceLastCapture = 0;
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
      var scale = scenarioCaptureScale(scenarioRunArgs, dpr);
      // Raw when the host asked for it: PNG *encoding* is ~80% of a 1×
      // capture's cost (56ms/step vs 11.5ms raw) and ~96% at 3× — the
      // rasterization itself is nearly free. Standalone runs always get PNG,
      // which everything can open.
      var raw = listener != null && (scenarioRunArgs?.captureRaw ?? false);
      Uint8List bytes;
      String format;
      int width;
      int height;
      if (listener != null && !(scenarioRunArgs?.capturePixels ?? true)) {
        // A budget probe reads the walk, not the pixels — skipping the
        // rasterization and the encode is what makes a probe pass cheaper
        // than the capture pass it rides beside. The dimensions are still
        // reported, because the survey computes screen share from them.
        bytes = Uint8List(0);
        format = 'none';
        width = (view.size.width * scale).round();
        height = (view.size.height * scale).round();
      } else {
        var image = await layer.toImage(
          Offset.zero & (view.size * dpr),
          pixelRatio: scale / dpr,
        );
        var data = (await image.toByteData(
          format: raw ? ui.ImageByteFormat.rawRgba : ui.ImageByteFormat.png,
        ))!;
        (width, height) = (image.width, image.height);
        image.dispose();
        bytes = data.buffer.asUint8List();
        format = raw ? 'raw' : 'png';
      }
      // Drained in the same `runAsync` as the shot: this is where the
      // rasterization `toImageSync` deferred is finally paid, and paying it
      // once for the whole transition is the difference between a recording
      // that costs 10ms and one that costs 250.
      var motion =
          await _recorder?.drain(raw: raw) ?? ScenarioMotionFrames.empty;
      // The overlay style the app last declared — what the GUI's fake status
      // bar tints itself with. Read at capture time rather than at hand-over,
      // because by then the app has moved on. Visible-for-testing is exactly
      // what this is: scenario code only ever runs under the test binding.
      // ignore: invalid_use_of_visible_for_testing_member
      var style = SystemChrome.latestStyle;
      // Held rather than handed over, so a `screen` that names this same
      // frame can put its name here instead of taking a second picture. See
      // [_pending] — this is the one step of latency that buys it.
      _pending = _PendingEmit(
        index: index,
        parent: parent,
        branch: branch,
        name: shot?.name,
        tags: shot?.tags ?? const [],
        bytes: bytes,
        format: format,
        width: width,
        height: height,
        texts: visibleTexts(),
        // Read here, beside the texts and the overlay style, for the reason
        // written on all three: this capture waits a step before it is handed
        // over, and by then the app has moved on.
        screen: scenarioScreenReader?.call(),
        statusBrightness: style?.statusBarIconBrightness?.name,
        navBrightness: style?.systemNavigationBarIconBrightness?.name,
        verb: verb,
        target: target,
        aim: aim,
        position: position,
        events: List.of(events),
        eventsDropped: dropped,
        motion: motion,
        motionInterval: _recorder?.interval,
        settled: settled,
        landed: landed,
        strayFrames: stray,
        failure: failure,
        overflowErrors: overflowErrors,
        frames: _frames,
        // What the screen lost to a keyboard when this was photographed. Read
        // here with the texts and the overlay style, for the reason written on
        // both: the hand-over is a step late and by then the app has moved on.
        keyboard: _keyboard.up ? _keyboard.height : null,
      );
    });
  }

  /// The visible text, in tree order — the projection an agent reads next to
  /// the screenshot. `EditableText` too, or what the user just typed into a
  /// `TextField` would be pixels only.
  List<String> visibleTexts() => visibleTextsOf(tester);

  /// Stands in for the define and the environment variable below, which are
  /// the two things a test process cannot change about itself: one is fixed at
  /// compile time and the other is read-only. Without it the standalone lane —
  /// what a bare `flutter test` writes, and the only lane a consumer's CI uses
  /// without the GUI — can be exercised nowhere but a subprocess.
  @visibleForTesting
  static String? screenshotsDestinationOverride;

  static String? get _screenshotsDestination {
    if (screenshotsDestinationOverride case var override?) return override;
    const define = String.fromEnvironment('screenshots-destination');
    if (define.isNotEmpty) return define;
    var env = Platform.environment['SCREENSHOTS_DESTINATION'];
    if (env != null && env.isNotEmpty) return env;
    return null;
  }
}

/// A capture that has been rendered but not yet handed over — see
/// [ScenarioTester._pending].
///
/// Mutable in exactly the places a following `screen` may still change: the
/// name, the tags, and what the flow produced on the way here. The rest is the
/// frame, which has been taken and does not move.
class _PendingEmit {
  _PendingEmit({
    required this.index,
    required this.parent,
    required this.branch,
    required this.name,
    required this.tags,
    required this.verb,
    required this.target,
    required this.position,
    required this.events,
    required this.eventsDropped,
    required this.settled,
    required this.landed,
    required this.strayFrames,
    required this.failure,
    required this.frames,
    this.overflowErrors = 0,
    this.keyboard,
    this.aim,
    this.kind = ScenarioCaptureKind.screen,
    this.bytes,
    this.format,
    this.width,
    this.height,
    this.texts = const [],
    this.screen,
    this.statusBrightness,
    this.navBrightness,
    this.payload,
    this.fileName,
    this.mimeType,
    this.notification,
    this.motion = ScenarioMotionFrames.empty,
    this.motionInterval,
  });

  final int index;
  final int? parent;
  final String? branch;

  /// The frame count when this picture was taken — the baseline a following
  /// `screen` proves nothing has been drawn since. Not the count at the end of
  /// the last *step*: a step whose shot was skipped captures nothing and still
  /// draws.
  final int frames;

  /// Null while the frame is anonymous — which is what makes it adoptable.
  /// A name arriving here from a later `screen` is indistinguishable
  /// afterwards from one the shot carried, and that is the point.
  String? name;
  List<String> tags;

  final ScenarioCaptureKind kind;
  final Uint8List? bytes;
  final String? format;
  final int? width;
  final int? height;
  final List<String> texts;

  /// The tree and the semantics behind [bytes], read at the shutter — see
  /// [ScenarioScreenRead] for why they cannot wait for the hand-over below.
  final ScenarioScreenRead? screen;
  final Uint8List? payload;
  final String? fileName;
  final String? mimeType;
  final ScenarioNotification? notification;
  final String? statusBrightness;
  final String? navBrightness;
  final String? verb;
  final String? target;

  /// Where the verb's finger went — see [ScenarioAim].
  final ScenarioAim? aim;

  final String position;
  final List<AppEvent> events;
  int eventsDropped;
  final ScenarioMotionFrames motion;
  final Duration? motionInterval;
  final bool settled;
  final bool landed;
  final int strayFrames;
  final String? failure;

  /// See [ScenarioStepCapture.overflowErrors] — carried on the edge into this
  /// step, like [events].
  final int overflowErrors;

  /// How tall the software keyboard was when this frame was taken, in logical
  /// pixels — null when it was down, which is nearly every step.
  final double? keyboard;

  ScenarioStepCapture toCapture() => ScenarioStepCapture(
    index: index,
    parent: parent,
    branch: branch,
    name: name,
    tags: tags,
    kind: kind,
    bytes: bytes,
    format: format,
    width: width,
    height: height,
    texts: texts,
    screen: screen,
    payload: payload,
    fileName: fileName,
    mimeType: mimeType,
    notification: notification,
    statusBrightness: statusBrightness,
    navBrightness: navBrightness,
    verb: verb,
    target: target,
    aim: aim,
    position: position,
    events: events,
    eventsDropped: eventsDropped,
    motion: motion,
    motionInterval: motionInterval,
    settled: settled,
    landed: landed,
    strayFrames: strayFrames,
    failure: failure,
    overflowErrors: overflowErrors,
    keyboard: keyboard,
  );
}

/// The software keyboard's own verbs — `s.keyboard`.
///
/// A scenario needs none of them for the ordinary case: tapping a field raises
/// a keyboard already. These are for the cases a flow cannot express on its
/// own — hold one up over a layout with nothing focused, swipe one away the way
/// a user does, or take one picture without it.
///
/// Each is a step like any other verb, so the flow shows the screen moving
/// rather than a screen that changed between two shots for no visible reason.
class ScenarioKeyboardVerbs {
  ScenarioKeyboardVerbs._(this._s);

  final ScenarioTester _s;

  /// Whether one is on screen.
  bool get isUp => _s._keyboard.up;

  /// Whether the **app** has asked for one — a field has focus, and the
  /// framework told the platform so.
  ///
  /// Separate from [isUp] because the two genuinely differ, and reporting only
  /// one is how a control ends up lying: [hide] leaves this true with nothing
  /// on screen, and [show] leaves it false with a keyboard over a third of it.
  bool get isRequested => _s._keyboard.requested;

  /// How much of the screen it is taking, in logical pixels — 0 when down.
  double get height => _s._keyboard.height;

  /// Whether this stage has a keyboard at all: false on a desktop size, on a
  /// run staged as nothing, and in a folder that turned the feature off.
  /// Every verb below is a no-op when it is false.
  bool get isAvailable => _s._keyboard.deviceHeight > 0;

  /// Holds it up, focus or no focus — *what does this layout do with a third
  /// of the screen gone*, asked without hunting for a field to tap.
  ///
  /// Sticky: the app asking for the keyboard to go away no longer takes it
  /// away. [auto] hands it back, and so does [dismiss].
  Future<void> show({Shot? shot, Settle? settle}) =>
      _set(KeyboardMode.up, 'show', shot, settle);

  /// Holds it down, whatever the app asks for — one picture of the whole
  /// screen in the middle of a flow that is typing into it.
  Future<void> hide({Shot? shot, Settle? settle}) =>
      _set(KeyboardMode.down, 'hide', shot, settle);

  /// Back to following the app, which is where every scenario starts.
  Future<void> auto({Shot? shot, Settle? settle}) =>
      _set(KeyboardMode.auto, 'auto', shot, settle);

  /// The platform closing it without the app being touched — a swipe down on
  /// Android, the dismiss key on an iPad.
  ///
  /// Not the same as [hide], and the difference is the whole reason both
  /// exist: this makes the app *let go*. The focused field is unfocused, so
  /// anything the app does on losing focus — validating, committing a draft,
  /// collapsing a suggestion list — actually happens. [hide] leaves the field
  /// focused and takes the picture away.
  Future<void> dismiss({Shot? shot, Settle? settle}) => _s._step(
    shot,
    settle,
    () async => _s._keyboard.dismiss(),
    verb: 'keyboard',
    target: 'dismiss',
  );

  Future<void> _set(
    KeyboardMode mode,
    String said,
    Shot? shot,
    Settle? settle,
  ) => _s._step(
    shot,
    settle,
    () async => _s._keyboard.jumpTo(mode),
    verb: 'keyboard',
    target: said,
  );
}
