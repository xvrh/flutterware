import 'package:flutter/widgets.dart';
import '../api.dart';
import 'extract_text.dart';
import 'run_context.dart';

abstract class AppTest {
  Future<void> setUp() async {}
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
  }

  Future<void> pump([
    Duration? duration,
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  ]) async {
    await tester.pump(duration, phase);
  }

  Finder _targetToFinder(dynamic target) {
    if (target is Finder) {
      return target;
    } else if (target is String) {
      return TextFinder(target);
    } else if (target is IconData) {
      return find.byIcon(target);
    } else if (target is Key) {
      return find.byKey(target);
    } else if (target is Type) {
      return find.byType(target);
    } else {
      throw StateError('Unsupported target ${target.runtimeType}');
    }
  }

  Future<void> enterText(
    dynamic target,
    String text, {
    bool pumpFrames = true,
  }) async {
    var finder = _targetToFinder(target);
    await tester.enterText(finder, text);
    await _pumpFramesIfNeeded(pumpFrames);
  }

  Future<void> tap(
    dynamic target, {
    bool pumpFrames = true,
  }) async {
    var finder = _targetToFinder(target);

    var box = _getElementBox(finder);
    if (box != null) {
      tester.runContext.previousTap ??=
          box.localToGlobal(box.size.topLeft(Offset.zero)) & box.size;
    }

    await tester.tap(finder);
    await _pumpFramesIfNeeded(pumpFrames);
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

  Future<void> _pumpFramesIfNeeded(bool needed) async {
    if (needed) {
      await tester.waitForAssets();
      await tester.pumpAndSettle();
    }
  }

  Future<void> screenshot({String? name, List<String>? tags}) {
    return tester.screenshot(name: name, tags: tags);
  }
}
