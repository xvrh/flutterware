// Disposable spike: the scene rendered where user code lives.
//
// This app is what "the whole canvas rendered by the preview system, without
// compile in the loop" means concretely: it is compiled against this package
// once, then receives the editor's scene model as *data* over a VM-service
// extension, renders it with the app's own theme, and reports measured rects
// back. External widgets are native and live — a spinner spins, a button
// takes the theme — because nothing is rasterized across a boundary.
//
// The editor half is the canvas toy's remote mode (app/lib/canvas_toy/).
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutterware_example/shop/shop_app.dart';

void main() {
  runApp(const SceneHostApp());
}

/// Everything the editor may inject, by name — the hand-written stand-in for
/// the generated registration bridge. Mockups (a [Drink]) live here, on this
/// side of the wire, and never serialize.
final _registry = <String, Widget Function(Map<String, Object?> args)>{
  'DrinkBadge': (a) =>
      DrinkBadge(drinks[1], size: (a['size'] as num?)?.toDouble() ?? 56),
  'Spinner': (a) => SizedBox(
    width: (a['size'] as num?)?.toDouble() ?? 36,
    height: (a['size'] as num?)?.toDouble() ?? 36,
    child: const CircularProgressIndicator(strokeWidth: 3),
  ),
  'OrderButton': (a) => FilledButton(
    onPressed: () {},
    child: Text('${a['label'] ?? 'Order now'}'),
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
  Map<String, dynamic>? _scene;
  String? _selected;
  final _artboardKey = GlobalKey();
  final _keys = <String, GlobalKey>{};

  GlobalKey _key(String name) => _keys.putIfAbsent(name, GlobalKey.new);

  /// Once per isolate: a re-mounted widget must not re-register.
  static var _registered = false;

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

  static _SceneHostAppState? _instance;

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
      _scene = decoded['root'] as Map<String, dynamic>?;
      _selected = decoded['selected'] as String?;
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
        'rects': _sweep(),
        'frameMs': frame.elapsedMicroseconds / 1000,
      }),
    );
  }

  Map<String, List<double>> _sweep() {
    var artboard =
        _artboardKey.currentContext?.findRenderObject() as RenderBox?;
    if (artboard == null) return {};
    var rects = <String, List<double>>{};
    void visit(Map<String, dynamic> node) {
      var box =
          _key('${node['name']}').currentContext?.findRenderObject()
              as RenderBox?;
      if (box != null && box.hasSize) {
        var topLeft = box.localToGlobal(Offset.zero, ancestor: artboard);
        rects['${node['name']}'] = [
          topLeft.dx,
          topLeft.dy,
          box.size.width,
          box.size.height,
        ];
      }
      for (var child in (node['children'] as List? ?? const [])) {
        visit(child as Map<String, dynamic>);
      }
    }

    var scene = _scene;
    if (scene != null) visit(scene);
    return rects;
  }

  @override
  Widget build(BuildContext context) {
    var artboard = _scene == null
        ? null
        : SizedBox(
            key: _artboardKey,
            width: (_scene!['w'] as num?)?.toDouble() ?? 1024,
            height: (_scene!['h'] as num?)?.toDouble() ?? 500,
            child: _node(_scene!, root: true),
          );
    if (widget.bare) {
      return MaterialApp(
        title: 'Scene host',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF8C5A3C)),
        // Material, not ColoredBox: without a Material ancestor every Text
        // falls back to the debug style — the yellow double underline.
        home: Material(
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
      theme: ThemeData(colorSchemeSeed: const Color(0xFF8C5A3C)),
      home: Scaffold(
        backgroundColor: const Color(0xFF26282C),
        body: Center(
          child: _scene == null
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

  Widget _node(Map<String, dynamic> n, {bool root = false}) {
    var name = '${n['name']}';
    Widget? inner;
    switch (n['kind']) {
      case 'text':
        inner = Text(
          '${n['text']}',
          style: TextStyle(
            fontSize: (n['fontSize'] as num?)?.toDouble() ?? 16,
            fontWeight: FontWeight.values[(n['weight'] as num?)?.toInt() ?? 3],
            color: _color(n['color']) ?? const Color(0xFF1A1A1A),
            height: 1.15,
          ),
        );
      case 'shape':
        inner = null;
      case 'ext':
        var build = _registry['${n['entry']}'];
        var args = (n['args'] as Map?)?.cast<String, Object?>() ?? const {};
        inner = build == null
            ? Text(
                'unknown: ${n['entry']}',
                style: const TextStyle(color: Colors.red),
              )
            : build(args);
      case 'frame' || null:
        var children = <Widget>[
          for (var c in (n['children'] as List? ?? const []))
            _child(n, c as Map<String, dynamic>),
        ];
        inner = switch ('${n['layout']}') {
          'row' => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: _cross(n),
            spacing: (n['gap'] as num?)?.toDouble() ?? 0,
            children: children,
          ),
          'column' => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: _cross(n),
            spacing: (n['gap'] as num?)?.toDouble() ?? 0,
            children: children,
          ),
          _ => Stack(clipBehavior: Clip.none, children: children),
        };
    }

    var fill = _color(n['fill']);
    var corner = (n['corner'] as num?)?.toDouble() ?? 0;
    var circle = n['kind'] == 'shape' && n['circle'] == true;
    var padding = (n['padding'] as num?)?.toDouble() ?? 0;
    var selected = !root && name == _selected;
    Widget result = Container(
      key: _key(name),
      width: (n['w'] as num?)?.toDouble(),
      height: (n['h'] as num?)?.toDouble(),
      padding: padding > 0
          ? EdgeInsets.symmetric(horizontal: padding, vertical: padding * 0.6)
          : null,
      foregroundDecoration: selected
          ? BoxDecoration(
              border: Border.all(color: const Color(0xFF4A64D0), width: 1.5),
            )
          : null,
      decoration: fill != null || corner > 0
          ? BoxDecoration(
              color: fill,
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: circle || corner == 0
                  ? null
                  : BorderRadius.circular(corner),
            )
          : null,
      child: inner,
    );
    var opacity = (n['opacity'] as num?)?.toDouble() ?? 1;
    if (opacity < 1) result = Opacity(opacity: opacity, child: result);
    return result;
  }

  Widget _child(Map<String, dynamic> parent, Map<String, dynamic> child) {
    var view = _node(child);
    if ('${parent['layout']}' == 'absolute') {
      return Positioned(
        left: (child['x'] as num?)?.toDouble() ?? 0,
        top: (child['y'] as num?)?.toDouble() ?? 0,
        child: view,
      );
    }
    return view;
  }

  CrossAxisAlignment _cross(Map<String, dynamic> n) =>
      CrossAxisAlignment.values[(n['crossAlign'] as num?)?.toInt() ?? 2];

  Color? _color(Object? argb) => argb is num ? Color(argb.toInt()) : null;
}
