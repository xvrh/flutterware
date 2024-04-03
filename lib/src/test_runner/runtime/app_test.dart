import 'package:flutter/widgets.dart';
import '../api.dart';
import 'extract_text.dart';
import 'run_context.dart';

/// This class allow for a simpler API to write widget test.
///
/// ```dart
/// void main() {
///   testApp('Test example', CheckoutTest());
/// }
///
/// class CheckoutTest extends AppTest {
///   @override
///   Future<void> run() async {
///     await pumpWidget(MyApp());
///     await screenshot();
///
///     await tap(ElevatedButton);
///     await screenshot();
///
///     await enterText(TextField, 'Name');
///     await screenshot();
///   }
/// }
/// ```
abstract class AppTest {
  /// This function is run before each test and allows to setup the test environment
  Future<void> setUp() async {}

  /// This function is run after each test and allows to clean the test environment
  Future<void> tearDown() async {}

  Future<void> run();

  WidgetTester? _tester;
  WidgetTester get tester {
    var tester = _tester;
    if (tester == null) {
      throw Exception('tester is only available when the test is run');
    }
    return tester;
  }

  Future<void> call(WidgetTester tester) async {
    _tester = tester;
    var runContext = tester.runContext;
    try {
      do {
        runContext.screenIndex = 0;
        // Reset between the runs
        await tester.pumpWidget(const SizedBox());
        await setUp();
        await run();
      } while (runContext.pathTracker.resetAndCheck());
    } finally {
      await tearDown();
      _tester = null;
    }
  }

  Future<void> splitTest(Map<String, Future<void> Function()> paths) async {
    var runContext = tester.runContext;

    var index = runContext.pathTracker.split(paths.length);
    var path = paths.entries.elementAt(index);
    runContext.currentSplitName = path.key;
    await path.value();
  }

  Future<void> pumpWidget(
    Widget widget, {
    bool pumpFrames = true,
  }) async {
    await tester.pumpWidget(widget);
    await _pumpFramesIfNeeded(pumpFrames);
    await _screenshotIfNeeded();
  }

  Future<void> pump([
    Duration? duration,
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  ]) async {
    await tester.pump(duration, phase);
  }

  Finder targetToFinder(dynamic target, {bool skipOffStage = true}) {
    if (target is Finder) {
      return target;
    } else if (target is String) {
      return TextFinder(target, skipOffstage: skipOffStage);
    } else if (target is IconData) {
      return find.byIcon(target, skipOffstage: skipOffStage);
    } else if (target is Key) {
      return find.byKey(target, skipOffstage: skipOffStage);
    } else if (target is Type) {
      return find.byType(target, skipOffstage: skipOffStage);
    } else {
      throw StateError('Unsupported target ${target.runtimeType}');
    }
  }

  Future<void> enterText(
    dynamic target,
    String text, {
    bool pumpFrames = true,
  }) async {
    var finder = targetToFinder(target);
    await tester.enterText(finder, text);
    await _pumpFramesIfNeeded(pumpFrames);
    await _screenshotIfNeeded();
  }

  Future<void> tap(
    dynamic target, {
    bool pumpFrames = true,
    bool warnIfMissed = true,
  }) async {
    var finder = targetToFinder(target);

    var box = _getElementBox(finder);
    if (box != null) {
      tester.runContext.previousTap ??=
          box.localToGlobal(box.size.topLeft(Offset.zero)) & box.size;
    }

    await tester.tap(finder, warnIfMissed: warnIfMissed);
    await _pumpFramesIfNeeded(pumpFrames);
    await _screenshotIfNeeded();
  }

  Future<void> dragUntilVisible(dynamic target, dynamic scrollview,
      {Offset? moveStep}) async {
    var finder = targetToFinder(target, skipOffStage: false);
    var scrollFinder = targetToFinder(scrollview);
    await tester.dragUntilVisible(
        finder, scrollFinder, moveStep ?? Offset(0, -100));
    await pumpAndSettle();
  }

  Future<void> ensureVisible(dynamic target) async {
    var finder = targetToFinder(target, skipOffStage: false);
    await tester.ensureVisible(finder);
    await pumpAndSettle();
    await _screenshotIfNeeded();
  }

  RenderBox? _getElementBox(Finder finder) {
    final elements = finder.evaluate();
    if (elements.isNotEmpty) {
      var renderBox = elements.first.renderObject;
      if (renderBox is RenderBox) {
        return renderBox;
      }
    }
    return null;
  }

  Future<void> pumpAndSettle() async {
    await tester.waitForAssets();
    await tester.pumpAndSettle();
  }

  Future<void> _pumpFramesIfNeeded(bool needed) async {
    if (needed) {
      await pumpAndSettle();
    }
  }

  bool autoScreenshot = false;

  /// Takes a screenshot of the current widget and display it in the Flutterware
  /// visualizer
  Future<void> screenshot({String? name, List<String>? tags}) {
    return tester.screenshot(name: name, tags: tags);
  }

  Future<void> _screenshotIfNeeded() async {
    if (autoScreenshot) {
      await screenshot();
    }
  }
}
