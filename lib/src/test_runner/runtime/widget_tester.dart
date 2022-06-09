import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_studio/src/test_runner/protocol/models.dart';
import 'package:flutter_studio/src/test_runner/runtime/binding.dart';
import 'package:flutter_test/flutter_test.dart' as flutter;

import '../protocol/model/screen.dart';
import 'fake_window_padding.dart';
import 'path_tracker.dart';
import 'scenario.dart';

const String _defaultPlatform = kIsWeb ? 'web' : 'android';

Future<ui.Image> captureImage(Element element) {
  assert(element.renderObject != null);
  RenderObject renderObject = element.renderObject!;
  while (!renderObject.isRepaintBoundary) {
    renderObject = renderObject.parent! as RenderObject;
  }
  assert(!renderObject.debugNeedsPaint);
  final OffsetLayer layer = renderObject.debugLayer! as OffsetLayer;
  return layer.toImage(renderObject.paintBounds, pixelRatio: 1);
}

//TODO(xha): should come from Zone (injected by the runner). If direct tests:
// Default to EnvironmentVariable to define the behavior (device size etc...).
var _a = "";
RunContext runContext = EmptyRunContext();
PathTracker _pathTracker = PathTracker();
late WidgetTester tester;

Future<void> Function(flutter.WidgetTester) wrapTestBody(
    Future<void> Function(WidgetTester) body) {
  return (originalTester) async {
    var args = runContext.args;
    var device = args.device;
    var binding = flutter.AutomatedTestWidgetsFlutterBinding.instance;
    var window = binding.window;
    var platformDispatcher = binding.platformDispatcher;
    window.physicalSizeTestValue = Size(
        device.width * device.pixelRatio, device.height * device.pixelRatio);
    window.devicePixelRatioTestValue = device.pixelRatio;
    window.paddingTestValue = FakeWindowPadding(
      EdgeInsets.fromLTRB(
          device.safeArea.left * device.pixelRatio,
          device.safeArea.top * device.pixelRatio,
          device.safeArea.right * device.pixelRatio,
          device.safeArea.bottom * device.pixelRatio),
    );
    platformDispatcher.textScaleFactorTestValue = args.accessibility.textScale;
    platformDispatcher.accessibilityFeaturesTestValue =
        _FakeAccessibilityFeatures(args.accessibility);
    platformDispatcher.localesTestValue = [Locale('en', 'US')];
    debugDefaultTargetPlatformOverride = device.platform.toTargetPlatform();
    debugDisableShadows = false;
    tester = WidgetTester.delegated(originalTester);

    //TODO(xha): move that around the test so we can run the teardown & setup
    // between each run.
    _pathTracker = PathTracker();
    try {
      do {
        tester._screenIndex = 0;
        tester._previousTap = null;
        // Reset between the runs
        await tester.pumpWidget(const SizedBox());
        await body(tester);
      } while (_pathTracker.resetAndCheck());
    } catch (e, stackTrace) {
      print("Here fail $e");
      //await tester.screenshot();
      //await tester.pumpWidget(ErrorWidget(e));
      //await tester.screenshot();
      rethrow;
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    }
  };
}

Future<void> splitTest(Map<String, Future<void> Function()> paths) async {
  var index = _pathTracker.split(paths.length);
  var path = paths.entries.elementAt(index);
  tester._currentPathName = path.key;
  await path.value();
}

class WidgetTester implements flutter.WidgetTester {
  final flutter.WidgetTester delegate;
  int _screenIndex = 0;
  String? _previousId;
  Rect? _previousTap;
  String? _currentPathName;

