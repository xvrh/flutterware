import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Mounts a widget in its own build/layout/paint pipeline, attached to no
/// screen — the capture's way to render a widget that is not (and never
/// will be) part of the running app's tree.
///
/// The widget gets a minimal environment: tight constraints at [size], a
/// [MediaQuery] and left-to-right [Directionality]. Anything more — theme,
/// localizations — is the widget's own wrapping to bring.
///
/// One synchronous pass builds, lays out and paints. Content that arrives
/// asynchronously (a network image, a deferred font) is not waited for:
/// call [pump] after the wait the caller owns.
class OffscreenWidget {
  OffscreenWidget._(
    this._buildOwner,
    this._pipelineOwner,
    this._renderView,
    this._element,
    this.boundary,
  );

  static OffscreenWidget mount(Widget widget, {required Size size}) {
    var binding = WidgetsFlutterBinding.ensureInitialized();
    var view = binding.platformDispatcher.implicitView;
    if (view == null) {
      throw StateError('offscreen mounting needs an implicit FlutterView');
    }
    var boundary = RenderRepaintBoundary();
    var renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(size),
        physicalConstraints: BoxConstraints.tight(size),
      ),
      child: boundary,
    );
    var pipelineOwner = PipelineOwner();
    var buildOwner = BuildOwner(focusManager: FocusManager());
    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();
    // The initial build happens inside attachToRenderTree itself, so the
    // error hook has to be up before it — not only around pump().
    var mountErrors = <FlutterErrorDetails>[];
    var previousOnError = FlutterError.onError;
    FlutterError.onError = mountErrors.add;
    RenderObjectToWidgetElement<RenderBox> element;
    try {
      element = RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: widget,
          ),
        ),
      ).attachToRenderTree(buildOwner);
    } finally {
      FlutterError.onError = previousOnError;
    }
    var mounted = OffscreenWidget._(
      buildOwner,
      pipelineOwner,
      renderView,
      element,
      boundary,
    );
    mounted.flutterErrors.addAll(mountErrors);
    mounted.pump();
    return mounted;
  }

  final BuildOwner _buildOwner;
  final PipelineOwner _pipelineOwner;
  final RenderView _renderView;
  final RenderObjectToWidgetElement<RenderBox> _element;

  /// The laid-out root, ready for the capture (or [RenderRepaintBoundary]'s
  /// own toImage).
  final RenderRepaintBoundary boundary;

  /// What the framework caught while building, laying out or painting: the
  /// engine substitutes its error box and carries on, so without this list a
  /// throwing builder would render as a clean-looking success.
  final flutterErrors = <FlutterErrorDetails>[];

  /// One build + layout + paint pass over whatever is dirty.
  void pump() {
    var previousOnError = FlutterError.onError;
    FlutterError.onError = flutterErrors.add;
    try {
      _buildOwner.buildScope(_element);
      _buildOwner.finalizeTree();
      _pipelineOwner.flushLayout();
      _pipelineOwner.flushCompositingBits();
      _pipelineOwner.flushPaint();
    } finally {
      FlutterError.onError = previousOnError;
    }
  }

  /// Unmounts the tree so every State disposes, then releases the pipeline.
  void dispose() {
    // The childless adapter only marks the root dirty; the buildScope is
    // what actually swaps the child out and deactivates the subtree, and
    // finalizeTree is what unmounts it. Without the drain, nothing ever
    // unmounted and a resident guest leaked one whole tree per render.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(_buildOwner, _element);
    _buildOwner.buildScope(_element);
    _buildOwner.finalizeTree();
    _pipelineOwner.rootNode = null;
    _renderView.child = null;
    boundary.dispose();
    _renderView.dispose();
    _pipelineOwner.dispose();
    _buildOwner.focusManager.dispose();
  }
}
