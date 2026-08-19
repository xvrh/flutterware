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
import 'asset_bundle.dart';
import 'async_watchdog.dart';
import 'events.dart';
import 'motion.dart';
import 'profile.dart';
import 'real_work.dart';
import 'run_args.dart';
import 'run_listener.dart';
import 'settle.dart';
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
          shots,
          settle,
          assignment,
          source,
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
          shots,
          settle,
          assignment,
          source,
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
) async {
  // The runner's assignment wins, like its args do below: the declaration
  // captured the ambient one, which under the runner is null — and a body
  // reading `s.assignment?.language` has to see the language the request
  // named, the same as it would under `flutter test` with `FW_LANGUAGES`.
  assignment = scenarioRunArgs?.assignment ?? assignment;
  var restore = _applyRunArgs(tester, assignment);
  // Whatever the scenario before this one left memoized on `rootBundle`
  // belongs to *its* FakeAsync zone. A read still in flight when that scenario
  // ended can never complete again — nothing will ever flush that zone — and
  // this scenario awaiting it waits forever. Cleared at the top rather than at
  // the bottom, so a run also survives whatever ran before the first scenario:
  // the harness loads the app's fonts through `rootBundle` at startup.
  rootBundle.clear();
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
      );
      try {
        await body(s);
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
    this._settle,
    this._state,
    this.assignment,
    this._source,
    this.assets,
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
  /// teardown pump, so tearing the tree down is never anybody's stray frame.
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
        DefaultAssetBundle(bundle: assets, child: widget),
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
  /// pump could complete, deadlocks the whole run silently. The watchdog says
  /// so in seconds, and names the cache that is nearly always behind it.
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
    () async => tester.tap(await _resolve(target, 'tap'), warnIfMissed: false),
    verb: 'tap',
    target: describeTarget(target),
  );

  Future<void> longPress(dynamic target, {Shot? shot, Settle? settle}) => _step(
    shot,
    settle,
    () async => tester.longPress(
      await _resolve(target, 'longPress'),
      warnIfMissed: false,
    ),
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
        () async => tester.drag(
          await _resolve(target, 'drag'),
          by,
          warnIfMissed: false,
        ),
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
  /// the whole point — so it says so itself when the scrolling never finds
  /// it, and when nothing scrolls and the target is absent or off screen.
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

  /// Captures a named screen without performing an action.
  Future<void> screen(
    String name, {
    List<String> tags = const [],
    Settle? settle,
  }) => _step(Shot(name, tags: tags), settle, () async {}, verb: 'screen');

  /// Hands the run something the flow produced that is not a widget — the PDF
  /// it just generated, the email body it queued, the payload it posted.
  ///
  /// It rides the **next** capture, exactly as recorded events do: an
  /// attachment describes what happened on the way to a step, and a document
  /// generally exists before the screen that announces it.
  ///
  /// ```dart
  /// var bytes = await s.runAsync(() => report.generatePdf());
  /// s.attach('report', bytes!, fileName: 'report.pdf');
  /// await s.screen('PDF report');
  /// ```
  ///
  /// A flow whose whole point is the document it produces was otherwise a
  /// scenario that stopped one step short: you could screenshot the button
  /// and prove nothing about what it made. Deliberately one verb rather than
  /// one per format — the format is [mimeType]'s job.
  ///
  /// Attached after the last capture of a scenario, it goes nowhere, which is
  /// the same bargain [events] strike and for the same reason: there is no
  /// step for it to belong to.
  void attach(
    String name,
    List<int> bytes, {
    String? fileName,
    String? mimeType,
  }) {
    if (!_capturing) return;
    _pendingAttachments.add(
      ScenarioAttachment(
        name: name,
        bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        fileName: fileName,
        mimeType: mimeType,
      ),
    );
  }

  /// What [attach] has collected since the last capture drained it.
  final _pendingAttachments = <ScenarioAttachment>[];

  /// One verb: act, wait per the policy, capture. The settle result rides the
  /// step, so a screen that never stopped animating says so instead of
  /// throwing.
  Future<void> _step(
    Shot? shot,
    Settle? settle,
    Future<void> Function() action, {
    String? verb,
    String? target,
  }) async {
    // Frames since the previous verb finished: nothing this scenario's verbs
    // drew, so they came from `s.tester` — and whatever they showed is not in
    // the flow. Read before the action, reported on the step it precedes.
    var stray = _frames - _framesAtLastStep;
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
        land: () => budget.land(tester, assets),
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
    required bool landed,
    required int stray,
    String? verb,
    String? target,
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
        ' `s.tester` is the raw tester if hitting whatever is on top is the '
        'point.',
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
  );

  /// Resolves a verb's target and insists it names exactly one widget the
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
      scenarioEventBuffer?.discard();
      _recorder?.discard();
      // Same reasoning for the attachments this replay collected on the way:
      // the step they belong to was emitted on the first pass, with that
      // pass's artifacts, and appending these would multiply a shared prefix
      // once per branch.
      _pendingAttachments.clear();
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
      landed: landed,
      stray: stray,
      verb: verb,
      target: target,
      position: position,
    );
  }

  /// The frame the scenario broke on.
  ///
  /// Captured whatever the shot policy says — a failure is the one step nobody
  /// asked for and everybody wants — and deliberately given no position key:
  /// it belongs to this replay's dead end, never to a shared prefix a later
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
    bool landed = true,
    int stray = 0,
    String? verb,
    String? target,
    required String position,
    String? failure,
  }) async {
    var listener = scenarioRunListener;
    var destination = _screenshotsDestination;
    // Drained here rather than inside `runAsync`: the capture itself sends
    // platform messages (and the spy records them), and those belong to the
    // *next* transition, not to the one being closed.
    var (events, dropped) =
        scenarioEventBuffer?.drain() ?? (const <ScenarioEvent>[], 0);
    var attachments = List.of(_pendingAttachments);
    _pendingAttachments.clear();
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
      // Drained in the same `runAsync` as the shot: this is where the
      // rasterization `toImageSync` deferred is finally paid, and paying it
      // once for the whole transition is the difference between a recording
      // that costs 10ms and one that costs 250.
      var motion =
          await _recorder?.drain(raw: raw) ?? ScenarioMotionFrames.empty;
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
            verb: verb,
            target: target,
            position: position,
            events: events,
            eventsDropped: dropped,
            motion: motion,
            motionInterval: _recorder?.interval,
            settled: settled,
            landed: landed,
            strayFrames: stray,
            failure: failure,
            attachments: attachments,
          ),
        );
        return;
      }
      var label = failure != null ? 'failed' : shot?.name ?? 'step $index';
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
      var prefix = '$index-';
      var base =
          '${directory.path}/$prefix'
          '${scenarioFileSafe(label, max: scenarioNameMax - prefix.length - '.png'.length)}';
      File('$base.png').writeAsBytesSync(bytes);
      // Beside the picture, under the same stem, so a destination directory
      // stays readable as "one step, its frame and whatever it produced".
      for (var (i, attachment) in attachments.indexed) {
        File(
          '$base.${scenarioAttachmentFileName(attachments, i)}',
        ).writeAsBytesSync(attachment.bytes);
      }
    });
  }

  /// The visible text, in tree order — the projection an agent reads next to
  /// the screenshot. `EditableText` too, or what the user just typed into a
  /// `TextField` would be pixels only.
  List<String> visibleTexts() => visibleTextsOf(tester);


  static String? get _screenshotsDestination {
    const define = String.fromEnvironment('screenshots-destination');
    if (define.isNotEmpty) return define;
    var env = Platform.environment['SCREENSHOTS_DESTINATION'];
    if (env != null && env.isNotEmpty) return env;
    return null;
  }
}