  WidgetTester.delegated(this.delegate);
  final _previousScreens = <String>{};
  Future<void> screenshot() async {
    var index = ++_screenIndex;
    var parentIds = _pathTracker.id;

    var screenId = [...parentIds, index].join('-');

    var parentId = _previousId;
    _previousId = screenId;

    var isDuplicatedScreen = _previousScreens.contains(screenId);

    if (isDuplicatedScreen) {
      // Early exit. In "splits", we capture the same screen. To speed-up we skip
      // the screenshot part.
      _currentPathName = null;
      return;
    }
    _previousScreens.add(screenId);
    //var boundary = _boundaryKey.currentContext!.findRenderObject()!
    //  as RenderRepaintBoundary;

    await runAsync(() async {
      "pixel ratio from args";
      //var image = await boundary.toImage(pixelRatio: 1);
      var image = await captureImage(allElements.first);
      Future<void> f() async {
        Uint8List? pngBytes;
        var byteData =
            (await image.toByteData(format: ui.ImageByteFormat.png))!;
        pngBytes = byteData.buffer.asUint8List();

        var screen = Screen(screenId, "$screenId", isCollapsable: false)
            .rebuild((s) => s..pathName = _currentPathName);

        // File('_screenshots/$screenId-rawStraightRgba.bmp')
        //     .writeAsBytes(pngBytes);
        var newScreen = NewScreen((b) {
          b
            ..screen.replace(screen)
            ..imageBase64 = pngBytes != null ? base64Encode(pngBytes) : null
            ..parent = parentId;
        });
        //_logger.info('Add screen [$name] (id: $screenId, parent: $parentId)');
        await runContext.addScreen(newScreen);
      }

      await f();
    });
  }

  @override
  Iterable<Element> get allElements => delegate.allElements;

  @override
  Iterable<RenderObject> get allRenderObjects => delegate.allRenderObjects;

  @override
  Iterable<State<StatefulWidget>> get allStates => delegate.allStates;

  @override
  Iterable<Widget> get allWidgets => delegate.allWidgets;

  @override
  bool any(flutter.Finder finder) {
    return delegate.any(finder);
  }

  @override
  flutter.TestWidgetsFlutterBinding get binding => delegate.binding;

  @override
  flutter.Future<flutter.TestGesture> createGesture(
      {int? pointer,
      PointerDeviceKind kind = PointerDeviceKind.touch,
      int buttons = kPrimaryButton}) {
    return delegate.createGesture(
        pointer: pointer, kind: kind, buttons: buttons);
  }

  @override
  Ticker createTicker(TickerCallback onTick) {
    return delegate.createTicker(onTick);
  }

  @override
  void dispatchEvent(PointerEvent event, HitTestResult result) {
    delegate.dispatchEvent(event, result);
  }

  @override
  flutter.Future<void> drag(flutter.Finder finder, flutter.Offset offset,
      {int? pointer,
      int buttons = kPrimaryButton,
      double touchSlopX = flutter.kDragSlopDefault,
      double touchSlopY = flutter.kDragSlopDefault,
      bool warnIfMissed = true,
      PointerDeviceKind kind = PointerDeviceKind.touch}) {
    return delegate.drag(finder, offset,
        pointer: pointer,
        buttons: buttons,
        touchSlopX: touchSlopX,
        touchSlopY: touchSlopY,
        warnIfMissed: warnIfMissed,
        kind: kind);
  }

  @override
  flutter.Future<void> dragFrom(
      flutter.Offset startLocation, flutter.Offset offset,
      {int? pointer,
      int buttons = kPrimaryButton,
      double touchSlopX = flutter.kDragSlopDefault,
      double touchSlopY = flutter.kDragSlopDefault,
      PointerDeviceKind kind = PointerDeviceKind.touch}) {
    return delegate.dragFrom(startLocation, offset,
        pointer: pointer,
        buttons: buttons,
        touchSlopX: touchSlopX,
        touchSlopY: touchSlopY,
        kind: kind);
  }

  @override
  flutter.Future<void> dragUntilVisible(
      flutter.Finder finder, flutter.Finder view, flutter.Offset moveStep,
      {int maxIteration = 50,
      Duration duration = const Duration(milliseconds: 50)}) {
    return delegate.dragUntilVisible(finder, view, moveStep,
        maxIteration: maxIteration, duration: duration);
  }

  @override
  T element<T extends Element>(flutter.Finder finder) {
    return delegate.element(finder);
  }

  @override
  Iterable<T> elementList<T extends Element>(flutter.Finder finder) {
    return delegate.elementList(finder);
  }

