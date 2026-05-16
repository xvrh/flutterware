part of 'widgets.dart';

/// The [RenderObjectWidget] at the very top of the widget tree.
///
/// Unlike every other [RenderObjectWidget], [RootWidget] does not create a
/// fresh render object: its render object **is** the binding's existing
/// [RenderTuiView]. The widget tree is therefore grafted onto a render tree
/// that already exists and is already attached to a [PipelineOwner].
class RootWidget extends RenderObjectWidget {
  /// Wraps [child] beneath the binding's [view].
  const RootWidget(this.view, {super.key, required this.child});

  /// The render view this widget tree drives — supplied by the [TuiBinding].
  final RenderTuiView view;

  /// The application widget tree mounted under the root.
  final Widget child;

  @override
  RootElement createElement() => RootElement(this);

  /// Returns the binding's existing [view] rather than creating a new one.
  @override
  RenderTuiView createRenderObject(BuildContext context) => view;

  /// The view is owned by the binding; there is nothing to push onto it.
  @override
  void updateRenderObject(BuildContext context, RenderTuiView renderObject) {}
}

/// The [Element] at the root of the element tree.
///
/// It has no parent and no ancestor [RenderObjectElement], so attaching its
/// render object is a no-op — the [RenderTuiView] is already the render-tree
/// root. Its single [_child] is the application's element subtree, spliced
/// into [RenderTuiView.child].
class RootElement extends RenderObjectElement {
  RootElement(RootWidget super.widget);

  Element? _child;

  RenderTuiView get _view => (widget as RootWidget).view;

  @override
  void visitChildren(void Function(Element child) visitor) {
    if (_child != null) {
      visitor(_child!);
    }
  }

  @override
  void forgetChild(Element child) {
    assert(child == _child);
    _child = null;
    super.forgetChild(child);
  }

  /// Mounts this element as the tree root under [owner].
  ///
  /// Mirrors Flutter's `RenderObjectToWidgetElement.mount` driven through
  /// `BuildOwner.buildScope`: the caller wraps this in a build scope so the
  /// first build runs inside one.
  void mountAsRoot(BuildOwner owner) {
    assert(_lifecycleState == _ElementLifecycle.initial);
    _owner = owner;
    mount(null, null);
    assert(_lifecycleState == _ElementLifecycle.active);
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    assert(parent == null, 'RootElement is always the tree root.');
    super.mount(parent, newSlot);
    _rebuild();
  }

  @override
  void update(RootWidget newWidget) {
    super.update(newWidget);
    _rebuild();
  }

  @override
  void performRebuild() {
    super.performRebuild();
    _rebuild();
  }

  void _rebuild() {
    _child = updateChild(_child, (widget as RootWidget).child, null);
  }

  /// No ancestor render-object element exists; the view is already the root.
  @override
  void attachRenderObject(Object? newSlot) {
    _slot = newSlot;
  }

  @override
  void detachRenderObject() {
    _slot = null;
  }

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    assert(slot == null);
    _view.child = child as RenderBox;
  }

  @override
  void moveRenderObjectChild(
      RenderObject child, Object? oldSlot, Object? newSlot) {
    assert(false, 'The RootElement never moves its child.');
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    assert(slot == null);
    _view.child = null;
  }
}

/// Drives frames over the stage 3 render pipeline.
///
/// The binding owns the [BuildOwner] (rebuild scheduling), the [PipelineOwner]
/// (layout flushing), and the [RenderTuiView] (the render-tree root). It is
/// the headless heart of the widget layer: [drawFrame] turns the current
/// widget tree into painted cells given only a [Painter], so the whole layer
/// is testable without a real terminal.
class TuiBinding {
  TuiBinding() {
    renderView = RenderTuiView(CellSize.zero);
    renderView.attach(pipelineOwner);
  }

  /// Schedules and orders element rebuilds.
  final BuildOwner buildOwner = BuildOwner();

  /// Flushes render-tree layout.
  final PipelineOwner pipelineOwner = PipelineOwner();

  /// Owns the focus tree and routes key events.
  final FocusManager focusManager = FocusManager();

  /// The render-tree root.
  late final RenderTuiView renderView;

  /// Invoked when a rebuild is scheduled and a frame is needed. The shell
  /// ([runApp]) sets this to a microtask-coalesced frame closure; tests leave
  /// it null and drive [drawFrame] synchronously.
  void Function()? onFrameNeeded;

  RootElement? _rootElement;

  /// The root element, once [attachRootWidget] has run.
  RootElement? get rootElement => _rootElement;

  /// Mounts [rootWidget] as the tree root and runs the first build.
  ///
  /// Wires [BuildOwner.onBuildScheduled] to [onFrameNeeded] so later
  /// `setState`s request frames. The caller still has to run [drawFrame] for
  /// the first painted output.
  void attachRootWidget(Widget rootWidget) {
    assert(_rootElement == null, 'attachRootWidget called twice.');
    var wrapped = _FocusMarker(
      node: focusManager.rootScope,
      hasFocus: true, // the root scope always contains the primary focus
      child: rootWidget,
    );
    var root = RootWidget(renderView, child: wrapped);
    _rootElement = root.createElement();
    renderView.prepareInitialFrame();
    buildOwner.onBuildScheduled = () => onFrameNeeded?.call();
    focusManager.onFocusChange = () => onFrameNeeded?.call();
    buildOwner.buildScope(
        _rootElement!, () => _rootElement!.mountAsRoot(buildOwner));
  }

