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

import '../embedder/embedded_engine.dart' show EmbeddedEnginePhase;
import '../embedder/guest_channel.dart';
import '../embedder/guest_surface.dart';
import 'catalog_picture.dart';

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
      Widget guest = RepaintBoundary(
        key: surface._boundary,
        child: surface.root,
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