  @override
  flutter.SemanticsHandle ensureSemantics() {
    return delegate.ensureSemantics();
  }

  @override
  flutter.Future<void> ensureVisible(flutter.Finder finder) {
    return delegate.ensureVisible(finder);
  }

  @override
  flutter.Future<void> enterText(flutter.Finder finder, String text) {
    return delegate.enterText(finder, text);
  }

  @override
  T firstElement<T extends Element>(flutter.Finder finder) {
    return delegate.firstElement(finder);
  }

  @override
  T firstRenderObject<T extends RenderObject>(flutter.Finder finder) {
    return delegate.firstRenderObject(finder);
  }

  @override
  T firstState<T extends State<StatefulWidget>>(flutter.Finder finder) {
    return delegate.firstState(finder);
  }

  @override
  T firstWidget<T extends Widget>(flutter.Finder finder) {
    return delegate.firstWidget(finder);
  }

  @override
  flutter.Future<void> fling(
      flutter.Finder finder, flutter.Offset offset, double speed,
      {int? pointer,
      int buttons = kPrimaryButton,
      Duration frameInterval = const Duration(milliseconds: 16),
      flutter.Offset initialOffset = Offset.zero,
      Duration initialOffsetDelay = const Duration(seconds: 1),
      bool warnIfMissed = true}) {
    return delegate.fling(finder, offset, speed,
        pointer: pointer,
        buttons: buttons,
        frameInterval: frameInterval,
        initialOffset: initialOffset,
        initialOffsetDelay: initialOffsetDelay,
        warnIfMissed: warnIfMissed);
  }

  @override
  flutter.Future<void> flingFrom(
      flutter.Offset startLocation, flutter.Offset offset, double speed,
      {int? pointer,
      int buttons = kPrimaryButton,
      Duration frameInterval = const Duration(milliseconds: 16),
      flutter.Offset initialOffset = Offset.zero,
      Duration initialOffsetDelay = const Duration(seconds: 1)}) {
    return delegate.flingFrom(startLocation, offset, speed,
        pointer: pointer,
        buttons: buttons,
        frameInterval: frameInterval,
        initialOffset: initialOffset,
        initialOffsetDelay: initialOffsetDelay);
  }

  @override
  flutter.Offset getBottomLeft(flutter.Finder finder,
      {bool warnIfMissed = false, String callee = 'getBottomLeft'}) {
    return delegate.getBottomLeft(finder,
        warnIfMissed: warnIfMissed, callee: callee);
  }

  @override
  flutter.Offset getBottomRight(flutter.Finder finder,
      {bool warnIfMissed = false, String callee = 'getBottomRight'}) {
    return delegate.getBottomRight(finder,
        warnIfMissed: warnIfMissed, callee: callee);
  }

  @override
  flutter.Offset getCenter(flutter.Finder finder,
      {bool warnIfMissed = false, String callee = 'getCenter'}) {
    return delegate.getCenter(finder,
        warnIfMissed: warnIfMissed, callee: callee);
  }

  @override
  Rect getRect(flutter.Finder finder) {
    return delegate.getRect(finder);
  }

  @override
  flutter.Future<flutter.TestRestorationData> getRestorationData() {
    return delegate.getRestorationData();
  }

  @override
  SemanticsNode getSemantics(flutter.Finder finder) {
    return delegate.getSemantics(finder);
  }

  @override
  Size getSize(flutter.Finder finder) {
    return delegate.getSize(finder);
  }

  @override
  flutter.Offset getTopLeft(flutter.Finder finder,
      {bool warnIfMissed = false, String callee = 'getTopLeft'}) {
    return delegate.getTopLeft(finder,
        warnIfMissed: warnIfMissed, callee: callee);
  }

  @override
  flutter.Offset getTopRight(flutter.Finder finder,
      {bool warnIfMissed = false, String callee = 'getTopRight'}) {
    return delegate.getTopRight(finder,
        warnIfMissed: warnIfMissed, callee: callee);
  }

