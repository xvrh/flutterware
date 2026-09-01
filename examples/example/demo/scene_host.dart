// The scene rendered where the app lives.
//
// This is what "the guest is the only renderer" means concretely: the editor
// sends the scene as *data* over a VM-service extension, and this app draws it
// with `SceneView` — its own theme, its own widgets, its own fonts — then
// reports back what the layout measured, which is where the editor's selection
// rectangles and drag targets come from.
//
// The app's part is small on purpose: register the widgets a scene may name,
// and mount the view. Everything else is flutterware's.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_example/shop/shop_app.dart';

void main() {
  runApp(const SceneHostApp());
}

/// Everything a scene may name, by entry — the app's own widgets, with their
/// mockup data on this side of the wire where it belongs. A [Drink] never
/// serializes; the scene only knows the name `DrinkBadge`.
final _externals = <String, SceneExternalBuilder>{
  'DrinkBadge': (context, args) =>
      DrinkBadge(drinks[1], size: (args['size'] as num?)?.toDouble() ?? 56),
  'Spinner': (context, args) => SizedBox(
    width: (args['size'] as num?)?.toDouble() ?? 36,
    height: (args['size'] as num?)?.toDouble() ?? 36,
    child: const CircularProgressIndicator(strokeWidth: 3),
  ),
  'OrderButton': (context, args) => FilledButton(
    onPressed: () {},
    child: Text('${args['label'] ?? 'Order now'}'),
  ),
};

class SceneHostApp extends StatefulWidget {
  const SceneHostApp({super.key, this.bare = false});

  /// Bare: the artboard alone at the window's origin, 1:1 — for a host whose
  /// window IS the canvas (the studio's embedder texture), where the editor
  /// maps its coordinates straight onto the guest's. No announcement either:
  /// the mounting panel owns the pipe.
  final bool bare;

  @override
  State<SceneHostApp> createState() => _SceneHostAppState();
}

class _SceneHostAppState extends State<SceneHostApp> {
  /// The scene the editor sent, as a live document — the same model the
  /// editor holds, so what draws here is what it authored.
  SceneDocument? _scene;
  var _selected = <String>{};
  var _rects = <String, SceneRect>{};

  /// Once per isolate: a re-mounted widget must not re-register.
  static var _registered = false;
  static _SceneHostAppState? _instance;

  @override
  void initState() {
    super.initState();
    if (!_registered) {
      _registered = true;
      dev.registerExtension('ext.fw.scene.apply', _applyStatic);
    }
    _instance = this;
    if (!widget.bare) unawaited(_announce());
  }

  static Future<dev.ServiceExtensionResponse> _applyStatic(
    String method,
    Map<String, String> params,
  ) async {
    var instance = _instance;
    if (instance == null) {
      return dev.ServiceExtensionResponse.result(
        jsonEncode({'error': 'no scene host mounted'}),
      );
    }
    return instance._apply(method, params);
  }

  /// Writes this app's VM-service websocket URI where the editor polls for
  /// it, so connecting needs no copy-paste.
  Future<void> _announce() async {
    var info = await dev.Service.getInfo();
    var http = info.serverUri;
    if (http == null) return;
    var ws = 'ws${http.toString().substring(4)}ws';
    try {
      var file = File(
        '${Platform.environment['HOME']}/.flutterware/scene_hosts/$pid.txt',
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(ws);
    } catch (_) {
      // A sandboxed guest (a simulator) cannot reach the editor's home
      // directory; something outside drops the announcement for it.
    }
  }

  Future<dev.ServiceExtensionResponse> _apply(
    String method,
    Map<String, String> params,
  ) async {
    var frame = Stopwatch()..start();
    setState(() {
      var decoded = jsonDecode(params['scene'] ?? '{}') as Map<String, dynamic>;
      // The wire is a picture: values already composed with the motion's fx,
      // so the host draws what it is given rather than evaluating anything.
      _scene = sceneFromWire(decoded['root'] as Map<String, dynamic>);
      _selected = switch (decoded['selected']) {
        List names => {for (var n in names) '$n'},
        String name => {name},
        _ => const {},
      };
    });
    // A hidden window pumps no ordinary frames; a forced frame paints even
    // when the compositor thinks nothing is visible — the drive layer's trick.
    SchedulerBinding.instance.scheduleForcedFrame();
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 500),
      );
    } on TimeoutException {
      return dev.ServiceExtensionResponse.result(
        jsonEncode({'error': 'no frame within 500ms (window hidden?)'}),
      );
    }
    return dev.ServiceExtensionResponse.result(
      jsonEncode({
        'rects': {
          for (var e in _rects.entries)
            e.key: [e.value.left, e.value.top, e.value.width, e.value.height],
        },
        'frameMs': frame.elapsedMicroseconds / 1000,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    var scene = _scene;
    var artboard = scene == null
        ? null
        : SceneView(
            scene,
            externals: _externals,
            selected: _selected,
            onMeasured: (rects) => _rects = rects,
          );
    var theme = ThemeData(colorSchemeSeed: const Color(0xFF8C5A3C));
    if (widget.bare) {
      return MaterialApp(
        title: 'Scene host',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: ColoredBox(
          color: const Color(0xFF26282C),
          child: artboard == null
              ? const SizedBox()
              : Align(alignment: Alignment.topLeft, child: artboard),
        ),
      );
    }
    return MaterialApp(
      title: 'Scene host',
      debugShowCheckedModeBanner: false,
      // The app's own look — what the editor canvas inherits by construction.
      theme: theme,
      home: Scaffold(
        backgroundColor: const Color(0xFF26282C),
        body: Center(
          child: scene == null
              ? const Text(
                  'scene host — waiting for the editor',
                  style: TextStyle(color: Colors.white54),
                )
              // Scale-to-fit so a small guest (a phone) shows the whole
              // artboard. Rects stay in artboard coordinates: the sweep
              // measures against the artboard box, inside the scaling.
              : FittedBox(fit: BoxFit.scaleDown, child: artboard),
        ),
      ),
    );
  }
}
