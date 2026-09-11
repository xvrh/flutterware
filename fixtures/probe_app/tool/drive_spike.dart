// Throwaway spike target for the run-drive design
// (docs/superpowers/specs/2026-08-11-run-drive-design.md).
//
// A live `flutter run` app that imports flutter_test, holds a
// LiveWidgetController over the real binding, and serves drive verbs over a
// service extension. Driven by app/tool/drive_spike/driver.dart.
//
//   flutter run -d macos -t tool/drive_spike.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:flutterware/drive.dart' as drive;
import 'package:flutterware/run_guest.dart' as guest;

final tapLog = <String>[];
final textEvents = <String>[];
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // The real run guest — what a generated run entrypoint installs — plus the
  // spike's own hand-rolled probes beside it.
  guest.runGuest(() {
    SpikeDrive.instance.register();
    runApp(const SpikeApp());
  });
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: const HomePage(),
      routes: {
        'moving': (_) => const MovingPage(),
        'text': (_) => const TextPage(),
        'spinner': (_) => const SpinnerPage(),
        'list': (_) => const ListPage(),
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _count = 0;

  Widget _navButton(String label, String route) {
    return ElevatedButton(
      onPressed: () {
        tapLog.add('nav-$route');
        Navigator.of(context).pushNamed(route);
      },
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drive spike')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Count: $_count'),
            ElevatedButton(
              onPressed: () {
                tapLog.add('increment');
                // For the logs-since leg of the act bundle.
                print('increment pressed');
                setState(() => _count++);
              },
              child: const Text('Increment'),
            ),
            _navButton('Moving', 'moving'),
            _navButton('Text', 'text'),
            _navButton('Spinner', 'spinner'),
            _navButton('List', 'list'),
            ElevatedButton(
              onPressed: () {
                tapLog.add('push');
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PushedPage()),
                );
              },
              child: const Text('Push'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Buttons oscillating vertically with staggered phases so neighbours cross
/// and overlap, plus a slide-in entrance — the tap-under-animation stress.
class MovingPage extends StatefulWidget {
  const MovingPage({super.key});

  @override
  State<MovingPage> createState() => _MovingPageState();
}

class _MovingPageState extends State<MovingPage> with TickerProviderStateMixin {
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat();
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void dispose() {
    _wobble.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moving')),
      body: AnimatedBuilder(
        animation: Listenable.merge([_wobble, _entrance]),
        builder: (context, _) {
          var t = _wobble.value * 2 * math.pi;
          var slide = (1 - Curves.easeOut.transform(_entrance.value)) * 400;
          return Column(
            children: [
              for (var i = 0; i < 8; i++)
                Transform.translate(
                  offset: Offset(slide, math.sin(t + i * 0.9) * 30),
                  child: ElevatedButton(
                    onPressed: () => tapLog.add('item-$i'),
                    child: Text('Item $i'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class TextPage extends StatefulWidget {
  const TextPage({super.key});

  @override
  State<TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<TextPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Text')),
      body: Column(
        children: [
          TextField(
            key: const ValueKey('field'),
            controller: _controller,
            onChanged: textEvents.add,
          ),
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, value, _) => Text('Value: ${value.text}'),
          ),
        ],
      ),
    );
  }
}

class SpinnerPage extends StatelessWidget {
  const SpinnerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spinner')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class PushedPage extends StatelessWidget {
  const PushedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pushed')),
      body: const Center(child: Text('Pushed page')),
    );
  }
}

class ListPage extends StatelessWidget {
  const ListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('List')),
      body: ListView.builder(
        itemCount: 60,
        itemBuilder: (_, i) =>
            ListTile(title: Text('Row $i'), onTap: () => tapLog.add('row-$i')),
      ),
    );
  }
}

class SpikeDrive {
  SpikeDrive._();

  static final instance = SpikeDrive._();

  final _controller = ft.LiveWidgetController(WidgetsBinding.instance);
  final _drive = drive.Drive();
  var _queue = Future<void>.value();

  void register() {
    developer.registerExtension('ext.spike.call', (method, params) {
      var completer = Completer<developer.ServiceExtensionResponse>();
      _queue = _queue.then((_) async {
        Object? result;
        try {
          result = await _dispatch(params);
        } catch (e, st) {
          result = {'error': '$e', 'stack': '$st'};
        }
        completer.complete(
          developer.ServiceExtensionResponse.result(jsonEncode(result)),
        );
      });
      return completer.future;
    });
  }

  Future<Map<String, Object?>> _dispatch(Map<String, String> params) async {
    switch (params['cmd']) {
      case 'ping':
        return {'ok': true};
      case 'reset':
        tapLog.clear();
        textEvents.clear();
        return {'ok': true};
      case 'home':
        navigatorKey.currentState!.popUntil((r) => r.isFirst);
        return await _settle(2000);
      case 'observe':
        var settle = await _settle(_budget(params));
        return {...settle, ...await _snapshot()};
      case 'tap':
        return await _tap(params);
      case 'scrollToRow':
        return await _scrollToRow(params);
      case 'focusField':
        return await _focusField();
      case 'enterText1':
        return await _enterText1(params['text']!);
      case 'enterText2':
        return await _enterText2(params['text']!);
      case 'screenshot':
        return await _screenshot();
      // The production engine (package:flutterware/drive.dart), as opposed to
      // the hand-rolled mechanism probes above.
      case 'etap':
        return _engineStep(
          await _drive.tap(_engineTarget(params), settle: _settleOf(params)),
        );
      case 'eenter':
        return _engineStep(
          await _drive.enterText(
            _engineTarget(params),
            params['value']!,
            settle: _settleOf(params),
          ),
        );
      case 'escroll':
        return _engineStep(
          await _drive.scrollTo(
            _engineTarget(params),
            settle: _settleOf(params),
          ),
        );
      case 'eback':
        return _engineStep(await _drive.back(settle: _settleOf(params)));
      case 'eobserve':
        return _engineStep(await _drive.observe(settle: _settleOf(params)));
      default:
        return {'error': 'unknown cmd ${params['cmd']}'};
    }
  }

  int _budget(Map<String, String> params) =>
      int.parse(params['settleMs'] ?? '800');

  Duration? _settleOf(Map<String, String> params) {
    var ms = params['settleMs'];
    return ms == null ? null : Duration(milliseconds: int.parse(ms));
  }

  dynamic _engineTarget(Map<String, String> params) {
    if (params['text'] case var text?) return text;
    if (params['key'] case var key?) return ValueKey(key);
    return null;
  }

  Future<Map<String, Object?>> _engineStep(drive.DriveStep step) async {
    return {'step': step.toJson(), ...await _snapshot()};
  }

  ft.FinderBase<Element> _finder(Map<String, String> params) {
    if (params['text'] case var text?) return ft.find.text(text);
    if (params['key'] case var key?) return ft.find.byKey(ValueKey(key));
    throw ArgumentError('no target');
  }

  Future<Map<String, Object?>> _tap(Map<String, String> params) async {
    var finder = _finder(params);
    var elements = finder.evaluate().toList();
    if (elements.length != 1) {
      return {
        'error': 'expected one match, found ${elements.length}',
        'matches': elements.length,
      };
    }
    if (params['checkReach'] == 'true') {
      var renderObject = elements.single.renderObject!;
      var center = _controller.getCenter(finder);
      // Not hitTestOnBinding: its default viewId comes from WidgetController's
      // test-typed view getter, which casts the live PlatformDispatcher to
      // TestPlatformDispatcher and throws.
      var hit = HitTestResult();
      var binding = WidgetsBinding.instance;
      binding.hitTestInView(
        hit,
        center,
        binding.renderViews.first.flutterView.viewId,
      );
      var reached = hit.path.any((entry) => entry.target == renderObject);
      if (!reached) {
        return {'error': 'covered', 'covered': true};
      }
    }
    var sw = Stopwatch()..start();
    await _controller.tap(finder, warnIfMissed: false);
    var tapMs = sw.elapsedMilliseconds;
    var settle = await _settle(_budget(params));
    return {'tapMs': tapMs, ...settle, ...await _snapshot()};
  }

  Future<Map<String, Object?>> _scrollToRow(Map<String, String> params) async {
    var finder = ft.find.text(params['text']!);
    await _controller.scrollUntilVisible(
      finder,
      100,
      scrollable: ft.find.byType(Scrollable),
    );
    var settle = await _settle(_budget(params));
    return {...settle, ...await _snapshot()};
  }

  /// Programmatic focus: what a tap should have achieved, requested directly
  /// on the field's EditableText.
  Future<Map<String, Object?>> _focusField() async {
    var states = _editableStates();
    if (states.length != 1) {
      return {'error': 'EditableText count: ${states.length}'};
    }
    states.single.requestKeyboard();
    var settle = await _settle(800);
    return {
      ...settle,
      'hasFocus': states.single.widget.focusNode.hasFocus,
      ...await _snapshot(),
    };
  }

  List<EditableTextState> _editableStates() {
    return ft.find
        .byType(EditableText)
        .evaluate()
        .map((e) => (e as StatefulElement).state as EditableTextState)
        .toList();
  }

  Future<Map<String, Object?>> _enterText1(String text) async {
    var states = _editableStates();
    var focused = states.where((s) => s.widget.focusNode.hasFocus).toList();
    if (focused.length != 1) {
      return {
        'error': 'focused EditableText count: ${focused.length}',
        'editableCount': states.length,
        ...await _snapshot(),
      };
    }
    focused.single.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    var settle = await _settle(800);
    return {...settle, ...await _snapshot()};
  }

  Future<Map<String, Object?>> _enterText2(String text) async {
    TextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    var settle = await _settle(800);
    return {...settle, ...await _snapshot()};
  }

  Future<Map<String, Object?>> _screenshot() async {
    var sw = Stopwatch()..start();
    var view = WidgetsBinding.instance.renderViews.first;
    var layer = view.debugLayer! as OffsetLayer;
    var dpr = view.flutterView.devicePixelRatio;
    var image = await layer.toImage(
      Offset.zero & (view.size * dpr),
      pixelRatio: 1,
    );
    var bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    var result = {
      'ms': sw.elapsedMilliseconds,
      'width': image.width,
      'height': image.height,
      'png': base64Encode(bytes!.buffer.asUint8List()),
    };
    image.dispose();
    return result;
  }

  /// Bounded wall-clock settle.
  ///
  /// A hidden window disables frames (`framesEnabled` false): `scheduleFrame`
  /// no-ops, so transitions wedge mid-flight and `hasScheduledFrame` reads
  /// false while tickers are still waiting. `scheduleForcedFrame` bypasses
  /// that, and `transientCallbackCount` is the honest "something is animating"
  /// probe when frames are disabled.
  Future<Map<String, Object?>> _settle(int budgetMs) async {
    var binding = WidgetsBinding.instance;
    var sw = Stopwatch()..start();
    var frames = 0;
    var forced = 0;
    bool pending() =>
        binding.hasScheduledFrame || binding.transientCallbackCount > 0;
    if (!binding.framesEnabled) {
      // A dirty element is invisible to hasScheduledFrame while frames are
      // disabled (scheduleFrame no-ops); flush unconditionally once.
      binding.scheduleForcedFrame();
      forced++;
      await Future.any([
        binding.endOfFrame,
        Future<void>.delayed(const Duration(milliseconds: 250)),
      ]);
      frames++;
    }
    while (sw.elapsedMilliseconds < budgetMs) {
      if (!pending()) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!pending()) break;
        continue;
      }
      if (!binding.framesEnabled) {
        binding.scheduleForcedFrame();
        forced++;
      }
      await Future.any([
        binding.endOfFrame,
        Future<void>.delayed(const Duration(milliseconds: 250)),
      ]);
      frames++;
    }
    return {
      'settled': !pending(),
      'frames': frames,
      'forcedFrames': forced,
      'framesEnabled': binding.framesEnabled,
      'elapsedMs': sw.elapsedMilliseconds,
    };
  }

  Future<Map<String, Object?>> _snapshot() async {
    return {
      'tapLog': tapLog.toList(),
      'textEvents': textEvents.toList(),
      'texts': _visibleTexts(),
      'lifecycle': WidgetsBinding.instance.lifecycleState?.toString(),
      'primaryFocus': FocusManager.instance.primaryFocus?.toString(),
    };
  }

  List<String> _visibleTexts() {
    var out = <String>[];
    void visit(Element element) {
      var widget = element.widget;
      if (widget is Text && widget.data != null) out.add(widget.data!);
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return out;
  }
}
