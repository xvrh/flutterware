import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart' hide WidgetTester;
import 'package:logging/logging.dart';
import 'package:pool/pool.dart';
import '../protocol/models.dart';
import 'asset_bundle.dart';
import 'extract_text.dart';
import 'fake_window_padding.dart';
import 'path_tracker.dart';
import 'widget_tester.dart';
import 'widget_tester_extension.dart';

final _logger = Logger('scenario');

abstract class RunContext {
  Future<void> addScreen(RunArgs args, NewScreen newScreen);
}

abstract class Scenario {
  late RunContext _runContext;
  late AutomatedTestWidgetsFlutterBinding _binding;
  late ScenarioBundle _bundle;
  late RunArgs _args;
  late ProjectInfo _project;
  late WidgetTester _tester;
  final _boundaryKey = GlobalKey();
  int _screenIndex = 0;
  String? _previousId;
  Rect? _previousTap;
  String? _currentPathName;
  late Pool _uploadScreenPool;

  /// Override this field to set a description of the scenario
  String? get description => null;

  AutomatedTestWidgetsFlutterBinding get binding => _binding;

  RunArgs get args => _args;

  ProjectInfo get projectInfo => _project;

  Future<void> setUp() async {}

  Future<void> run();

  WidgetTester get tester => _tester;

