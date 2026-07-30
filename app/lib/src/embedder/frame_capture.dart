import 'dart:async';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// The node types, not the umbrella `ui_catalog.dart`: that one reaches
// `package:flutter/widgets.dart`, and this file is on `fw`'s import graph
// through the headless pipeline.
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import 'protocol.dart';
import 'raw_frame.dart';

/// Asks a guest for the frame it composited, and turns it into a picture.
///
/// Both halves of the exchange live here on purpose. A capture is requested by
/// *path*: the guest writes a `.rawframe` and answers with [CapturedMessage]
/// naming it, so a caller holding the send without the ack has a file it cannot
/// know is finished. Splitting them is how you get a half-written frame.
///
/// Shared by the headless pipeline and by the GUI's live engine, because they
/// are the same exchange over different sockets. The live one is the only way
/// to photograph a demo *as somebody left it* — the dropdown they opened, the
/// row they scrolled to — since no fresh guest performs their clicks.
class FrameCapture {
  FrameCapture({required this.send, required this.workDir});

  /// Hands one message to the guest and returns once it is on the wire.
  ///
  /// Flushing is the caller's, not this class's, because only the caller knows
  /// what it is writing to. It has to happen though: a request still sitting in
  /// a socket buffer waits for an ack the guest was never asked for.
  final Future<void> Function(EmbedderMessage message) send;

  /// Where the raw frame lands on its way to being decoded.
  ///
  /// Each file is deleted as soon as it has been read, so nothing accumulates —
  /// but a frame is tens of megabytes while it exists, which is why this is a
  /// scratch directory rather than anywhere a user looks.
  final String workDir;

  /// Outstanding captures, by the path each was requested at.
  ///
  /// The completer carries a *failure* rather than completing with an error, and
  /// that is deliberate. A guest can report an error between the write and the
  /// flush — the window is small and it is a socket — and `completeError` on a
  /// future nothing is awaiting yet delivers to the zone instead, where it
  /// surfaces as an unhandled exception and takes the app down rather than
  /// failing this call. A value cannot be orphaned whenever it arrives.
  final _pending = <String, Completer<Object?>>{};

  /// Settles the capture [message] acknowledges.
  ///
  /// Returns false for anything that is not an ack, so a socket handler can
  /// offer it every message and go on with the ones this does not want.
  bool acknowledge(EmbedderMessage message) {
    if (message is! CapturedMessage) return false;
    _pending.remove(message.path)?.complete(null);
    return true;
  }

  /// Fails everything outstanding.
  ///
  /// A guest that has reported an error is not going to finish writing a frame,
  /// and a caller left on the timeout below learns thirty seconds later, in
  /// less detail, what [error] already said.
  void failAll(Object error) {
    for (var pending in _pending.values) {
      if (!pending.isCompleted) pending.complete(error);
    }
    _pending.clear();
  }

  /// Captures run one at a time, and that is a property of the guest rather
  /// than a convenience here.
  ///
  /// The host keeps **one** armed capture path: `kMsgCapture` does
  /// `free(g_capture_path); g_capture_path = path;` (`native/host.c`). A second
  /// request therefore does not queue behind the first, it *replaces* it — the
  /// first frame is never written, and whoever asked for it waits out the
  /// timeout for a file that is not coming. Overlapping callers are ordinary:
  /// the copy button and its ⌘⇧C shortcut are two of them, and an agent
  /// screenshotting while a panel is open is another.
  Future<void> _turn = Future.value();

