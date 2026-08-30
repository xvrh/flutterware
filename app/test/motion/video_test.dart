import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/motion/video.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  group('videoStops', () {
    test('covers both ends, so the clip shows what the motion starts from', () {
      var stops = videoStops(durationMs: 1000, fps: 30);
      expect(stops.first, 0);
      expect(stops.last, 1);
    });

    test('renders one frame per video frame, plus the closing one', () {
      // A second at 30fps is 30 intervals, and 31 frames bound them. Off by
      // one here and the clip plays a frame short of where it was authored to
      // land — invisible in a filmstrip, and exactly the kind of drift the
      // playhead law exists to prevent.
      expect(videoStops(durationMs: 1000, fps: 30), hasLength(31));
      expect(videoStops(durationMs: 500, fps: 60), hasLength(31));
      expect(videoStops(durationMs: 620, fps: 30), hasLength(20));
    });

    test('spaces stops evenly', () {
      var stops = videoStops(durationMs: 1000, fps: 4);
      expect(stops, [0, 0.25, 0.5, 0.75, 1]);
    });

    test('a motion too short for one frame still gets its two ends', () {
      // Rounding to zero frames would produce an empty stream, and an empty
      // stream is a refused encode rather than a very short video.
      expect(videoStops(durationMs: 5, fps: 30), [0, 1]);
      expect(videoStops(durationMs: 0, fps: 30), [0, 1]);
    });
  });

  group('VideoEncoder', () {
    late Directory scratch;

    setUp(() => scratch = Directory.systemTemp.createTempSync('fw-video'));
    tearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    test('writes a file a player can open', () async {
      var output = p.join(scratch.path, 'clip.mp4');
      var encoder = await VideoEncoder.start(
        output: output,
        width: 64,
        height: 48,
        fps: 10,
      );
      for (var i = 0; i < 10; i++) {
        encoder.add(_solid(64, 48, i * 25));
      }
      var file = await encoder.finish();

      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
      expect(encoder.frames, 10);
      // The container's own magic, so this asserts a real MP4 rather than
      // "ffmpeg exited 0" — which it also does for a zero-length file.
      expect(file.readAsBytesSync().sublist(4, 8), 'ftyp'.codeUnits);
    }, skip: _skipWithoutFfmpeg);

    test('refuses a frame that changes size mid-stream', () async {
      var encoder = await VideoEncoder.start(
        output: p.join(scratch.path, 'clip.mp4'),
        width: 64,
        height: 48,
        fps: 10,
      );
      encoder.add(_solid(64, 48, 0));
      // Raw video has no per-frame header, so a differently-sized frame is not
      // a resize — it is a stream that silently desynchronises from here on.
      expect(() => encoder.add(_solid(65, 48, 0)), throwsA(isA<StateError>()));
      await encoder.abort();
    }, skip: _skipWithoutFfmpeg);

    test('an aborted encode leaves no file', () async {
      var output = p.join(scratch.path, 'clip.mp4');
      var encoder = await VideoEncoder.start(
        output: output,
        width: 64,
        height: 48,
        fps: 10,
      );
      encoder.add(_solid(64, 48, 0));
      await encoder.abort();
      // A half-written video is worse than none: it opens, plays, and stops
      // somewhere the motion does not.
      expect(File(output).existsSync(), isFalse);
    }, skip: _skipWithoutFfmpeg);
  });
}

img.Image _solid(int width, int height, int grey) {
  var image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(grey, grey, grey, 255));
  return image;
}

/// `null` to run, a reason to skip — the encoder is a real process, and a
/// machine without `ffmpeg` should report that rather than fail.
final Object? _skipWithoutFfmpeg = _hasFfmpeg
    ? null
    : 'no `${VideoEncoder.executable}` on PATH';

bool get _hasFfmpeg {
  try {
    return Process.runSync(VideoEncoder.executable, ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
