import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
      await body(ScenarioTester._(tester, description, shots: shots));
    } finally {
      restore?.call();
    }
  });
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
  ScenarioTester._(this.tester, this._description, {required this.shots});

  /// The real tester — the escape hatch to the full `flutter_test` surface.
  final WidgetTester tester;

  final Shots shots;
  final String _description;
  var _stepCount = 0;

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
    _stepCount++;
    var listener = scenarioRunListener;
    var destination = _screenshotsDestination;
    if (listener == null && destination == null) return;
    await tester.runAsync(() async {
      var view = tester.binding.renderViews.single;
      var layer = view.debugLayer! as OffsetLayer;
      var image = await layer.toImage(Offset.zero & view.size);
      var data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      image.dispose();
      var png = data.buffer.asUint8List();
      if (listener != null) {
        listener(
          ScenarioStepCapture(
            index: _stepCount,
            name: shot?.name,
            tags: shot?.tags ?? const [],
            png: png,
            texts: visibleTexts(),
          ),
        );
        return;
      }
      var label = shot?.name ?? 'step $_stepCount';
      var directory = Directory('$destination/${_fileSafe(_description)}')
        ..createSync(recursive: true);
      File(
        '${directory.path}/$_stepCount-${_fileSafe(label)}.png',
      ).writeAsBytesSync(png);
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