  /// The frame the guest composites next, decoded, annotated and cropped.
  ///
  /// Next rather than last: the engine renders nothing when nothing changed, so
  /// the host arms the request and forces a frame. On a static scene that frame
  /// is identical to the one on screen.
  ///
  /// Waits for any capture already in flight — see [_turn]. [name] only names
  /// the scratch file; it does **not** make two captures independent, because
  /// nothing downstream of here can be.
  Future<img.Image> capture({
    InspectLayout? crop,
    List<InspectNode> annotate = const [],

    /// Logical-to-physical, for turning either of the above into pixels.
    double pixelRatio = 1,
    String name = 'screenshot',
    Duration timeout = const Duration(seconds: 30),
  }) {
    var result = _turn.then(
      (_) => _capture(
        crop: crop,
        annotate: annotate,
        pixelRatio: pixelRatio,
        name: name,
        timeout: timeout,
      ),
    );
    // The queue must not inherit this one's failure, or one bad capture would
    // fail every capture after it. Swallowed here only — `result` still throws
    // to the caller, and having a listener from this moment is also what keeps
    // an ignored failure off the zone.
    _turn = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<img.Image> _capture({
    required InspectLayout? crop,
    required List<InspectNode> annotate,
    required double pixelRatio,
    required String name,
    required Duration timeout,
  }) async {
    Directory(workDir).createSync(recursive: true);
    var path = p.join(workDir, '$name.rawframe');
    var file = File(path);
    // A stale file from a capture that timed out would otherwise be decoded as
    // if it were this one's answer.
    if (file.existsSync()) file.deleteSync();

    var done = _pending[path] = Completer<Object?>();
    Object? failure;
    try {
      await send(CaptureMessage(path));
      failure = await done.future.timeout(timeout);

      // `Object`, because it is whatever the socket handler was given — an
      // `ErrorMessage`'s text arrives wrapped in a StateError today, and this
      // rethrows what it was handed rather than reclassifying it.
      // ignore: only_throw_errors
      if (failure != null) throw failure;

      var image = decodeRawFrame(file.readAsBytesSync());
      // Annotate before cropping, so a box on a node partly outside the crop is
      // clipped with the picture rather than drawn against its edge.
      if (annotate.isNotEmpty) {
        image = annotateNodes(image, annotate, pixelRatio);
      }
      return crop == null ? image : cropToNode(image, crop, pixelRatio);
    } finally {
      _pending.remove(path);
      // Whatever happened. A frame is tens of megabytes uncompressed, and on
      // the failure paths the guest may write it after we stopped waiting — so
      // the one place that reliably has both the path and the last word is
      // here, not the success path this used to sit on.
      if (file.existsSync()) file.deleteSync();
    }
  }
}

/// The frame, cut to one node's box.
///
/// Cropped out of the real composited frame rather than re-rendered in
/// isolation, which is what `ext.flutter.inspector.screenshot` would do: a
/// widget photographed away from its surroundings is a different picture, and
/// usually not the one the question was about.
///
/// Clamped to the frame, because a node may legitimately sit partly outside it
/// — that is what an overflow *is* — and a crop that threw would refuse to show
/// the one case worth looking at.
img.Image cropToNode(img.Image image, InspectLayout rect, double ratio) {
  var x = (rect.x * ratio).round().clamp(0, image.width - 1);
  var y = (rect.y * ratio).round().clamp(0, image.height - 1);
  return img.copyCrop(
    image,
    x: x,
    y: y,
    width: (rect.width * ratio).round().clamp(1, image.width - x),
    height: (rect.height * ratio).round().clamp(1, image.height - y),
  );
}

/// A box and an id over each node.
///
/// The point is the id: an agent reads a tree, gets `0/1/2`, and then gets a
/// picture with `0/1/2` written on the thing it names. Without that the tree
/// and the screenshot are two observations of the same frame with nothing
/// joining them.
img.Image annotateNodes(
  img.Image image,
  List<InspectNode> nodes,
  double ratio,
) {
  for (var node in _distinctBoxes(nodes)) {
    if (node.layout case var layout?) {
      var x = (layout.x * ratio).round();
      var y = (layout.y * ratio).round();
      var w = (layout.width * ratio).round();
      var h = (layout.height * ratio).round();
      img.drawRect(
        image,
        x1: x,
        y1: y,
        x2: x + w - 1,
        y2: y + h - 1,
        color: img.ColorRgb8(255, 0, 128),
      );
      var label = node.id.isEmpty ? 'root' : node.id;
      // A filled strip behind it: these are drawn over a rendered UI, and
      // magenta-on-whatever-was-there is not always legible.
      var labelX = x + 2;
      var labelY = y < 16 ? y + 2 : y - 15;
      img.fillRect(
        image,
        x1: labelX - 1,
        y1: labelY - 1,
        x2: labelX + label.length * 8,
        y2: labelY + 14,
        color: img.ColorRgb8(255, 0, 128),
      );
      img.drawString(
        image,
        label,
        font: img.arial14,
        x: labelX,
        y: labelY,
        color: img.ColorRgb8(255, 255, 255),
      );
    }
  }
  return image;
}

/// One node per distinct box, outermost kept.
///
/// Most of a summary tree lays nothing out of its own: a provider, a builder
/// and the widget under them share one rect, so drawing every node draws the
/// same rectangle six times and stacks six labels on one corner. The first
/// version did exactly that and was unreadable — which is the difference
/// between a feature that exists and one that answers the question.
///
/// Outermost wins because it is the shorter id and the one a caller is more
/// likely to have meant; the inner ones are still in the tree for anyone who
/// wants them.
List<InspectNode> _distinctBoxes(List<InspectNode> nodes) {
  var seen = <String>{};
  return [
    for (var node in nodes)
      if (node.layout case var l?)
        if (seen.add('${l.x},${l.y},${l.width},${l.height}')) node,
  ];
}
