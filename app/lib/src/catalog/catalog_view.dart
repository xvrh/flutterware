import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:device_frame/device_frame.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutterware/ui_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../address/address_scope.dart';
import '../embedder/embedded_engine.dart';
import '../embedder/protocol.dart';
import '../ui/design/design.dart';
import '../utils/image_clipboard.dart';
import 'catalog_params.dart';
import 'catalog_devices.dart';
import 'catalog_entry.dart';
import 'catalog_session.dart';
import 'catalog_tree.dart';
import 'inspect_panel.dart';

/// The namespace covering the canvas and the panel below it — see where it is
/// installed in [_CatalogViewState._buildBody] for why it stops there.
///
/// Named once because both sides of that boundary have to agree: what is
/// written under it is `inspect.*`, and a reader on the other side has to say
/// so. Two of them did not, in opposite directions — see [_deviceOf] and
/// [_croppedNode].
const _inspectNamespace = 'inspect';

/// The catalog loop: entries on the left, the live guest on the right.
/// Selecting an entry hot-reloads the running guest rather than restarting it.
///
/// Mounted by the `flutterware.ui_catalog` plugin as its panel, and by
/// `main_catalog_dev.dart` for working on the loop itself.
///
/// It **renders** a [CatalogSession]; it does not own one. The owner outlives
/// the widget, which is what lets a cold compile keep running — and keep
/// reporting into the sidebar — while you are looking at another plugin.
class CatalogView extends StatefulWidget {
  const CatalogView({super.key, required this.session});

  final CatalogSession session;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  /// How often the panel asks whether entries have appeared or disappeared.
  ///
  /// Cheap enough not to think about — the daemon compares a listing of the
  /// roots, a few milliseconds, and answers nothing at all when it matches.
  /// It exists because the other triggers are all things *you* do, and files
  /// arrive without you: an agent writing a demo while you watch the panel
  /// would otherwise go unnoticed until you touched something.
  static const _pollInterval = Duration(seconds: 3);

  /// When the panel looks again after coming back to the window.
  ///
  /// An editor that saves as it loses focus is racing the window that gains it:
  /// IntelliJ writes the file at about the moment this panel sweeps for edits,
  /// and often a beat after — so a single check on resume misses the very edit
  /// you switched over to look at, and you have to reload by hand or save
  /// again. Looking twice more costs nothing when nothing moved, which is the
  /// same property the whole focus trigger rests on.
  static const _afterFocus = [
    Duration(milliseconds: 200),
    Duration(milliseconds: 600),
    Duration(milliseconds: 1500),
  ];

  /// The node the pointer is over, drawn on the preview and nowhere else.
  ///
  /// A notifier rather than session state or a `setState`, and the granularity
  /// is the reason: this changes on every mouse move across a tree row, and
  /// rebuilding the entry list and the top bar sixty times a second to move one
  /// rectangle would be absurd. Only the overlay listens.
  final _highlight = ValueNotifier<String?>(null);

  /// Whether a click on the preview picks a widget instead of reaching the demo.
  final _picking = ValueNotifier<bool>(false);

  final FocusNode _focusNode = FocusNode();
  Timer? _poll;
  final _settling = <Timer>[];
  (int, int, double, EdgeInsets)? _lastReported;
  late final AppLifecycleListener _lifecycle;

  CatalogSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    // Coming back to the window after editing elsewhere. `onResume` is
    // documented as "a view in the application gains input focus", which on
    // desktop is exactly the alt-tab back from the editor.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _reloadAfterFocus();
        _startPolling();
      },
      // Nothing arrives on screen while the window is behind another one, and
      // coming back runs a full check anyway.
      onInactive: _stopPolling,
    );
    _startPolling();

    // The one thing on screen whose rect has to keep up with a demo that is
    // moving. Everything else the tree says goes slightly stale and looks
    // slightly wrong; a rectangle drawn over the wrong place looks *broken*,
    // and it is the reason the watch exists at all.
    _highlight.addListener(_trackHighlighted);

    // And coming back to the *panel*: the shell rebuilds it from scratch when
    // you switch plugins, so a mount is the other half of the same signal.
    // After the frame, because this runs during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadIfChanged());
  }

  void _trackHighlighted() => _session.watchedNode = _highlight.value;

  @override
  void dispose() {
    _stopPolling();
    _stopSettling();
    _lifecycle.dispose();
    _focusNode.dispose();
    _highlight
      ..removeListener(_trackHighlighted)
      ..dispose();
    _picking.dispose();
    super.dispose();
  }

  /// Checks now, then again over the next second and a half — see [_afterFocus].
  void _reloadAfterFocus() {
    _reloadIfChanged();
    _stopSettling();
    _settling.addAll([
      for (var delay in _afterFocus) Timer(delay, _reloadIfChanged),
    ]);
  }

  void _stopSettling() {
    for (var timer in _settling) {
      timer.cancel();
    }
    _settling.clear();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) {
      _session.refresh();
      // Errors are not a fact about the build, they are a stream. A read fired
      // once after a reload gets a 300ms window, and a cold start can spend
      // seconds getting to its first frame — so the answer was "waiting for
      // the entry to render…" for ever, on a demo that was visibly painting
      // Flutter's overflow stripes. Worse, an error thrown from `paint`
      // arrives *whenever it is painted*, which can be long after any build
      // this could have hung a read on.
      //
      // Cheap: a handful of deduped errors over a connection that is already
      // open, and only while somebody has the panel on screen.
      unawaited(_session.readErrors());
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The guest is told what the address asks of the shell's axes, from here
    // rather than from the panel above: this widget is what renders a session,
    // and the standalone harness mounts it without a panel. One place, so the
    // two cannot drift.
    _session.axisSelections = AddressScope.params(context, namespace: 'axis');
    _session.knobSelections = AddressScope.params(context, namespace: 'knob');
  }

  /// Cheap by construction: the daemon answers `unchanged` when nothing on disk
  /// moved, so this fires as often as it likes without touching the guest.
  void _reloadIfChanged() {
    if (mounted) unawaited(_session.reloadIfChanged());
  }

  void _maybeResize(
    EmbeddedEngine engine,
    Size size,
    double dpr, {
    EdgeInsets safeAreas = EdgeInsets.zero,
  }) {
    var width = (size.width * dpr).round();
    var height = (size.height * dpr).round();
    if (width < 1 || height < 1) return;
    // Keyed on the ratio and the safe areas as well as the size: two devices
    // can share a logical size at different ratios or different notches, and
    // comparing only the size would leave the guest rendering as the old one.
    var next = (width, height, dpr, safeAreas);
    if (next == _lastReported) return;
    _lastReported = next;
    // Physical pixels, like the size — the guest turns them back into logical
    // padding on the other side.
    engine.resize(width, height, dpr, insets: safeAreas * dpr);
  }

  /// Whether a key belongs to the app rather than to the guest.
  ///
  /// The canvas forwards everything else and reports it handled, so without
  /// this no shortcut survives a click on the demo — not the panel's own
  /// reload, and not the shell's. Command chords are the app's; a demo that
  /// wants one is rarer than a user who wants their window back.
  bool _isAppChord(KeyEvent event) =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): _reload,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _reload,
        // Shifted, because plain ⌘C belongs to whatever text has the selection.
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true):
            _copyPreview,
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ): _copyPreview,
      },
      child: _buildBody(context),
    );
  }

  /// The same thing the top bar's copy button does — see [_capturePreview] for
  /// why the two share their capture rather than each having one.
  void _copyPreview() {
    if (!ImageClipboard.isSupported) return;
    unawaited(() async {
      try {
        var png = await _capturePreview(context, _session);
        if (png != null) await ImageClipboard.setPng(png);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not copy the preview: $e')),
          );
        }
      }
    }());
  }

  void _reload() {
    if (_session.phase == CatalogSessionPhase.ready) {
      unawaited(_session.reload());
    }
  }

  Widget _buildBody(BuildContext context) {
    return Material(
      child: AnimatedBuilder(
        // All three, named here rather than relied on being forwarded. The
        // session does forward them, but it wires that up in its constructor —
        // which a hot reload never re-runs, so an existing session ends up with
        // a staging nobody listens to and a top bar that only catches up when
        // something else happens to rebuild it.
        animation: Listenable.merge([
          _session,
          _session.browsing,
          _session.staging,
        ]),
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_session.browsing.listVisible)
                SizedBox(width: 260, child: _EntryList(session: _session))
              else
                _ShowListStrip(browsing: _session.browsing),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(session: _session),
                    const Divider(height: 1),
                    // Wrapped so the panel can be told how much room there is,
                    // and wrapped *here* rather than higher so the number is
                    // the canvas and the panel and nothing else — a reserve
                    // that had to guess at the bars above and below would be
                    // wrong the moment either changed height.
                    //
                    // It cannot measure this itself: a `Column` hands a
                    // non-flex child an unbounded main axis, so a
                    // `LayoutBuilder` down there reads infinity and clamps
                    // against nothing.
                    Expanded(
                      // `inspect` covers the canvas and the panel and
                      // nothing else, because those are its two writers: the
                      // tree writes a selection when you click a row, the
                      // picker writes one when you click the *preview*.
                      // Wrapped any higher and it would swallow the top
                      // bar's writes too — a device picked from up there
                      // would land as `inspect.device`, which is nobody's
                      // parameter.
                      //
                      // Which cuts both ways, and the read is the half that
                      // is easy to miss: `device` is the top bar's,
                      // un-namespaced, so it is resolved *here* — above the
                      // scope — and handed down. Read from inside, it asked
                      // for `inspect.device` and got nothing, and the canvas
                      // framed every entry as the panel however the picker
                      // was set.
                      child: Builder(
                        builder: (context) {
                          var device = _deviceOf(context, _session);
                          return AddressScope(
                            namespace: _inspectNamespace,
                            child: LayoutBuilder(
                              builder: (context, constraints) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _buildCanvas(context, device),
                                  ),
                                  // Always mounted, unlike the knob drawer it
                                  // replaced: that one was absent rather than
                                  // empty when an entry declared no knobs, so
                                  // anybody who had not happened to open a demo
                                  // with knobs never learned the feature
                                  // existed. The tab is there now and says so.
                                  InspectPanel(
                                    session: _session,
                                    available: constraints.maxHeight,
                                    highlight: _highlight,
                                    picking: _picking,
                                    controls: (context) =>
                                        _KnobPanel(session: _session),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    _StatusBar(session: _session, onReload: _reload),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCanvas(BuildContext context, CatalogDevice? device) {
    switch (_session.phase) {
      case CatalogSessionPhase.starting:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              const CircularProgressIndicator(),
              Text(
                'Building the guest and compiling the first entry… '
                '${_session.busyFor.inSeconds}s',
              ),
            ],
          ),
        );
      case CatalogSessionPhase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: SelectableText(
                _session.errorMessage ?? 'unknown error',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ),
        );
      case CatalogSessionPhase.ready:
        // The error goes where the widget would have been. The guest is still
        // rendering the last entry that loaded, and showing that under a
        // selection it does not belong to is how you end up wondering why your
        // edit did nothing.
        if (_session.selectedError case var error?) {
          return _CompileError(
            entry: _session.selected!,
            error: error,
            onRetry: _session.busyWith == null ? _reload : null,
          );
        }
        return _buildTexture(context, _session.engine!, device);
    }
  }

  /// The guest, sized either to the panel or to a device.
  ///
  /// A device is not a frame drawn around the same picture: the guest's window
  /// *is* the device screen, at the device's own pixel ratio, so what the demo
  /// reads from `MediaQuery` is what it would read on the phone. Rendering at
  /// the device's resolution and scaling the result down is also the only way
  /// the texture stays sharp.
  Widget _buildTexture(
    BuildContext context,
    EmbeddedEngine engine,
    CatalogDevice? device,
  ) {
    if (device == null) {
      var dpr = MediaQuery.of(context).devicePixelRatio;
      return LayoutBuilder(
        builder: (context, constraints) {
          _resizeAfterFrame(engine, constraints.biggest, dpr);
          return _guestInput(engine, dpr, const SizedBox.expand());
        },
      );
    }

    var screen = Size(device.width, device.height);
    _resizeAfterFrame(
      engine,
      screen,
      device.pixelRatio,
      // What the frame draws around the screen, told to the thing rendering
      // inside it — otherwise the notch is decoration and an AppBar sits under
      // it.
      safeAreas: EdgeInsets.fromLTRB(
        device.insetLeft,
        device.insetTop,
        device.insetRight,
        device.insetBottom,
      ),
    );
    // The one thing `device_frame` is here for, and the only place it is
    // touched: the silhouette. Everything above came from our own measurements.
    // Null for a desktop size, which gets none.
    var chrome = deviceFrameFor(device);
    var guest = _guestInput(
      engine,
      device.pixelRatio,
      SizedBox.fromSize(size: screen),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FwSpacing.xl),
        // scaleDown, never up: a texture rendered at the device's resolution
        // and then enlarged is just a blurrier phone.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: chrome == null || !_session.staging.frameVisible
              ? SizedBox.fromSize(size: screen, child: guest)
              : DeviceFrame(device: chrome, screen: guest),
        ),
      ),
    );
  }

  void _resizeAfterFrame(
    EmbeddedEngine engine,
    Size logical,
    double dpr, {
    EdgeInsets safeAreas = EdgeInsets.zero,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeResize(engine, logical, dpr, safeAreas: safeAreas);
    });
  }

  /// Picks the widget under a point instead of letting the demo have the click.
  ///
  /// Two hit tests, and the split is deliberate. The highlight has already
  /// followed the mouse here from [InspectTree.nodeAtPoint], which knows only
  /// rectangles; the commit asks the guest, which runs the framework's own
  /// hit test and therefore knows about transforms, clips and `IgnorePointer`.
  /// So the box you were shown is a guess and the node you get is not — and
  /// when they disagree, the tree jumps to the right one.
  Future<void> _pick(BuildContext context, Offset point) async {
    var handle = AddressScope.write(context);
    var id = await _session.nodeUnder(point.dx, point.dy);
    if (!mounted) return;
    // Nothing under the point is a miss, not a selection to clear: you clicked
    // the margin, and losing what you had chosen for that would be a punishment
    // for a slip.
    if (id != null) handle.setParam('node', id);
    // One pick per arming, as Chrome does. Staying armed means the next click
    // anywhere is also a pick, which is how you end up fighting the tool to
    // press a button in your own demo.
    _picking.value = false;
    _highlight.value = null;
  }

  /// Everything the guest needs to be driven: keys, hover, and pointers, in
  /// [dpr] — the panel's when it fills the panel, the device's when it is one.
  ///
  /// While [_picking] the guest is given **nothing**: not the click, which
  /// would tap the button you were trying to inspect, and not the hover, which
  /// would light the demo's own hover states underneath the thing you are
  /// trying to see.
  Widget _guestInput(EmbeddedEngine engine, double dpr, Widget sizedBox) {
    // The guest's picture, built once and handed to whichever mode is on. Built
    // per-mode it is easy to pass the placeholder to one of them, which is what
    // happened: arming the picker replaced the demo with an empty box, so the
    // preview vanished the moment you went to point at it.
    var picture = engine.textureId == null
        ? sizedBox
        : Texture(textureId: engine.textureId!);
    return ValueListenableBuilder(
      valueListenable: _picking,
      builder: (context, picking, _) => picking
          ? _pickerInput(context, picture)
          : _demoInput(engine, dpr, picture),
    );
  }

  Widget _pickerInput(BuildContext context, Widget picture) {
    // Its own focus, because the demo's is not mounted while picking — and a
    // mode you can only leave by finding the button again is a trap.
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        _picking.value = false;
        _highlight.value = null;
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        // Local coordinates are the guest's own: the box is sized to the guest's
        // logical size in both staging modes, so a point here needs no transform
        // — and neither does the rect that comes back.
        onHover: (e) => _highlight.value = _session.treeForSelection
            ?.nodeAtPoint(e.localPosition.dx, e.localPosition.dy)
            ?.id,
        onExit: (_) => _highlight.value = null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (e) => unawaited(_pick(context, e.localPosition)),
          child: _withOverlay(picture),
        ),
      ),
    );
  }

  Widget _demoInput(EmbeddedEngine engine, double dpr, Widget picture) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        // Ignored, not handled: it carries on up to whichever
        // `CallbackShortcuts` claims it — this panel's, or the shell's.
        if (_isAppChord(event)) return KeyEventResult.ignored;
        engine.sendKey(
          kind: event is KeyDownEvent
              ? KeyEventKind.down
              : event is KeyRepeatEvent
              ? KeyEventKind.repeat
              : KeyEventKind.up,
          physicalKey: event.physicalKey.usbHidUsage,
          logicalKey: event.logicalKey.keyId,
        );
        return KeyEventResult.handled;
      },
      // Hover is not a [Listener]'s business: with no button held the engine
      // sends `PointerHoverEvent`, which `onPointerMove` never sees. Without
      // this the demo is blind to the mouse unless you are dragging — no ink
      // highlight, no `MouseRegion`, no hover tooltip, every demo frozen in
      // its resting state.
      child: MouseRegion(
        onEnter: (e) => engine.sendPointer(
          phaseKind: PointerPhase.add,
          x: e.localPosition.dx * dpr,
          y: e.localPosition.dy * dpr,
        ),
        onHover: (e) => engine.sendPointer(
          phaseKind: PointerPhase.hover,
          x: e.localPosition.dx * dpr,
          y: e.localPosition.dy * dpr,
        ),
        // Paired with the add: the guest is tracking a device that has left
        // the window, and a hover state left behind never lifts.
        onExit: (e) => engine.sendPointer(
          phaseKind: PointerPhase.remove,
          x: e.localPosition.dx * dpr,
          y: e.localPosition.dy * dpr,
        ),
        child: Listener(
          onPointerDown: (e) {
            _focusNode.requestFocus();
            engine.sendPointer(
              phaseKind: PointerPhase.down,
              x: e.localPosition.dx * dpr,
              y: e.localPosition.dy * dpr,
              buttons: 1,
            );
          },
          onPointerMove: (e) => engine.sendPointer(
            phaseKind: PointerPhase.move,
            x: e.localPosition.dx * dpr,
            y: e.localPosition.dy * dpr,
            buttons: 1,
          ),
          onPointerUp: (e) => engine.sendPointer(
            phaseKind: PointerPhase.up,
            x: e.localPosition.dx * dpr,
            y: e.localPosition.dy * dpr,
          ),
          child: _withOverlay(picture),
        ),
      ),
    );
  }

  /// The guest's picture with the highlight drawn over it.
  ///
  /// **Inside the texture's own box**, which is the whole trick: node rects
  /// are in the guest's logical coordinates and this box *is* the guest's
  /// logical size, so the painter needs no transform — and it inherits the
  /// `FittedBox` and the `DeviceFrame` above it, so the highlight stays put
  /// when the preview is staged as a phone. Drawn over the canvas instead, it
  /// would need the scale, the offset and the frame's own inset, and would be
  /// wrong on every device change until each was found again.
  Widget _withOverlay(Widget picture) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        picture,
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder(
              valueListenable: _highlight,
              builder: (context, hovered, _) {
                // **Hover only, never the selection.** A box that stayed put
                // after you chose something is a box you then have to find a
                // way to dismiss — which is the state this was in, with no way
                // out at all. Chrome draws it while you point and stops when
                // you stop; what a selection leaves behind is a row in the
                // tree, not a rectangle on the picture.
                var node = hovered == null
                    ? null
                    : _session.treeForSelection?.nodeAt(hovered);
                return ValueListenableBuilder(
                  valueListenable: _session.watchedBox,
                  builder: (context, live, _) => CustomPaint(
                    painter: _HighlightPainter(
                      node: node,
                      // The guest's own last frame, when it is about this node.
                      // The tree's rect is of the build it was read from, which
                      // on anything animating is already wrong — and a
                      // rectangle in the wrong place does not read as slightly
                      // stale, it reads as broken.
                      live: live?.id == hovered ? live : null,
                      color: context.colors.accent,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws a box around one node, and its type above it.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({required this.node, required this.color, this.live});

  final InspectNode? node;

  /// The same node's box as of the guest's last frame, when the watch is
  /// reporting it. Wins over the tree's, which is of the build it was read
  /// from — correct the instant it arrives and wrong for as long as anything
  /// on screen is moving.
  final WatchBox? live;

  final Color color;

  /// Where to draw: the live box if there is one, else what the tree said.
  Rect? get _rect {
    if (live case var box?) {
      return Rect.fromLTWH(box.x, box.y, box.width, box.height);
    }
    if (node?.layout case var layout?) {
      return Rect.fromLTWH(layout.x, layout.y, layout.width, layout.height);
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The node is still what names the box — a live rect with no node behind
    // it would draw a rectangle labelled nothing.
    if (node == null) return;
    var rect = _rect;
    if (rect == null) return;
    canvas
      ..drawRect(rect, Paint()..color = color.withValues(alpha: 0.18))
      ..drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

    // The type, because a rectangle alone does not say which of the four boxes
    // stacked at this corner you have got.
    var label = TextPainter(
      text: TextSpan(
        text: ' ${node!.type} ',
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Above the box, or inside it when there is no room above — a label off
    // the top of the picture names nothing.
    var top = rect.top >= label.height ? rect.top - label.height : rect.top;
    var left = rect.left
        .clamp(0.0, math.max(0.0, size.width - label.width))
        .toDouble();
    canvas.drawRect(
      Rect.fromLTWH(left, top, label.width, label.height),
      Paint()..color = color,
    );
    label.paint(canvas, Offset(left, top));
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.node?.id != node?.id || old._rect != _rect || old.color != color;
}

/// The controls the entry declared while it built.
///
/// Absent, not empty, when there are none: most demos have no knobs, and a
/// permanent empty drawer is a permanent reminder of a feature you are not
/// using.
class _KnobPanel extends StatelessWidget {
  const _KnobPanel({required this.session});

  final CatalogSession session;

  @override
  Widget build(BuildContext context) {
    if (session.knobs.knobs.isEmpty) {
      return Container(
        color: context.colors.panel,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Text(
          // Says what a knob *is*, because this is the state most entries are
          // in and it is the only moment anybody reads this pane.
          'This entry declares no knobs.\nA demo gets one by asking while it '
          'builds — context.uiCatalog.parameters.string("label", "Hello").',
          textAlign: TextAlign.center,
          style: context.type.caption.copyWith(color: context.colors.mut),
        ),
      );
    }
    return Container(
      color: context.colors.panel,
      width: double.infinity,
      // The entry's knobs own `knob.*`, and only this panel. Nested below the
      // level that owns the entry segment, which is what says a knob dies with
      // the entry while an axis does not.
      child: AddressScope(
        namespace: 'knob',
        child: Builder(
          builder: (context) {
            var selections = AddressScope.params(context);
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: FwSpacing.lg,
                vertical: FwSpacing.md,
              ),
              child: Wrap(
                spacing: FwSpacing.xxl,
                runSpacing: FwSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var knob in session.knobs.knobs)
                    _Knob(
                      // Keyed by name, so a field keeps its cursor when the
                      // report is read back and the list is rebuilt around it.
                      key: ValueKey(knob.name),
                      knob: knob,
                      selections: selections,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({super.key, required this.knob, required this.selections});

  final KnobDescriptor knob;

  /// What the address asked for. Wins over the guest's confirmation while the
  /// two disagree, which is the whole of the optimistic update — see
  /// [paramDisplayValue]. Nothing is mutated to achieve it.
  final Map<String, String> selections;

  Object? get _value => paramDisplayValue(knob, selections);

  /// Writes the choice into the address, and stops there. The demo is told
  /// because the session is watching the address, not because this told it.
  void _choose(BuildContext context, Object? value) => AddressScope.write(
    context,
  ).setParam(paramKeyFor(knob), paramValueSlug(knob, value));

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: FwSpacing.md,
      children: [
        Text(
          knob.name,
          style: context.type.caption.copyWith(
            // Bright when it has been moved, so what you have changed is
            // legible at a glance against what you have not.
            color: _value == knob.defaultValue
                ? context.colors.mut
                : context.colors.ink,
          ),
        ),
        _control(context),
      ],
    );
  }

  Widget _control(BuildContext context) {
    switch (knob.kind) {
      case KnobKind.boolean:
        return _Toggle(
          value: _value == true,
          onChanged: (v) => _choose(context, v),
        );
      case KnobKind.picker:
        return _Popover<String?>(
          selected: _value as String?,
          onSelected: (v) => _choose(context, v),
          groups: [
            (
              heading: null,
              items: [
                for (var option in knob.options)
                  (value: option, label: option, detail: ''),
              ],
            ),
          ],
          child: _Field(
            child: Text(
              (_value ?? '—').toString(),
              style: context.type.caption.copyWith(color: context.colors.ink),
            ),
          ),
        );
      case KnobKind.integer || KnobKind.number:
        if (knob.min case var min?) {
          if (knob.max case var max?) return _slider(context, min, max);
        }
        return _NumberField(
          knob: knob,
          value: _value,
          onChanged: (v) => _choose(context, v),
        );
      case KnobKind.string:
        return _StringField(
          knob: knob,
          value: _value,
          onChanged: (v) => _choose(context, v),
        );
    }
  }

  Widget _slider(BuildContext context, num min, num max) {
    var value = (_value as num? ?? min).toDouble().clamp(
      min.toDouble(),
      max.toDouble(),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 132,
          // Without this the slider reserves room for a touch target on each
          // side, and the value beside it reads as belonging to the next knob.
          child: SliderTheme(
            data: const SliderThemeData(padding: EdgeInsets.zero),
            child: Slider(
              value: value,
              min: min.toDouble(),
              max: max.toDouble(),
              // Whole steps for a whole number, so dragging cannot land between
              // two of them.
              divisions: knob.kind == KnobKind.integer
                  ? (max - min).round().clamp(1, 1000)
                  : null,
              onChanged: (v) => _choose(
                context,
                knob.kind == KnobKind.integer ? v.round() : v,
              ),
            ),
          ),
        ),
        const Gap(FwSpacing.md),
        SizedBox(
          width: 26,
          child: Text(
            knob.kind == KnobKind.integer
                ? '${value.round()}'
                : value.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: context.type.caption.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

/// A boolean, drawn to the same scale as the fields beside it.
///
/// Hand-rolled rather than a [Switch]: the stock one is 52 by 32 and coloured
/// from the Material theme, so in a 36-pixel bar of 24-pixel fields it was both
/// the largest thing on the row and the only thing not using the palette.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Semantics(
      container: true,
      toggled: value,
      // A [Switch] carries these for free; a hand-rolled one has to say so, or
      // the control becomes invisible to everything that is not a pair of eyes.
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // The visible track is 14 tall; the target is the whole row height,
          // so it can be hit without aiming.
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: SizedBox(
            height: 24,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: 26,
                height: 14,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: value ? colors.accent : colors.bg,
                  border: Border.all(
                    color: value ? colors.accent : colors.line,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: value ? colors.panel : colors.mut,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The box every knob control sits in, so a field, a picker and a number all
/// line up.
class _Field extends StatelessWidget {
  const _Field({required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 24,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.bg,
        border: Border.all(color: context.colors.line),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      child: child,
    );
  }
}

/// A text knob, applied as you stop typing rather than as you type.
///
/// Every keystroke would be a round trip to the guest and a rebuild of the
/// demo, which is both wasteful and jumpy to read.
class _StringField extends StatefulWidget {
  const _StringField({
    required this.knob,
    required this.value,
    required this.onChanged,
  });

  final KnobDescriptor knob;

  /// What the address asks for, not what the guest last confirmed.
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  State<_StringField> createState() => _StringFieldState();
}

class _StringFieldState extends State<_StringField> {
  late final _controller = TextEditingController(text: '${widget.value ?? ''}');
  final _focus = FocusNode();
  Timer? _debounce;

  @override
  void didUpdateWidget(_StringField old) {
    super.didUpdateWidget(old);
    // Only when the change came from somewhere else — writing back into a field
    // that has the caret would fight the cursor. Focus rather than the debounce
    // timer: between a debounce firing and the guest answering there is a
    // stretch where no timer is pending and the user is still typing.
    var value = '${widget.value ?? ''}';
    if (!_focus.hasFocus && value != _controller.text) {
      _controller.text = value;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Field(
      width: 140,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        style: context.type.caption.copyWith(color: context.colors.ink),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (value) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), () {
            _debounce = null;
            widget.onChanged(value);
          });
        },
      ),
    );
  }
}

/// A number without bounds, which is a field rather than a slider — there is
/// nothing to slide between.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.knob,
    required this.value,
    required this.onChanged,
  });

  final KnobDescriptor knob;

  /// What the address asks for, not what the guest last confirmed.
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  // Owned rather than built: a controller made in `build` is a new one on every
  // rebuild, and the panel rebuilds whenever any knob moves — so typing here
  // while a slider elsewhere settles would lose what you had typed.
  late final _controller = TextEditingController(text: '${widget.value ?? ''}');
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    // Never while it has the caret: the value on screen is then the user's,
    // and the guest's is what they are in the middle of replacing.
    var value = '${widget.value ?? ''}';
    if (!_focus.hasFocus && value != _controller.text) {
      _controller.text = value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Field(
      width: 80,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        style: context.type.caption.copyWith(color: context.colors.ink),
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: _apply,
        // Also on the way out, so clicking away from a number you have typed
        // applies it rather than quietly reverting it on the next rebuild.
        onTapOutside: (_) {
          _focus.unfocus();
          _apply(_controller.text);
        },
      ),
    );
  }

  void _apply(String text) {
    var parsed = num.tryParse(text);
    if (parsed == null) return;
    widget.onChanged(
      widget.knob.kind == KnobKind.integer ? parsed.round() : parsed,
    );
  }
}

/// What the guest is being rendered as, and nothing about which entry it is —
/// that is the list's job, and the status bar's.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.session});

  final CatalogSession session;

  @override
  Widget build(BuildContext context) {
    var staging = session.staging;
    var device = _deviceOf(context, session);
    return Container(
      color: context.colors.panel,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
      height: 36,
      child: Row(
        spacing: FwSpacing.md,
        children: [
          _DevicePicker(device: device),
          if (device != null)
            Text(
              describeDevice(device),
              style: context.type.caption.copyWith(fontFamily: 'monospace'),
            ),
          // The shell's own switches, after what the guest is *staged* as. A
          // different order would read as if the flavor were a property of the
          // phone rather than of the app inside it.
          //
          // Scrolling rather than wrapping or shrinking: the bar is one row
          // tall by design, a project may declare more axes than fit beside a
          // device name, and the alternative is that the last one silently
          // pushes the frame toggle off the end.
          Expanded(
            // The shell's axes own `axis.*`, and only this subtree. Nested
            // rather than written as a full key so the controls below say
            // `theme`, not `axis.theme` — and so the device picker beside them
            // keeps reading flutterware's own un-namespaced parameters.
            child: AddressScope(
              namespace: 'axis',
              // Below the scope, so `params` is `axis.*` rather than
              // flutterware's own un-namespaced ones.
              child: Builder(
                builder: (context) {
                  var selections = AddressScope.params(context);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      spacing: FwSpacing.lg,
                      children: [
                        for (var axis in session.axes.axes)
                          _Axis(
                            // Keyed by name so a picker keeps its place when
                            // the report is read back and the row is rebuilt
                            // around it.
                            key: ValueKey(axis.name),
                            axis: axis,
                            selections: selections,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          _CaptureButtons(session: session),
          if (device != null)
            IconButton(
              icon: Icon(
                staging.frameVisible ? Icons.phone_iphone : Icons.crop_din,
                size: 16,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              tooltip: staging.frameVisible
                  ? 'Hide the frame'
                  : 'Show the frame',
              onPressed: () => staging.frameVisible = !staging.frameVisible,
            ),
        ],
      ),
    );
  }
}

/// The live guest's next frame, cropped to whatever node is selected.
///
/// Shared by the top bar's buttons and the panel's ⌘⇧C. A shortcut that copied
/// the whole frame while the button beside it copied the selected node would be
/// two behaviours wearing one name.
///
/// Null when there is no guest to ask — the panel is compiling, or the last
/// build failed — which is a refusal rather than an error: there is nothing on
/// screen to be a picture of.
Future<Uint8List?> _capturePreview(
  BuildContext context,
  CatalogSession session,
) async {
  var engine = session.engine;
  if (engine == null || engine.phase != EmbeddedEnginePhase.running) {
    return null;
  }
  var node = _croppedNode(context, session);
  return engine.capturePng(
    crop: node?.layout,
    // A crop arrives in the guest's logical coordinates; its pixels are in the
    // device's.
    pixelRatio: _deviceOf(context, session)?.pixelRatio ?? 1,
  );
}

/// The node the Elements tab has selected, when its tree still describes what
/// is on screen — a rect read before the last switch would crop this frame to a
/// box measured in another one.
///
/// `node` is named as `inspect`'s rather than read plainly, because every caller
/// is in the top bar: one level *above* the scope that owns it, where a plain
/// read asks for an un-namespaced `node` nobody writes. The buttons then
/// photographed the whole frame however the tree was set — the same boundary
/// [_deviceOf] falls off in the other direction.
InspectNode? _croppedNode(BuildContext context, CatalogSession session) {
  var id = AddressScope.params(context, namespace: _inspectNamespace)['node'];
  return id == null ? null : session.treeForSelection?.nodeAt(id);
}

/// Copy the preview to the clipboard, or save it to a file.
///
/// These photograph the **live** guest, which is why they are here rather than
/// being the `screenshot` action with a button on it. What they capture is the
/// demo as you left it — the dropdown you opened, the tab you switched to, the
/// row you scrolled to — and no fresh render performs your clicks. `fw` cannot
/// offer the same thing and deliberately refuses to pretend otherwise: an
/// attached session gives it a VM service and no frames. The panel is the only
/// place that holds the socket the picture comes over.
///
/// With a node selected in the Elements tab they capture that node's box
/// instead of the whole frame — cropped out of the real composited frame, so it
/// is the widget among its surroundings rather than the different picture that
/// re-rendering it alone would produce.
class _CaptureButtons extends StatefulWidget {
  const _CaptureButtons({required this.session});

  final CatalogSession session;

  @override
  State<_CaptureButtons> createState() => _CaptureButtonsState();
}

class _CaptureButtonsState extends State<_CaptureButtons> {
  /// Set while a capture is in flight, so a second click cannot start one on
  /// top of it — the two would write the same scratch path.
  var _busy = false;

  /// Flips the copy icon to a tick for a moment. A 36px bar has no room for a
  /// message, and a button that looks identical before and after is a button
  /// you press twice.
  Timer? _copied;

  @override
  void dispose() {
    _copied?.cancel();
    super.dispose();
  }

  Future<Uint8List?> _capture() async {
    setState(() => _busy = true);
    try {
      return await _capturePreview(context, widget.session);
    } catch (e) {
      if (mounted) _complain('$e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    var png = await _capture();
    if (png == null || !mounted) return;
    try {
      await ImageClipboard.setPng(png);
      if (!mounted) return;
      _copied?.cancel();
      setState(() {});
      _copied = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) _complain('$e');
    }
  }

  Future<void> _save() async {
    var png = await _capture();
    if (png == null || !mounted) return;
    var location = await getSaveLocation(
      suggestedName: _suggestedName(),
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG image', extensions: ['png']),
      ],
    );
    if (location == null) return;
    try {
      await File(location.path).writeAsBytes(png);
    } catch (e) {
      if (mounted) _complain('$e');
    }
  }

  /// Named after what it is a picture *of*, so a directory of these is still
  /// readable a week later. Matches what the `screenshot` action derives.
  String _suggestedName() {
    var entry = widget.session.selected ?? widget.session.active;
    var base = entry == null
        ? 'catalog'
        : entry.id.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    var node = AddressScope.params(
      context,
      namespace: _inspectNamespace,
    )['node'];
    return '$base${node == null ? '' : '-node-${node.replaceAll('/', '-')}'}.png';
  }

  /// Failures only. A capture that worked says so by changing the icon; one
  /// that did not has a reason, and a reason needs words.
  void _complain(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Could not capture the preview: $message')),
  );

  @override
  Widget build(BuildContext context) {
    var running = widget.session.engine?.phase == EmbeddedEnginePhase.running;
    var enabled = running && !_busy;
    var cropped = _croppedNode(context, widget.session) != null;
    var what = cropped ? 'the selected node' : 'the preview';
    var justCopied = _copied?.isActive ?? false;

    return Row(
      spacing: FwSpacing.xs,
      children: [
        IconButton(
          icon: Icon(justCopied ? Icons.check : Icons.content_copy, size: 15),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 24, height: 24),
          tooltip: ImageClipboard.isSupported
              ? 'Copy $what (⌘⇧C)'
              : 'Copying an image is not implemented on this platform',
          onPressed: enabled && ImageClipboard.isSupported ? _copy : null,
        ),
        IconButton(
          icon: const Icon(Icons.save_alt, size: 15),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 24, height: 24),
          tooltip: 'Save $what as PNG',
          onPressed: enabled ? _save : null,
        ),
      ],
    );
  }
}

/// One of the shell's axes, in the top bar.
///
/// Labelled unconditionally, unlike a knob, which is written as
/// `name  [control]` in a panel of its own. Up here an axis sits beside a
/// device picker and a frame toggle, and an unlabelled `staging` would read as
/// something about the phone.
class _Axis extends StatelessWidget {
  const _Axis({super.key, required this.axis, required this.selections});

  final KnobDescriptor axis;

  /// What the address asked for, which wins over the guest's own report while
  /// the two disagree — see [axisDisplayValue]. That is the whole of the
  /// optimistic update, and it mutates nothing.
  final Map<String, String> selections;

  /// Writes the choice into the address, and stops there. The guest is told
  /// because the session is watching the address, not because this told it.
  void _choose(BuildContext context, Object? value) => AddressScope.write(
    context,
  ).setParam(paramKeyFor(axis), paramValueSlug(axis, value));

  @override
  Widget build(BuildContext context) {
    var value = paramDisplayValue(axis, selections);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: FwSpacing.sm,
      children: [
        Text(
          axis.name,
          style: context.type.caption.copyWith(
            // Bright once it is off its default, so what you have changed
            // about the whole catalog is legible without reading the values.
            color: value == axis.defaultValue
                ? context.colors.mut
                : context.colors.ink,
          ),
        ),
        if (axis.kind == KnobKind.boolean)
          _Toggle(value: value == true, onChanged: (v) => _choose(context, v))
        else
          _Popover<String?>(
            selected: value as String?,
            onSelected: (v) => _choose(context, v),
            groups: [
              (
                heading: null,
                items: [
                  for (var option in axis.options)
                    (
                      value: option,
                      label: option,
                      detail: option == axis.defaultValue ? 'default' : '',
                    ),
                ],
              ),
            ],
            child: _Field(
              child: Text(
                (value ?? '—').toString(),
                style: context.type.caption.copyWith(color: context.colors.ink),
              ),
            ),
          ),
      ],
    );
  }
}

/// Picks what the guest is sized to. "Fit" is the panel itself.
///
/// Hand-rolled rather than a [PopupMenuButton]: the stock menu gives every row
/// the same weight, so the platform headings read as disabled entries, and its
/// scale-from-nothing entrance belongs to a floating action button rather than
/// to a control that drops open under your cursor.
class _DevicePicker extends StatelessWidget {
  const _DevicePicker({required this.device});

  /// What is on screen, already resolved. The picker holds nothing.
  final CatalogDevice? device;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return _Popover<CatalogDevice?>(
      selected: device,
      // **The only place a device is chosen, and it writes the address.** It
      // used to set the staging and let the panel copy that into the address a
      // frame later; the copy came back stale and undid the pick.
      onSelected: (value) => AddressScope.write(
        context,
      ).setParam('device', value?.id ?? fitDeviceId),
      groups: [
        (
          heading: null,
          items: [(value: null, label: 'Fit', detail: 'the panel')],
        ),
        for (var group in {for (var d in catalogDevices) d.group})
          (
            heading: group,
            items: [
              for (var d in catalogDevices.where((d) => d.group == group))
                (value: d, label: d.label, detail: describeDevice(d)),
            ],
          ),
      ],
      child: Container(
        padding: const EdgeInsets.only(left: FwSpacing.md, right: FwSpacing.xs),
        height: 24,
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        ),
        child: Row(
          spacing: FwSpacing.xs,
          children: [
            Text(
              // Straight off the device now. It used to be a scan of the list
              // by `device_frame` identifier, because staging held that type
              // rather than ours.
              device?.label ?? 'Fit',
              style: context.type.caption.copyWith(color: colors.ink),
            ),
            Icon(Icons.expand_more, size: 14, color: colors.mut),
          ],
        ),
      ),
    );
  }
}

typedef _PopoverItem<T> = ({T value, String label, String detail});
typedef _PopoverGroup<T> = ({String? heading, List<_PopoverItem<T>> items});

/// A menu that drops open under its anchor.
class _Popover<T> extends StatelessWidget {
  const _Popover({
    required this.groups,
    required this.selected,
    required this.onSelected,
    required this.child,
  });

  final List<_PopoverGroup<T>> groups;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, FwSpacing.xs),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(context.colors.panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: FwSpacing.sm),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            side: BorderSide(color: context.colors.line),
            borderRadius: BorderRadius.circular(context.radii.radius),
          ),
        ),
      ),
      builder: (context, controller, child) => InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        child: child,
      ),
      menuChildren: [
        for (var group in groups) ...[
          if (group.heading case var heading?)
            // A heading, not a disabled row: uppercase, muted and half-height,
            // so the eye takes it for a label rather than for something it is
            // not allowed to pick.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FwSpacing.lg,
                FwSpacing.md,
                FwSpacing.lg,
                FwSpacing.xxs,
              ),
              child: Text(
                heading.toUpperCase(),
                style: context.type.micro.copyWith(
                  color: context.colors.mut2,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          for (var item in group.items)
            _PopoverRow(
              item: item,
              selected: item.value == selected,
              onTap: () => onSelected(item.value),
            ),
        ],
      ],
      child: child,
    );
  }
}

class _PopoverRow<T> extends StatelessWidget {
  const _PopoverRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _PopoverItem<T> item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return MenuItemButton(
      onPressed: onTap,
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(
          selected ? colors.accentSoft : Colors.transparent,
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: FwSpacing.lg),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
      ),
      child: SizedBox(
        width: 200,
        child: Row(
          spacing: FwSpacing.lg,
          children: [
            Expanded(
              child: Text(
                item.label,
                style: context.type.bodySmall.copyWith(color: colors.ink),
              ),
            ),
            // The size, right-aligned in its own column: it is what you are
            // choosing between once you know the names.
            Text(
              item.detail,
              style: context.type.caption.copyWith(
                fontFamily: 'monospace',
                color: colors.mut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The entry browser: a filter, then the tree.
class _EntryList extends StatelessWidget {
  const _EntryList({required this.session});

  final CatalogSession session;

  @override
  Widget build(BuildContext context) {
    var browsing = session.browsing;
    // Built from everything discovered, broken included: an entry you are
    // midway through fixing keeps its place, and selecting it is the retry.
    var tree = filterCatalogTree(
      buildCatalogTree(session.allEntries),
      browsing.filter,
    );
    var filtering = browsing.filter.trim().isNotEmpty;
    // Whatever is selected is visible, whatever was folded away before it was.
    var reveal = branchesTo(tree, session.selected?.id);
    var rows = <Widget>[];
    void walk(List<CatalogNode> nodes, int depth) {
      for (var node in nodes) {
        switch (node) {
          case CatalogLeaf(:var entry):
            rows.add(
              _LeafRow(
                entry: entry,
                depth: depth,
                broken: session.compileErrorFor(entry),
                selected: entry.id == session.selected?.id,
                highlight: browsing.filter.trim(),
                onTap: session.phase == CatalogSessionPhase.ready
                    ? () => session.switchTo(entry)
                    : null,
              ),
            );
          case CatalogBranch(:var children):
            // A filtered tree is already the answer to a question; folding
            // part of it away would only hide what was asked for.
            var open =
                filtering ||
                reveal.contains(node.id) ||
                browsing.isOpen(node.id);
            rows.add(
              _BranchRow(
                branch: node,
                depth: depth,
                open: open,
                highlight: browsing.filter.trim(),
                onTap: filtering ? null : () => browsing.toggle(node.id),
              ),
            );
            if (open) walk(children, depth + 1);
        }
      }
    }

    walk(tree, 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterField(browsing: browsing, tree: tree),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    filtering ? 'Nothing matches' : 'No entries',
                    style: context.type.caption,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
                  children: rows,
                ),
        ),
      ],
    );
  }
}

/// Indent for [depth], plus the width a branch spends on its chevron so that
/// leaves and folders at the same level start at the same place.
EdgeInsets _rowPadding(int depth) =>
    EdgeInsets.only(left: FwSpacing.md + depth * 14.0, right: FwSpacing.md);

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.depth,
    required this.open,
    required this.highlight,
    required this.onTap,
  });

  final CatalogBranch branch;
  final int depth;
  final bool open;

  /// What the filter is showing this row for, marked in the label.
  final String highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: _rowPadding(depth),
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: colors.mut,
              ),
              const Gap(FwSpacing.xs),
              Expanded(
                child: _Marked(
                  text: branch.label,
                  mark: highlight,
                  style: context.type.caption.copyWith(color: colors.ink2),
                ),
              ),
              if (!open) ...[
                const Gap(FwSpacing.xs),
                Text(
                  '${branch.entries.length}',
                  style: context.type.micro.copyWith(color: colors.mut2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LeafRow extends StatelessWidget {
  const _LeafRow({
    required this.entry,
    required this.depth,
    required this.broken,
    required this.selected,
    required this.highlight,
    required this.onTap,
  });

  final CatalogEntry entry;
  final int depth;

  /// What the filter is showing this row for, marked in the name.
  final String highlight;

  /// The compiler's complaint, or null when the entry builds.
  final String? broken;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var color = broken != null ? colors.red : colors.ink;
    return Tooltip(
      // One line per entry leaves no room for the file, and the file is often
      // what you remember it by.
      message: '${entry.path} · ${entry.symbol}',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: selected ? colors.accentSoft : null,
          padding: _rowPadding(depth),
          child: SizedBox(
            height: 26,
            child: Row(
              children: [
                // The chevron column a branch occupies, so a leaf beside a
                // folder is indented to match rather than sitting under it.
                const SizedBox(width: 14 + FwSpacing.xs),
                Expanded(
                  child: _Marked(
                    text: entry.name,
                    mark: highlight,
                    style: context.type.bodySmall.copyWith(color: color),
                  ),
                ),
                if (broken != null) ...[
                  const Gap(FwSpacing.xs),
                  Icon(Icons.error_outline, size: 14, color: colors.red),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [text], with every occurrence of [mark] struck through with a highlighter.
///
/// A filtered list otherwise makes you find, in every row, the thing you just
/// typed. A row with no mark on it has answered too: it matched on its file or
/// its symbol, neither of which fits on the row.
class _Marked extends StatelessWidget {
  const _Marked({required this.text, required this.mark, required this.style});

  final String text;
  final String mark;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    var haystack = text.toLowerCase();
    var needle = mark.toLowerCase();
    if (needle.isEmpty || !haystack.contains(needle)) {
      return Text(text, overflow: TextOverflow.ellipsis, style: style);
    }

    var marked = style.copyWith(
      // Amber rather than a raw yellow, and see-through, so it reads as a
      // highlighter over the row instead of a second background colour.
      backgroundColor: context.colors.amber.withValues(alpha: 0.35),
      color: context.colors.ink,
    );
    var spans = <TextSpan>[];
    var at = 0;
    while (true) {
      var found = haystack.indexOf(needle, at);
      if (found < 0) {
        spans.add(TextSpan(text: text.substring(at)));
        break;
      }
      if (found > at) spans.add(TextSpan(text: text.substring(at, found)));
      at = found + needle.length;
      spans.add(TextSpan(text: text.substring(found, at), style: marked));
    }
    return Text.rich(
      TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _FilterField extends StatefulWidget {
  const _FilterField({required this.browsing, required this.tree});

  final CatalogBrowsing browsing;

  /// What "collapse all" would have to name.
  final List<CatalogNode> tree;

  @override
  State<_FilterField> createState() => _FilterFieldState();
}

/// One size for both of the field's icon slots, filled or not.
const _iconSlot = BoxConstraints.tightFor(width: 24, height: 22);

/// Says work is happening, but only once that is news.
///
/// A switch is 90ms. Anything that appears and disappears inside that is a
/// flash on every click, which reads as a fault rather than as progress — so
/// the dot waits out the common case and fades in only for the work you would
/// otherwise wonder about. Its slot is always there, so nothing moves either
/// way.
class BusyDot extends StatefulWidget {
  const BusyDot({super.key, required this.busy});

  /// What the session is doing, or null when it is idle.
  final String? busy;

  /// Longer than a warm switch, shorter than a wait you would question.
  static const appearsAfter = Duration(milliseconds: 250);

  @override
  State<BusyDot> createState() => _BusyDotState();
}

class _BusyDotState extends State<BusyDot> {
  Timer? _timer;
  var _shown = false;

  @override
  void didUpdateWidget(BusyDot old) {
    super.didUpdateWidget(old);
    if (widget.busy == old.busy) return;
    _timer?.cancel();
    if (widget.busy == null) {
      setState(() => _shown = false);
    } else {
      _timer = Timer(BusyDot.appearsAfter, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var dot = AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.accent,
          shape: BoxShape.circle,
        ),
      ),
    );
    return SizedBox(
      width: 8,
      height: 8,
      child: widget.busy == null
          ? dot
          : Tooltip(message: widget.busy!, child: dot),
    );
  }
}

class _FilterFieldState extends State<_FilterField> {
  late final _controller = TextEditingController(
    // Seeded rather than empty: the panel is rebuilt from scratch every time
    // you come back to it, and a filter that clears itself is a filter you
    // stop trusting.
    text: widget.browsing.filter,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(FwSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _controller,
                style: context.type.caption.copyWith(color: colors.ink),
                onChanged: (value) => widget.browsing.filter = value,
                decoration: InputDecoration(
                  hintText: 'Filter',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.md,
                  ),
                  prefixIcon: Icon(Icons.search, size: 14, color: colors.mut2),
                  // Both slots are the same size whether or not they hold
                  // anything. An `InputDecorator` sizes itself around its
                  // icons, so a clear button that comes and goes with the text
                  // takes the field's height with it.
                  prefixIconConstraints: _iconSlot,
                  suffixIconConstraints: _iconSlot,
                  suffixIcon: _controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: Icon(Icons.close, size: 14, color: colors.mut2),
                          padding: EdgeInsets.zero,
                          constraints: _iconSlot,
                          onPressed: () {
                            _controller.clear();
                            widget.browsing.filter = '';
                          },
                        ),
                ),
              ),
            ),
          ),
          const Gap(FwSpacing.xs),
          // One button for both directions: with nothing folded away the only
          // useful thing it can do is fold, and after that, unfold.
          IconButton(
            icon: Icon(
              widget.browsing.anyClosed ? Icons.unfold_more : Icons.unfold_less,
              size: 16,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: widget.browsing.anyClosed ? 'Expand all' : 'Collapse all',
            onPressed: () => widget.browsing.anyClosed
                ? widget.browsing.openAll()
                : widget.browsing.closeAll(allBranches(widget.tree)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: 'Hide the list',
            onPressed: () => widget.browsing.listVisible = false,
          ),
        ],
      ),
    );
  }
}

/// All that is left of the list when it is hidden: the way back.
class _ShowListStrip extends StatelessWidget {
  const _ShowListStrip({required this.browsing});

  final CatalogBrowsing browsing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: FwSpacing.md),
          child: IconButton(
            icon: const Icon(Icons.chevron_right, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: 'Show the list',
            onPressed: () => browsing.listVisible = true,
          ),
        ),
      ),
    );
  }
}

/// Why the selected entry is not on screen, where it would have been.
///
/// Deliberately not a red page. The compiler's own words are the content, and
/// they are long, dense and monospaced: they need a calm surface and real
/// contrast, not a wash that fights them.
class _CompileError extends StatelessWidget {
  const _CompileError({
    required this.entry,
    required this.error,
    required this.onRetry,
  });

  final CatalogEntry entry;
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return ColoredBox(
      color: colors.bg,
      child: Padding(
        padding: const EdgeInsets.all(FwSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.error_outline, size: 18, color: colors.red),
                ),
                const Gap(FwSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.name} doesn’t compile',
                        style: context.type.bodyStrong.copyWith(
                          color: colors.red,
                        ),
                      ),
                      const Gap(FwSpacing.xxs),
                      // Where to go and fix it.
                      Text(
                        '${entry.path} · ${entry.symbol}',
                        style: context.type.caption,
                      ),
                    ],
                  ),
                ),
                const Gap(FwSpacing.lg),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
            const Gap(FwSpacing.lg),
            // Loose, not expanded: the block is as tall as the diagnostic and
            // no taller. Five lines of error stretched down a 900px panel
            // reads as an empty page with a caption.
            Flexible(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.panel,
                  border: Border.all(color: colors.line),
                  borderRadius: BorderRadius.circular(context.radii.radius),
                ),
                clipBehavior: Clip.antiAlias,
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(FwSpacing.lg),
                    // Horizontal too, and never wrapped: a diagnostic puts a
                    // caret line under the offending column, and a wrapped line
                    // points the caret at the wrong character.
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        error,
                        style: context.type.caption.copyWith(
                          fontFamily: 'monospace',
                          color: colors.ink2,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.session, required this.onReload});

  final CatalogSession session;
  final VoidCallback onReload;

  /// Right-aligned in a fixed column, so a number that gains a digit pushes
  /// nothing along with it.
  static String _ms(Duration d) => '${'${d.inMilliseconds}'.padLeft(4)}ms';

  @override
  Widget build(BuildContext context) {
    var parts = <String>[];
    if (session.coldCompile case var cold?) parts.add('cold ${_ms(cold)}');
    if (session.lastSwitch case var report?) {
      parts.add(
        report.ok
            ? '${report.entry.name}: compile ${_ms(report.compile)} '
                  '· reload ${_ms(report.reload)} '
                  // What the reload was *made of*: edited files on a reload,
                  // added libraries on a first visit. Both are zero when the
                  // guest is showing what it already had.
                  '· ${report.reloaded ? '${report.editedCount} edited' : '+${report.newSourceCount} libs'}'
            : '${report.entry.name}: did not compile',
      );
    }
    var failed = session.lastSwitch?.ok == false;
    var ready = session.phase == CatalogSessionPhase.ready;
    var busy = session.busyWith;
    var colors = context.colors;
    var mono = context.type.caption.copyWith(fontFamily: 'monospace');
    return Container(
      // No red bar. A failure has a whole panel explaining it now, and a status
      // line that changes colour as well as content is one more thing moving.
      color: colors.panel,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
      // Every slot below is fixed, and the bar with them. A row that reflows
      // each time the compiler is asked something is a row nobody can read
      // while it works — which is the only time it has anything to say.
      height: 32,
      child: Row(
        spacing: FwSpacing.lg,
        children: [
          Expanded(
            child: Text(
              parts.join('   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: failed ? mono.copyWith(color: colors.red) : mono,
            ),
          ),
          // Activity sits by the button that starts it, not in front of the
          // report — an empty slot at the head of the line reads as an indent.
          BusyDot(busy: busy),
          IconButton(
            onPressed: ready && busy == null ? onReload : null,
            icon: const Icon(Icons.refresh, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: 'Reload (${Platform.isMacOS ? '⌘R' : 'Ctrl+R'})',
          ),
        ],
      ),
    );
  }
}

/// What the guest is staged as: whatever the address names, else what the entry
/// on screen declares.
///
/// Read at every point of use rather than stored anywhere. Subscribes to the
/// one parameter, so choosing a device rebuilds what draws the frame and
/// nothing above it.
///
/// `device` is un-namespaced, so [context] has to be one no [AddressScope] has
/// given a namespace to — from under `inspect` this asks for `inspect.device`
/// and quietly gets nothing.
///
/// Asserted rather than left to be noticed, because the failure is a picture
/// that is wrong without looking wrong: the canvas framed every entry as the
/// panel while the picker beside it named a phone. `write` rather than `of` —
/// this is a check, and a check that subscribed would rebuild on every address
/// change in debug and on none in release.
CatalogDevice? _deviceOf(BuildContext context, CatalogSession session) {
  assert(
    AddressScope.write(context).view.namespace == null,
    'device is un-namespaced: read it above any namespaced scope, or it asks '
    'for <namespace>.device and nobody writes that.',
  );
  return resolveDevice(
    AddressScope.param(context, 'device'),
    formFactor: session.selected?.formFactor,
  );
}
