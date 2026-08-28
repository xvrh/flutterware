import 'dart:async';
import 'dart:io';

import 'package:image/image.dart' as img;

/// Encodes a sequence of rendered frames into a video file, through `ffmpeg`.
///
/// Frames arrive as decoded images and leave as raw RGBA on the encoder's
/// stdin, so nothing is ever a PNG. That is not a micro-optimisation: a second
/// of motion is 30 frames, and PNG encoding was measured at ~7.5ms a picture
/// on top of a write and a read back — a third of a minute per minute of video
/// spent turning pixels into a format the encoder immediately undoes.
///
/// `ffmpeg` rather than a Dart encoder because there is no Dart H.264 encoder
/// worth the name, and because the one thing an export has to be is a file
/// somebody else's player opens. It is a hard dependency and says so: an
/// export that silently produced an unplayable file would be worse than one
/// that refuses.
class VideoEncoder {
  VideoEncoder._(this._process, this._errors, this.file, this.fps);

  /// Starts an encoder writing [output] at [fps], for frames of [width] by
  /// [height] physical pixels.
  ///
  /// The dimensions are fixed at start because raw video carries no header —
  /// the stream is nothing but pixels, and the encoder has to be told how to
  /// cut it into frames. A guest whose frame size changes mid-motion would
  /// therefore corrupt the stream rather than resize, which is why [add]
  /// checks rather than trusts.
  static Future<VideoEncoder> start({
    required String output,
    required int width,
    required int height,
    required int fps,
  }) async {
    var file = File(output);
    file.parent.createSync(recursive: true);
    if (file.existsSync()) file.deleteSync();

    Process process;
    try {
      process = await Process.start(executable, [
        '-hide_banner',
        '-loglevel', 'error',
        '-f', 'rawvideo',
        '-pix_fmt', 'rgba',
        '-s', '${width}x$height',
        '-r', '$fps',
        '-i', '-',
        '-c:v', 'libx264',
        // Even dimensions: yuv420p subsamples chroma 2×2, so an odd width
        // fails the encoder outright. Motion renders at a device's pixel
        // ratio, which makes odd sizes ordinary rather than exotic.
        '-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2',
        // The chroma format every player agrees on. libx264 defaults to
        // yuv444p for RGBA input, which QuickTime and most browsers refuse.
        '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart',
        output,
      ]);
    } on ProcessException catch (error) {
      throw StateError(
        'video export needs `$executable` on PATH, and starting it failed: '
        '${error.message}',
      );
    }

    // Drained rather than ignored: a process whose stderr fills its pipe
    // blocks on the write and the export hangs with no output.
    var errors = StringBuffer();
    unawaited(
      process.stderr.forEach(
        (chunk) => errors.write(String.fromCharCodes(chunk)),
      ),
    );
    unawaited(process.stdout.drain<void>());

    return VideoEncoder._(process, errors, file, fps);
  }

  static const executable = 'ffmpeg';

  final Process _process;
  final StringBuffer _errors;

  final File file;
  final int fps;

  /// How many frames have been handed over.
  int get frames => _frames;
  var _frames = 0;

  int? _width;
  int? _height;

  /// Hands one frame to the encoder.
  ///
  /// Frames go in playhead order and each one is one frame of output — the
  /// caller decides what `t` a frame was rendered at, which is what keeps
  /// [VideoEncoder] ignorant of motion and reusable by anything that renders a
  /// sequence.
  void add(img.Image frame) {
    _width ??= frame.width;
    _height ??= frame.height;
    if (frame.width != _width || frame.height != _height) {
      throw StateError(
        'frame ${_frames + 1} is ${frame.width}x${frame.height}, but the '
        'stream was opened at ${_width}x$_height — raw video carries no size, '
        'so a frame that changes it corrupts everything after it',
      );
    }
    _process.stdin.add(frame.getBytes(order: img.ChannelOrder.rgba));
    _frames++;
  }

  /// Closes the stream and waits for the file to be written.
  ///
  /// The exit code is read here rather than watched from [start], because an
  /// encoder that is [abort]ed exits non-zero *by design* — a watcher would
  /// turn every deliberate teardown into an unhandled error thrown into
  /// whatever zone happened to be running.
  Future<File> finish() async {
    if (_frames == 0) {
      _process.kill();
      await _process.exitCode;
      throw StateError('nothing was added, so there is no video to write');
    }
    // An encoder that already died leaves a broken pipe here. Its own
    // complaint is the useful one, so the close is allowed to fail quietly and
    // the exit code below speaks.
    try {
      await _process.stdin.close();
    } on Object {
      // Reported by the exit code.
    }
    var code = await _process.exitCode;
    if (code != 0) throw StateError('ffmpeg exited $code:\n$_errors');
    return file;
  }

  /// Ends the encode without producing a file — for a render that failed
  /// partway, where a truncated video is worse than none.
  Future<void> abort() async {
    _process.kill();
    await _process.exitCode;
    if (file.existsSync()) file.deleteSync();
  }
}

/// The playhead positions a motion of [durationMs] should be rendered at to
/// play back at [fps].
///
/// Both ends included, like a filmstrip's stops and for the same reason: the
/// first frame is what the motion starts from and the last is where it lands,
/// and a video missing either does not show the motion. That makes the clip
/// one frame longer than `duration × fps` — 31 frames for a second at 30fps —
/// which is the correct length for a motion that is played once rather than
/// looped.
List<double> videoStops({required int durationMs, required int fps}) {
  var count = (durationMs * fps / 1000).round() + 1;
  if (count < 2) return const [0, 1];
  return [for (var i = 0; i < count; i++) i / (count - 1)];
}
