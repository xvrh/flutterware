import 'dart:async';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

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
/// to photograph a demo *as it was left* — the dropdown that was opened, the
/// row that was scrolled to — since no fresh guest repeats those clicks.
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

  /// The frame the guest composites next, decoded.
  ///
  /// Next rather than last: the engine renders nothing when nothing changed, so
  /// the host arms the request and forces a frame. On a static scene that frame
  /// is identical to the one on screen.
  ///
  /// Waits for any capture already in flight — see [_turn]. [name] only names
  /// the scratch file; it does **not** make two captures independent, because
  /// nothing downstream of here can be.
  Future<img.Image> capture({
    String name = 'screenshot',
    Duration timeout = const Duration(seconds: 30),
  }) async => await _queued(name, timeout, raw: false) as img.Image;

  /// [capture]'s frame with the pixels left exactly as the guest wrote them.
  ///
  /// For a consumer that reads BGRA as happily as RGBA — `ffmpeg` does — and
  /// so should not pay a 3-megapixel channel swizzle in Dart to be handed what
  /// it was already sent. Measured at 26ms a frame at phone resolution, which
  /// on a one-minute clip is 47 seconds spent converting pixels into a form
  /// the encoder immediately converts back.
  Future<RawFrame> captureRaw({
    String name = 'screenshot',
    Duration timeout = const Duration(seconds: 30),
  }) async => await _queued(name, timeout, raw: true) as RawFrame;

  Future<Object> _queued(String name, Duration timeout, {required bool raw}) {
    var result = _turn.then(
      (_) => _capture(name: name, timeout: timeout, raw: raw),
    );
    // The queue must not inherit this one's failure, or one bad capture would
    // fail every capture after it. Swallowed here only — `result` still throws
    // to the caller, and having a listener from this moment is also what keeps
    // an ignored failure off the zone.
    _turn = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// What a captured frame costs, split three ways.
  ///
  /// The guest draws and writes, this side reads and decodes, and only the
  /// first of those is rendering. Kept apart because they are fixed by
  /// different things — a scene's complexity, the disk, and the pixel format —
  /// and a plan to make capture cheaper has to know which one it is aimed at.
  Duration drawTime = Duration.zero;
  Duration readTime = Duration.zero;
  Duration decodeTime = Duration.zero;
  int readBytes = 0;

  Future<Object> _capture({
    required String name,
    required Duration timeout,
    bool raw = false,
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
      var watch = Stopwatch()..start();
      await send(CaptureMessage(path));
      failure = await done.future.timeout(timeout);
      drawTime += watch.elapsed;

      // `Object`, because it is whatever the socket handler was given — an
      // `ErrorMessage`'s text arrives wrapped in a StateError today, and this
      // rethrows what it was handed rather than reclassifying it.
      // ignore: only_throw_errors
      if (failure != null) throw failure;

      watch.reset();
      var bytes = file.readAsBytesSync();
      readTime += watch.elapsed;
      readBytes += bytes.length;

      // Decoded and handed back, and no further: framing a picture is
      // `catalog_picture.dart`'s, because it is the same work whichever engine
      // drew the frame.
      if (raw) return readRawFrame(bytes);
      watch.reset();
      var image = decodeRawFrame(bytes);
      decodeTime += watch.elapsed;
      return image;
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
