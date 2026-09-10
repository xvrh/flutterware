import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:flutterware/src/guest_extensions.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
import 'package:image/image.dart' as img;

import 'package:flutterware/previews_guest.dart'
    show CatalogEntryBuilder, CatalogHost, installInlineGuest;

import '../embedder/embedded_engine.dart' show EmbeddedEnginePhase;
import '../embedder/guest_channel.dart';
import '../embedder/guest_surface.dart';
import 'catalog_entry.dart';
import 'catalog_picture.dart';
import 'catalog_session.dart';
import 'catalog_source.dart';
import 'protocol.dart';

/// A catalog guest drawn inside the host, as a widget.
///
/// The embedder guest is a process the stage paints as a texture and talks to
/// over the VM service. This is the same guest — the same `CatalogHost` root,
/// the same extensions — in the host's own tree: the picture is the widget,
/// laid out at the size the stage asks for, and the channel calls the guest's
/// handlers directly. What it buys is a catalog where no process can be
/// spawned (a browser) and a panel test over a real entry (no process to
/// wait for); what it costs is isolation — an entry that throws throws here,
/// and a platform override is the host's.
///
/// The extensions the channel reaches must have been registered in this
/// process: `installInlineGuest` from `package:flutterware/previews_guest.dart`.
class InlineGuestSurface extends ChangeNotifier implements GuestSurface {
  InlineGuestSurface({required this.root});

  /// The guest's root — a `CatalogHost` over the entries this host holds.
  final Widget root;

  final _boundary = GlobalKey(debugLabel: 'flutterware.inline guest');

  @override
  EmbeddedEnginePhase get phase => EmbeddedEnginePhase.running;

  @override
  bool get hasPainted => _painted;
  var _painted = false;

  @override
  double get pixelRatio => _pixelRatio;
  var _pixelRatio = 1.0;

  /// What the stage last asked for, in physical pixels — see [resize]. Null
  /// until it has asked, which is the picture sizing itself to its parent.
  (int, int, EdgeInsets)? _size;

  @override
  void resize(
    int width,
    int height,
    double pixelRatio, {
    EdgeInsets insets = EdgeInsets.zero,
  }) {
    var next = (width, height, insets);
    if (next == _size && pixelRatio == _pixelRatio) return;
    _size = next;
    _pixelRatio = pixelRatio;
    _painted = false;
    notifyListeners();
  }

  @override
  void cancelPointer() {
    // The widget's own recognizers see the stage take the pointer, the way
    // any widget under a pan does; there is no pipe to flush.
  }

  @override
  Widget picture() => InlineGuestPicture(surface: this);

  @override
  Widget input({
    required Widget child,
    required FocusNode focusNode,
    required bool touch,
    bool Function(KeyEvent event)? shouldIgnoreKey,
    bool Function(PointerEvent event)? shouldIgnorePointer,
  }) =>
      // The widget receives the host's input directly. The stage's veto
      // covers the one case that matters here — a pan in progress — and the
      // keys the host reserves never reach a focused child either way.
      Focus(focusNode: focusNode, child: child);

  @override
  Future<Uint8List> capturePng({
    InspectLayout? crop,
    List<InspectNode> annotate = const [],
    double pixelRatio = 1,
  }) async {
    var boundary =
        _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('the inline guest is not on screen');
    }
    var image = await boundary.toImage(pixelRatio: _pixelRatio);
    var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (bytes == null) throw StateError('the inline guest could not be read');
    var decoded = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: bytes.buffer,
      numChannels: 4,
    );
    return img.encodePng(
      framePicture(
        decoded,
        framing: PictureFraming(crop: crop, boxes: annotate),
        pixelRatio: pixelRatio,
      ),
    );
  }

  void _didPaint() {
    if (_painted) return;
    _painted = true;
    notifyListeners();
  }
}

/// The guest laid out at the size the stage asked for, under the media query
/// an embedder would report for it. Public so a test can find where the
/// guest sits on the stage.
class InlineGuestPicture extends StatelessWidget {
  const InlineGuestPicture({super.key, required this.surface});

  final InlineGuestSurface surface;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: surface,
    builder: (context, _) {
      var ratio = surface._pixelRatio;
      var host = MediaQuery.of(context);
      // A semantics boundary, the way a window is one. An entry wrapped in
      // its own `MaterialApp` brings a navigator whose modal barrier blocks
      // the semantics of everything painted before it, up to the nearest
      // boundary — which, without this, is the studio: the rail, the tabs
      // and the entry list vanished from the accessibility tree the moment
      // such an entry mounted, measured on the web demo's browser walk.
      Widget guest = Semantics(
        container: true,
        explicitChildNodes: true,
        child: RepaintBoundary(key: surface._boundary, child: surface.root),
      );
      if (surface._size case (var width, var height, var insets)) {
        var logical = Size(width / ratio, height / ratio);
        guest = SizedBox.fromSize(
          size: logical,
          child: MediaQuery(
            // What the embedder tells its guest: the window is the device,
            // and the safe areas arrive as view insets — `CatalogHost` turns
            // them into padding, as it does for a process.
            data: host.copyWith(
              size: logical,
              devicePixelRatio: ratio,
              viewInsets: insets / ratio,
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
            ),
            child: guest,
          ),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => surface._didPaint());
      // Clipped like a window: a demo that overflows its device does not
      // spill onto the stage.
      return ClipRect(child: guest);
    },
  );
}

