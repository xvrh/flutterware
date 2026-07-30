import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

import 'run_args.dart';
import 'run_listener.dart';

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
@isTest
void scenario(
  String description,
  Future<void> Function(ScenarioTester s) body, {
  Shots shots = Shots.auto,
}) {
  testWidgets(description, (tester) async {
    var restore = _applyRunArgs(tester);
    try {
      // The split-replay loop: the body runs once per path through its
      // `split`s, depth-first — a body with none runs once. Every replay
      // starts from the top, so its `pumpWidget` rebuilds the app from
      // scratch; steps already captured on a shared prefix are recognised by
      // position and not captured again.
      var state = _ReplayState();
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
        await body(ScenarioTester._(tester, description, shots, state));
      } while (state.plan.advance());
    } finally {
      restore?.call();
    }
  });
}

/// What survives across a scenario's replays: which paths ran, which step
/// positions were already captured, and the global step numbering.
class _ReplayState {
  final plan = _SplitPlan();

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
VoidCallback? _applyRunArgs(WidgetTester tester) {
  var args = scenarioRunArgs;
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
class ScenarioTester {
  ScenarioTester._(this.tester, this._description, this.shots, this._state);

  /// The real tester — the escape hatch to the full `flutter_test` surface.
  final WidgetTester tester;

  final Shots shots;
  final String _description;

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

  Future<void> pumpWidget(Widget widget, {Shot? shot}) async {
    await tester.pumpWidget(widget);
    await tester.pump();
    await _afterStep(shot);
  }

  /// Taps [target] — a `Finder`, a `String` (visible text), a `Key`, an
  /// `IconData`, or a `Type`.
  ///
  /// `dynamic` is a deliberate exception to the house no-dynamic preference:
  /// `tap('NEXT')` / `tap(Icons.add)` / `tap(Keys.next)` read too well to give
  /// up, and the auto-write generator emits exactly the string form.
  Future<void> tap(dynamic target, {Shot? shot}) async {
    await tester.tap(finderFor(target));
    await tester.pumpAndSettle();
    await _afterStep(shot);
  }

  Future<void> enterText(dynamic target, String text, {Shot? shot}) async {
    await tester.enterText(finderFor(target), text);
    await tester.pumpAndSettle();
    await _afterStep(shot);
  }

  /// Captures a named screen without performing an action.
  Future<void> screen(String name, {List<String> tags = const []}) =>
      _capture(Shot(name, tags: tags));

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
  Future<void> split(Map<String, Future<void> Function()> branches) async {
    if (branches.isEmpty) return;
    var names = branches.keys.toList();
    var name = names[_state.plan.choose(names.length)];
    // A new segment: positions restart under the extended choice path, and
    // the branch's first capture wears the label.
    _ordinal = 0;
    _pendingBranch = name;
    await branches[name]!();
  }

  Future<void> _afterStep(Shot? shot) async {
    if (identical(shot, Shot.skip)) return;
    if (shot == null && shots == Shots.manual) return;
    await _capture(shot);
  }

  /// Resolves the polymorphic target of [tap] and [enterText] to a [Finder].
  @visibleForTesting
  Finder finderFor(dynamic target) {
    return switch (target) {
      Finder() => target,
      String() => find.text(target, findRichText: true),
      Key() => find.byKey(target),
      IconData() => find.byIcon(target),
      Type() => find.byType(target),
      _ => throw ArgumentError(
        'tap/enterText take a Finder, String, Key, IconData or Type — '
        'got ${target.runtimeType}',
      ),
    };
  }

  /// Captures one step.
  ///
  /// Under the flutterware runner the harness listens and receives the bytes.
  /// Standalone (bare `flutter test`), a screenshot is written only when a
  /// destination is configured — via
  /// `--dart-define=screenshots-destination=…` or the
  /// `SCREENSHOTS_DESTINATION` environment variable — and skipped otherwise,
  /// so plain CI runs pay nothing for it.
  Future<void> _capture(Shot? shot) async {
    // Where this capture sits in the scenario's shape: the split choices
    // taken so far plus the count since the last one. Replays of a shared
    // prefix land on the same position — captured once, recognised after.
    var position = '${_state.plan.path}#${++_ordinal}';
    var listener = scenarioRunListener;
    var destination = _screenshotsDestination;
    if (listener == null && destination == null) return;
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
      var scale = scenarioRunArgs?.captureScale ?? 1.0;
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
          ),
        );
        return;
      }
      var label = shot?.name ?? 'step $index';
      var directory = Directory('$destination/${_fileSafe(_description)}')
        ..createSync(recursive: true);
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