  @override
  flutter.Future<List<Duration>> handlePointerEventRecord(
      Iterable<flutter.PointerEventRecord> records) {
    return delegate.handlePointerEventRecord(records);
  }

  @override
  bool get hasRunningAnimations => delegate.hasRunningAnimations;

  @override
  HitTestResult hitTestOnBinding(flutter.Offset location) {
    return delegate.hitTestOnBinding(location);
  }

  @override
  flutter.Future<void> idle() {
    return delegate.idle();
  }

  @override
  List<Layer> get layers => delegate.layers;

  @override
  flutter.Future<void> longPress(flutter.Finder finder,
      {int? pointer, int buttons = kPrimaryButton, bool warnIfMissed = true}) {
    return delegate.longPress(finder,
        pointer: pointer, buttons: buttons, warnIfMissed: warnIfMissed);
  }

  @override
  flutter.Future<void> longPressAt(flutter.Offset location,
      {int? pointer, int buttons = kPrimaryButton}) {
    return delegate.longPressAt(location, pointer: pointer, buttons: buttons);
  }

  @override
  int get nextPointer => delegate.nextPointer;

  @override
  flutter.Future<void> pageBack() {
    return delegate.pageBack();
  }

  @override
  flutter.Future<flutter.TestGesture> press(flutter.Finder finder,
      {int? pointer, int buttons = kPrimaryButton, bool warnIfMissed = true}) {
    return delegate.press(finder,
        pointer: pointer, buttons: buttons, warnIfMissed: warnIfMissed);
  }

  @override
  void printToConsole(String message) {
    delegate.printToConsole(message);
  }

  @override
  flutter.Future<void> pump(
      [Duration? duration,
      flutter.EnginePhase phase = flutter.EnginePhase.sendSemanticsUpdate]) {
    return delegate.pump(duration, phase);
  }

  @override
  flutter.Future<int> pumpAndSettle(
      [Duration duration = const Duration(milliseconds: 100),
      flutter.EnginePhase phase = flutter.EnginePhase.sendSemanticsUpdate,
      Duration timeout = const Duration(minutes: 10)]) {
    return delegate.pumpAndSettle(duration, phase, timeout);
  }

  @override
  flutter.Future<void> pumpBenchmark(Duration duration) {
    return delegate.pumpBenchmark(duration);
  }

  @override
  flutter.Future<void> pumpFrames(Widget target, Duration maxDuration,
      [Duration interval =
          const Duration(milliseconds: 16, microseconds: 683)]) {
    return delegate.pumpFrames(target, maxDuration, interval);
  }

  @override
  flutter.Future<void> pumpWidget(Widget widget,
      [Duration? duration,
      flutter.EnginePhase phase = flutter.EnginePhase.sendSemanticsUpdate]) {
    return delegate.pumpWidget(widget, duration, phase);
  }

  @override
  T renderObject<T extends RenderObject>(flutter.Finder finder) {
    return delegate.renderObject(finder);
  }

  @override
  Iterable<T> renderObjectList<T extends RenderObject>(flutter.Finder finder) {
    return delegate.renderObjectList(finder);
  }

  @override
  flutter.Future<void> restartAndRestore() {
    return delegate.restartAndRestore();
  }

  @override
  flutter.Future<void> restoreFrom(flutter.TestRestorationData data) {
    return delegate.restoreFrom(data);
  }

  @override
  flutter.Future<T?> runAsync<T>(flutter.Future<T> Function() callback,
      {Duration additionalTime = const Duration(milliseconds: 1000)}) {
    return delegate.runAsync(callback, additionalTime: additionalTime);
  }

  @override
  flutter.Future<void> scrollUntilVisible(flutter.Finder finder, double delta,
      {flutter.Finder? scrollable,
      int maxScrolls = 50,
      Duration duration = const Duration(milliseconds: 50)}) {
    return delegate.scrollUntilVisible(finder, delta,
        scrollable: scrollable, maxScrolls: maxScrolls, duration: duration);
  }

  @override
  flutter.Future<void> sendEventToBinding(PointerEvent event) {
    return delegate.sendEventToBinding(event);
  }