/// The guest's extensions, called in this process.
///
/// A framework extension — `ext.flutter.*`, the platform override and the
/// debug flags — has nothing to be called on here: the framework is the
/// host's, and overriding its platform would override the studio's. Those
/// are answered by echoing what was asked, which is what a guest that
/// applied them would answer.
class InProcessGuestChannel implements GuestChannel {
  @override
  Future<Map<String, dynamic>?> callExtension(
    String method, {
    Map<String, String> args = const {},
  }) async {
    if (method.startsWith('ext.flutter.')) return {...args};
    var response = await GuestExtensions.call(method, args);
    if (response == null) return null;
    if (response.errorCode != null) {
      throw StateError(
        '$method failed: ${response.errorDetail ?? response.errorCode}',
      );
    }
    var result = response.result;
    if (result == null) return null;
    return (jsonDecode(result) as Map).cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>?> requireExtension(
    String method, {
    Map<String, String> args = const {},
  }) => callExtension(method, args: args);

  @override
  Stream<Map<String, Object?>> extensionEvents(String kind) =>
      GuestExtensions.events(kind);

  @override
  Stream<String> developerLog() => const Stream.empty();

  /// Nothing to reload: the entries are compiled into this program.
  @override
  Future<void> reload(String dillPath) async {}

  @override
  bool get isGone => false;

  @override
  Future<void> close() async {}
}

/// A catalog compiled into the host: its entries, and how to build each.
///
/// What a generated table hands the studio — see `tool/demo/web_entries.dart`
/// — and what a test hands it by hand.
typedef InlinePreviews = ({
  List<CatalogEntry> entries,
  CatalogEntryBuilder? Function(String id) entryOf,
});

/// A catalog compiled into this program, and the guest that draws it — one
/// object, because the two share a fact.
///
/// A selection is a switch and never a compile: the guest holds every entry
/// already. But the session's compile path is not a no-op it can skip — an
/// embedder guest is told which entry to show by a *regenerated entrypoint*
/// whose file entry moved, reloaded over it, and the panel's first switch
/// after start lands on that path whenever the show arrives before the
/// picture is mounted. So [select] records the entry the way the entrypoint
/// would, and the root rebuilds with it as the file entry: the guest lands
/// on the selection whether or not it was mounted to be told.
class InlinePreviewsGuest {
  InlinePreviewsGuest(this.previews);

  final InlinePreviews previews;

  /// The entry the last selection named, or null before any — what the
  /// root treats as its file entry.
  final selected = ValueNotifier<String?>(null);

  late final _catalog = _InlineCatalog(this);

  /// `CatalogSession(connectToDaemon: …)`: answers the table instead of
  /// starting a compiler.
  Future<(CatalogSource, DaemonReady)> connect({
    required String dartExecutable,
    required DaemonConfig Function() config,
    void Function(String)? onLog,
    void Function(DaemonProgress)? onProgress,
  }) async => (
    _catalog,
    DaemonReady(
      sessionId: 'inline',
      assetsDir: '',
      icuData: '',
      coldCompile: Duration.zero,
      entries: previews.entries,
    ),
  );

  /// `CatalogSession(launchGuest: …)`: the guest as a widget in this tree.
  /// Sets the guest's extensions up in this process on the way, which is
  /// idempotent.
  Future<LaunchedGuest?> launch(
    GuestLaunch launch, {
    required void Function(GuestSurface surface) attach,
    required bool Function() abandoned,
  }) async {
    installInlineGuest(ids: () => [for (var e in previews.entries) e.id]);
    var surface = InlineGuestSurface(
      root: ValueListenableBuilder(
        valueListenable: selected,
        builder: (context, selected, _) => CatalogHost(
          fileEntryId: selected ?? previews.entries.first.id,
          entryOf: previews.entryOf,
        ),
      ),
    );
    attach(surface);
    return (channel: InProcessGuestChannel(), vmServiceUri: null);
  }
}

class _InlineCatalog implements CatalogSource {
  _InlineCatalog(this.guest);

  final InlinePreviewsGuest guest;

  @override
  CatalogChanged? get lastChange => null;

  @override
  Stream<CatalogChanged> get catalogChanges => const Stream.empty();

  @override
  Stream<AssetsChanged> get assetsChanges => const Stream.empty();

  @override
  Future<DaemonCompiled> select(
    String id, {
    bool full = false,
    bool ifChanged = false,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    guest.selected.value = id;
    return DaemonCompiled(
      requestId: 0,
      id: id,
      compile: Duration.zero,
      newSourceCount: 0,
      // Asked "only if a source moved": none ever does here, and the guest
      // was shown the entry already. Asked outright: a reload with nothing
      // behind it, which the in-process channel ignores — the file entry
      // recorded above is what moves the guest.
      unchanged: ifChanged,
      dill: '',
    );
  }

  @override
  Future<String> hostPath({Duration timeout = const Duration(minutes: 5)}) =>
      throw UnsupportedError('An inline catalog has no embedder host.');

  @override
  void shown(String id) {}

  @override
  void refresh() {}

  @override
  Future<void> close() async {}
}