  Widget? _widget;
  Future<void> pumpWidget(Widget widget) async {
    _widget = widget;

    widget = wrapWidget(widget);

    await _tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _bundle,
        child: RepaintBoundary(key: _boundaryKey, child: widget),
      ),
    );
  }

  Widget wrapWidget(Widget child) => child;

  Future<void> rePumpWidget() async {
    var widget = _widget;
    if (widget != null) {
      await pumpWidget(widget);
    }
  }

  Future<void> pump([Duration? duration]) async {
    await _tester.pump(duration);
  }

  Future<void> pumpAndSettle() async {
    await _tester.pumpAndSettle();
  }

  Future<List<TextInfo>> captureTexts(
      {Finder? ancestor, required bool onlyReset}) async {
    // Need to be overridden per project to bind to the translation system.
    return [];
  }

  Future<void> waitForAssets() async {
    await tester.waitForAssets();
    await _tester.runAsync(() => _bundle.waitFinishLoading());
    await tester.waitForNetworkImages();
    await rePumpWidget();
  }

  // Need to be overridden per project to bind to the analytic system.
  AnalyticEvent? lastAnalyticEvent() => null;

  final _previousScreens = <String>{};

  Future<void> screen(
    String name, {
    String? description,
    String? group,
    bool? pumpFrames,
    String? documentationKey,
    Finder? translationAncestor,
    bool? detail,
  }) async {
    pumpFrames ??= true;
    var index = ++_screenIndex;
    var parentIds = _pathTracker.id;

    var screenId = [...parentIds, index].join('-');

    var parentId = _previousId;
    _previousId = screenId;

    var parentRectangle = _previousTap;
    _previousTap = null;

    if (pumpFrames) {
      await tester.pumpAndSettle();
    }
    await waitForAssets();

    var isDuplicatedScreen = _previousScreens.contains(screenId);
    var texts = await captureTexts(
        ancestor: translationAncestor, onlyReset: isDuplicatedScreen);
    var analyticEvent = lastAnalyticEvent();

    if (isDuplicatedScreen) {
      // Early exit. In "splits", we capture the same screen. To speed-up we skip
      // the screenshot part.
      _currentPathName = null;
      return;
    }
    _previousScreens.add(screenId);

    var boundary = _boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;

    var captureScreenshot =
        !args.onlyWithDocumentationKey || documentationKey != null;

    await _tester.runAsync(() async {
      Uint8List? pngBytes;
      if (_args.imageRatio > 0 && captureScreenshot) {
        var image = await boundary.toImage(pixelRatio: _args.imageRatio);
        var byteData =
            (await image.toByteData(format: ui.ImageByteFormat.png))!;
        pngBytes = byteData.buffer.asUint8List();
      }

      var screen =
          Screen(screenId, name, isCollapsable: detail).rebuild((s) => s
            ..texts.replace(texts)
            ..documentationKey = documentationKey
            ..pathName = _currentPathName);
      _currentPathName = null;

      var newScreen = NewScreen((b) {
        b
          ..screen.replace(screen)
          ..imageBase64 = pngBytes != null ? base64Encode(pngBytes) : null
          ..parent = parentId
          ..analyticEvent = analyticEvent?.toBuilder();
        if (parentRectangle != null) {
          b.parentRectangle.replace(Rectangle.fromLTRB(
              parentRectangle.left,
              parentRectangle.top,
              parentRectangle.right,
              parentRectangle.bottom));
        }
      });
      _logger.info('Add screen [$name] (id: $screenId, parent: $parentId)');
      unawaited(_uploadScreenPool
          .withResource(() => _runContext.addScreen(_args, newScreen)));
    });
  }

  Future<void> emailScreen(
    String name, {
    required String subject,
    required String body,
    required String sender,
    required String recipient,
    String? documentationKey,
  }) async {
    await _addScreen(name, 'email',
        updates: (s) => s
          ..documentationKey = documentationKey
          ..email.replace(EmailInfo(
            subject: subject,
            body: body,
            sender: sender,
            recipient: recipient,
          )));
  }

  Future<void> pdfScreen(
    String name, {
    required Uint8List bytes,
    required String fileName,
  }) async {
    await _addScreen(name, 'pdf',
        updates: (s) => s
          ..pdf.replace(PdfInfo(
            bytes: bytes,
            fileName: fileName,
          )));
  }

  Future<void> jsonScreen(
    String name, {
    required String data,
    required String fileName,
  }) async {
    await _addScreen(name, 'json',
        updates: (s) => s
          ..json.replace(JsonInfo(
            data: data,
            fileName: fileName,
          )));
  }

  Future<void> _addScreen(String name, String type,
      {required void Function(ScreenBuilder) updates}) async {
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

    await _tester.runAsync(() async {
      var screen = Screen(screenId, name)
          .rebuild((s) => s..pathName = _currentPathName)
          .rebuild(updates);
      _currentPathName = null;

      var newScreen = NewScreen((b) {
        b
          ..screen.replace(screen)
          ..parent = parentId;
      });
      _logger.info('Add $type [$name] (id: $screenId, parent: $parentId)');
      unawaited(_uploadScreenPool
          .withResource(() => _runContext.addScreen(_args, newScreen)));
    });
  }

  Future<void> refreshIndicator() async {
    await tester.fling(find.byType(RefreshIndicator),
        Offset(0, binding.window.physicalSize.height * 0.6), 1000.0);
    await pumpAndSettle();
  }

  Finder _targetToFinder(dynamic target) {
    if (target is Finder) {
      return target;
    } else if (target is String) {
      return TextFinder(target);
    } else if (target is Key) {
      return find.byKey(target);
    } else if (target is Type) {
      return find.byType(target);
    } else {
      throw StateError('Unsupported target ${target.runtimeType}');
    }
  }

  Future<void> ensureVisible(dynamic target) async {
    var finder = _targetToFinder(target);
    await tester.ensureVisible(finder);
    await pumpAndSettle();
  }

  Future<void> tap(dynamic target, {bool pumpFrames = true}) async {
    var finder = _targetToFinder(target);

    await _tap(finder);
    if (pumpFrames) {
      await _tester.pumpAndSettle();
    }
  }

  Future<void> _tap(Finder finder) async {
    var box = _getElementBox(finder, callee: 'tap');
    _previousTap ??=
        box.localToGlobal(box.size.topLeft(Offset.zero)) & box.size;

    final center = box.localToGlobal(box.size.center(Offset.zero));
    await _tester.tapAt(center);
  }

  Future<void> longPress(Finder finder) async {
    var box = _getElementBox(finder, callee: 'longPress');
    final center = box.localToGlobal(box.size.center(Offset.zero));
    await _tester.longPressAt(center);
  }

  RenderBox _getElementBox(
    Finder finder, {
    required String callee,
  }) {
    TestAsyncUtils.guardSync();
    final elements = finder.evaluate();
    if (elements.isEmpty) {
      throw FlutterError(
          'The finder "$finder" (used in a call to "$callee()") could not find any matching widgets.');
    }
    if (elements.length > 1) {
      throw FlutterError(
          'The finder "$finder" (used in a call to "$callee()") ambiguously found multiple matching widgets. The "$callee()" method needs a single target.');
    }
    final element = elements.single;
    final renderObject = element.renderObject;
    if (renderObject == null) {
      throw FlutterError(
          'The finder "$finder" (used in a call to "$callee()") found an element, but it does not have a corresponding render object. '
          'Maybe the element has not yet been rendered?');
    }
    if (renderObject is! RenderBox) {
      throw FlutterError(
          'The finder "$finder" (used in a call to "$callee()") found an element whose corresponding render object is not a RenderBox (it is a ${renderObject.runtimeType}: "$renderObject"). '
          'Unfortunately "$callee()" only supports targeting widgets that correspond to RenderBox objects in the rendering.');
    }
    final box = element.renderObject! as RenderBox;
    return box;
  }

  Future<void> enterText(Key key, String text) async {
    await _tester.enterText(find.byKey(key), text);
    await _tester.pumpAndSettle();
  }

  Future<void> back() async {
    var backButton = find.byType(BackButton);
    if (backButton.evaluate().isEmpty) {
      backButton = find.byType(CupertinoNavigationBarBackButton);
    }
    if (backButton.evaluate().isEmpty) {
      backButton = find.byType(CloseButton);
    }
    await _tap(backButton);
  }

  T elementByKey<T extends Element>(Key key) =>
      tester.element<T>(find.byKey(key));

  Future<void> split(Map<String, Future<void> Function()> paths) async {
    var index = _pathTracker.split(paths.length);
    var path = paths.entries.elementAt(index);
    _currentPathName = path.key;
    await path.value();
  }

  late PathTracker _pathTracker;

  Future<Object?> execute(
      RunContext runContext,
      AutomatedTestWidgetsFlutterBinding binding,
      ScenarioBundle bundle,
      ProjectInfo project,
      RunArgs args) async {
    _runContext = runContext;
    _bundle = bundle;
    _project = project;
    _binding = binding;
    _args = args;

    var tester = WidgetTester(binding);
    _tester = tester;

    var device = args.device;
    var window = binding.window;
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
    window.textScaleFactorTestValue = args.accessibility.textScale;
    window.accessibilityFeaturesTestValue =
        _FakeAccessibilityFeatures(args.accessibility);
    window.localesTestValue = [Locale('en', 'US')];

    _pathTracker = PathTracker();
    _previousScreens.clear();

    _uploadScreenPool = Pool(1);

    Object? error;
    FlutterError.onError = (e) {
      error = e;
      FlutterError.presentError(e);
    };

    await runZonedGuarded(() async {
      await binding.runTest(
        () async {
          binding.reset();

          debugDefaultTargetPlatformOverride =
              device.platform.toTargetPlatform();
          debugDisableShadows = false;

          try {
            await _bundle.runWithNetworkOverride(() async {
              do {
                _screenIndex = 0;
                _previousTap = null;
                // Reset between the runs
                await tester.pumpWidget(const SizedBox());
                await setUp();
                await run();
              } while (_pathTracker.resetAndCheck());
            });
          } catch (e, stackTrace) {
            error = e;
            _logger.info(
                'Test ${args.scenarioName.join('/')} failed with error:\n$e\n$stackTrace');
            await screen('<Before Error>');
            await pumpWidget(ErrorWidget(e));
            await screen('<Error>');
          }
          debugDefaultTargetPlatformOverride = null;
          debugDisableShadows = true;
        },
        () {},
        description: args.scenarioName.join('/'),
      );
      if (error == null) {
        tester.endOfTestVerifications();
      }
      binding.postTest();
    }, (e, stackTrace) {
      error = e;
      _logger.warning('Zone error $e $stackTrace');
    });
    await _uploadScreenPool.close();

    return error;
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
}