  @override
  flutter.Future<bool> sendKeyDownEvent(LogicalKeyboardKey key,
      {String? character, String platform = _defaultPlatform}) {
    return delegate.sendKeyDownEvent(key,
        character: character, platform: platform);
  }

  @override
  flutter.Future<bool> sendKeyEvent(LogicalKeyboardKey key,
      {String platform = _defaultPlatform}) {
    return delegate.sendKeyEvent(key, platform: platform);
  }

  @override
  flutter.Future<bool> sendKeyRepeatEvent(LogicalKeyboardKey key,
      {String? character, String platform = _defaultPlatform}) {
    return delegate.sendKeyRepeatEvent(key,
        character: character, platform: platform);
  }

  @override
  flutter.Future<bool> sendKeyUpEvent(LogicalKeyboardKey key,
      {String platform = _defaultPlatform}) {
    return delegate.sendKeyUpEvent(key, platform: platform);
  }

  @override
  flutter.Future<void> showKeyboard(flutter.Finder finder) {
    return delegate.showKeyboard(finder);
  }

  @override
  flutter.Future<flutter.TestGesture> startGesture(flutter.Offset downLocation,
      {int? pointer,
      PointerDeviceKind kind = PointerDeviceKind.touch,
      int buttons = kPrimaryButton}) {
    return delegate.startGesture(downLocation,
        pointer: pointer, kind: kind, buttons: buttons);
  }

  @override
  T state<T extends State<StatefulWidget>>(flutter.Finder finder) {
    return delegate.state(finder);
  }

  @override
  Iterable<T> stateList<T extends State<StatefulWidget>>(
      flutter.Finder finder) {
    return delegate.stateList(finder);
  }

  @override
  dynamic takeException() {
    return delegate.takeException();
  }

  @override
  flutter.Future<void> tap(flutter.Finder finder,
      {int? pointer, int buttons = kPrimaryButton, bool warnIfMissed = true}) {
    return delegate.tap(finder,
        pointer: pointer, buttons: buttons, warnIfMissed: warnIfMissed);
  }

  @override
  flutter.Future<void> tapAt(flutter.Offset location,
      {int? pointer, int buttons = kPrimaryButton}) {
    return delegate.tapAt(location, pointer: pointer, buttons: buttons);
  }

  @override
  String get testDescription => delegate.testDescription;

  @override
  flutter.TestTextInput get testTextInput => delegate.testTextInput;

  @override
  flutter.Future<void> timedDrag(
      flutter.Finder finder, flutter.Offset offset, Duration duration,
      {int? pointer,
      int buttons = kPrimaryButton,
      double frequency = 60.0,
      bool warnIfMissed = true}) {
    return delegate.timedDrag(finder, offset, duration,
        pointer: pointer,
        buttons: buttons,
        frequency: frequency,
        warnIfMissed: warnIfMissed);
  }

  @override
  flutter.Future<void> timedDragFrom(
      flutter.Offset startLocation, flutter.Offset offset, Duration duration,
      {int? pointer, int buttons = kPrimaryButton, double frequency = 60.0}) {
    return delegate.timedDragFrom(startLocation, offset, duration,
        pointer: pointer, buttons: buttons, frequency: frequency);
  }

  @override
  void verifyTickersWereDisposed([String when = 'when none should have been']) {
    delegate.verifyTickersWereDisposed(when);
  }

  @override
  T widget<T extends Widget>(flutter.Finder finder) {
    return delegate.widget(finder);
  }

  @override
  Iterable<T> widgetList<T extends Widget>(flutter.Finder finder) {
    return delegate.widgetList(finder);
  }
}

class _FakeAccessibilityFeatures implements ui.AccessibilityFeatures {
  final AccessibilityConfig config;

  _FakeAccessibilityFeatures(this.config);

  @override
  bool get accessibleNavigation => false;

  @override
  bool get boldText => config.boldText;

  @override
  bool get disableAnimations => false;

  @override
  bool get highContrast => false;

  @override
  bool get invertColors => false;

  @override
  bool get reduceMotion => false;

  @override
  bool get onOffSwitchLabels => false;
}