  /// Reconciles the root against a new application [rootWidget].
  ///
  /// Used on resize to re-wrap the app in a [TerminalApp] carrying the new
  /// size without tearing down the element tree.
  void updateRootWidget(Widget rootWidget) {
    assert(_rootElement != null, 'attachRootWidget must run first.');
    var wrapped = _FocusMarker(
      node: focusManager.rootScope,
      hasFocus: true,
      child: rootWidget,
    );
    var root = RootWidget(renderView, child: wrapped);
    buildOwner.buildScope(_rootElement!, () => _rootElement!.update(root));
  }

  /// Runs one frame: rebuild dirty elements, finalize the tree, then flush
  /// layout and paint into [painter].
  void drawFrame(Painter painter) {
    assert(_rootElement != null, 'attachRootWidget must run first.');
    focusManager.applyFocusChangesIfNeeded();
    buildOwner.buildScope(_rootElement!);
    buildOwner.finalizeTree();
    renderView.compositeFrame(painter);
  }

  /// Updates the terminal size, requesting a re-layout on the next frame.
  void handleResize(CellSize size) {
    renderView.configuration = size;
  }

  /// Tears the binding down: unmounts the whole element tree — running every
  /// `State.dispose()`, so timers, stream subscriptions, and other resources
  /// held by [State] objects are released — and stops scheduling frames.
  ///
  /// Call this once, when [runApp] is exiting. Without it a [State] that
  /// started a `Timer` or stream subscription keeps the Dart event loop alive,
  /// so the process never terminates.
  void dispose() {
    var root = _rootElement;
    if (root == null) {
      return;
    }
    _rootElement = null;
    buildOwner.onBuildScheduled = null;
    buildOwner.unmountAll(root);
  }
}

/// An [InheritedWidget] exposing the terminal context to the whole tree.
///
/// [runApp] wraps the application in a [TerminalApp] so any descendant can
/// reach the raw key stream, the current terminal [size], and an [exit] hook
/// without out-of-band wiring. A widget that reads [size] via [of] rebuilds on
/// resize; the [keys] stream and [exit] closure are stable.
class TerminalApp extends InheritedWidget {
  /// Exposes [keys], [size], and [exit] to [child]'s subtree.
  const TerminalApp({
    super.key,
    required this.keys,
    required this.size,
    required this.exit,
    required super.child,
  });

  /// The raw terminal key-event stream.
  final Stream<KeyEvent> keys;

  /// The current terminal size, in cells.
  final CellSize size;

  /// Requests that the application terminate; [runApp] then returns.
  final void Function() exit;

  /// The nearest enclosing [TerminalApp], registering a dependency so the
  /// caller rebuilds when [size] changes.
  static TerminalApp of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TerminalApp>()!;

  @override
  bool updateShouldNotify(TerminalApp oldWidget) => oldWidget.size != size;
}

/// Runs [app] inside a full-screen terminal session.
///
/// Opens a [Terminal], builds a [TuiBinding], wraps [app] in a [TerminalApp]
/// carrying the key stream / size / exit hook, and drives frames: one initial
/// frame, then a frame per resize, plus microtask-coalesced frames whenever a
/// `setState` schedules a rebuild. Returns when a descendant calls
/// `TerminalApp.of(context).exit()`.
Future<void> runApp(Widget app) async {
  await Terminal.run((terminal) async {
    var binding = TuiBinding();
    var exit = Completer<void>();

    TerminalApp wrap() => TerminalApp(
          keys: terminal.keys,
          size: CellSize(terminal.rows, terminal.cols),
          exit: () {
            if (!exit.isCompleted) {
              exit.complete();
            }
          },
          child: app,
        );

    // Set once the app is exiting: frames must stop before the terminal is
    // restored, otherwise late draws (from a pending microtask or a State's
    // still-firing Timer) would scribble onto the recovered console.
    var stopped = false;

    void frame() {
      if (stopped) {
        return;
      }
      terminal.draw((buffer) {
        binding.handleResize(CellSize(buffer.rows, buffer.cols));
        binding.drawFrame(Painter(buffer));
      });
    }

    var frameScheduled = false;
    void scheduleFrame() {
      if (stopped || frameScheduled) {
        return;
      }
      frameScheduled = true;
      scheduleMicrotask(() {
        frameScheduled = false;
        frame();
      });
    }

    binding.attachRootWidget(wrap());
    binding.onFrameNeeded = scheduleFrame;
    var keySub = terminal.keys.listen((event) {
      if (stopped) return;
      binding.focusManager.handleKeyEvent(event);
    });
    frame();

    var resizeSub = terminal.resizes.listen((_) {
      binding.updateRootWidget(wrap());
      frame();
    });

    try {
      await exit.future;
    } finally {
      // Stop frames, then tear the tree down so every State.dispose() runs —
      // releasing Timers and stream subscriptions that would otherwise keep
      // the event loop alive and the process from exiting.
      stopped = true;
      binding.dispose();
      await resizeSub.cancel();
      await keySub.cancel();
    }
  });
}
