// The app's end of the scene editor: one widget that draws whatever the
// editor sends, through whatever view it asks for, and reports back what the
// layout measured.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'core/json.dart';
import 'core/model.dart';
import 'core/values.dart';
import 'view.dart';

/// The scene editor's canvas, hosted by the app whose theme and widgets the
/// scenes use.
///
/// Declare a `@Preview` entry named `sceneCanvasHost` that mounts this under
/// the app's own theme, and the editor composites it: it sends the scene as
/// *data* over a VM-service extension, this draws it with [SceneView], and
/// answers with what the layout measured — which is where the editor's
/// selection rectangles and drag targets come from.
///
/// The editor also sends its **view** — how the canvas is scaled and panned —
/// and this draws the artboard through it. The window this renders into is
/// the size of the editor's canvas pane, so a zoomed-in artboard is
/// rasterised at the zoom, crisp at any magnification, and the picture never
/// costs more than the pane's pixels.
class SceneCanvasHost extends StatefulWidget {
  const SceneCanvasHost({
    super.key,
    this.externals = const {},
    this.ground = const Color(0x00000000),
  });

  /// Everything a scene may name, by entry — the app's own widgets.
  final Map<String, SceneExternalBuilder> externals;

  /// What shows around the artboard. Transparent by default, so the editor's
  /// own ground shows through.
  final Color ground;

  @override
  State<SceneCanvasHost> createState() => _SceneCanvasHostState();
}

class _SceneCanvasHostState extends State<SceneCanvasHost> {
  /// The scene the editor sent, as a live document — the same model the
  /// editor holds, so what draws here is what it authored.
  SceneDocument? _scene;
  var _selected = <String>{};
  var _rects = <String, SceneRect>{};

  /// Artboard to window, as the editor's canvas has it: a scale and a pan.
  var _view = Matrix4.identity();

  /// The box the artboard is drawn in, as the editor's canvas decided it.
  ///
  /// A root that fills has no size of its own — that is the point of it —
  /// so somebody has to say how big the page being authored is. The editor
  /// does, and sends it; without one there is nothing to lay out against
  /// and Flutter says so with an infinite-constraint error.
  Size? _artboard;

  /// Once per isolate: a re-mounted widget must not re-register.
  static var _registered = false;
  static _SceneCanvasHostState? _instance;

  @override
  void initState() {
    super.initState();
    if (!_registered) {
      _registered = true;
      dev.registerExtension('ext.fw.scene.apply', _applyStatic);
    }
    _instance = this;
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
    return instance._apply(params);
  }

  /// One push from the editor: the scene, the view, or both.
  Future<dev.ServiceExtensionResponse> _apply(
    Map<String, String> params,
  ) async {
    var frame = Stopwatch()..start();
    var window = View.of(context);
    setState(() {
      if (params['scene'] case var raw?) {
        var decoded = jsonDecode(raw) as Map<String, dynamic>;
        // The wire is a picture: values already composed with the motion's
        // fx, so the host draws what it is given rather than evaluating
        // anything.
        _scene = sceneFromWire(decoded['root'] as Map<String, dynamic>);
        _selected = switch (decoded['selected']) {
          List names => {for (var n in names) '$n'},
          String name => {name},
          _ => const {},
        };
      }
      if (params['artboard'] case var raw?) {
        if (jsonDecode(raw) case [num w, num h]) {
          _artboard = Size(w.toDouble(), h.toDouble());
        }
      }
      if (params['view'] case var raw?) {
        if (jsonDecode(raw) case [num scale, num tx, num ty]) {
          _view = Matrix4.identity()
            ..translateByDouble(tx.toDouble(), ty.toDouble(), 0, 1)
            ..scaleByDouble(scale.toDouble(), scale.toDouble(), 1, 1);
        }
      }
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
        // What this end drew through and into — the editor's status line
        // shows it, which is how a host that is not this one is told apart.
        'view': [_view.storage[0], _view.storage[12], _view.storage[13]],
        'window': [
          window.physicalSize.width,
          window.physicalSize.height,
          window.devicePixelRatio,
        ],
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    var scene = _scene;
    return ColoredBox(
      color: widget.ground,
      child: scene == null
          ? const SizedBox.expand()
          // The artboard keeps its own size whatever the window's — an
          // OverflowBox, since a zoomed artboard is larger than the pane —
          // and is drawn through the editor's view. No filter quality: the
          // transform must rasterise at its scale, not sample a 1× picture.
          : Transform(
              transform: _view,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                // The window until the editor says otherwise: the first
                // push can land before the canvas has laid out and sent an
                // artboard, and a root that fills would meet the
                // OverflowBox's infinity and throw.
                child: SizedBox(
                  width: (_artboard ?? MediaQuery.sizeOf(context)).width,
                  height: (_artboard ?? MediaQuery.sizeOf(context)).height,
                  child: SceneView(
                    scene,
                    externals: widget.externals,
                    selected: _selected,
                    onMeasured: (rects) => _rects = rects,
                  ),
                ),
              ),
            ),
    );
  }
}
