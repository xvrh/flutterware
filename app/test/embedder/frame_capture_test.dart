import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware_app/src/embedder/frame_capture.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The capture exchange, without a guest.
///
/// Worth testing here rather than only end to end: this is what the headless
/// pipeline and the GUI's live engine now share, and the GUI half is the one no
/// harness reaches — a panel's capture needs a window, a Metal device and
/// somebody to have clicked something. What the two halves have in common is
/// this handshake, and it is all reachable with a fake guest.
///
/// Writes a real file because that is what the protocol is: the guest is asked
/// by path and answers with the path when the bytes have landed.
Uint8List _rawFrame(int width, int height, {int? rowBytes}) {
  var stride = rowBytes ?? width * 4;
  var header = ByteData(16)
    ..setUint32(0, width, Endian.little)
    ..setUint32(4, height, Endian.little)
    ..setUint32(8, stride, Endian.little)
    ..setUint32(12, 0, Endian.little); // BGRA, as the Metal ring writes
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        // Opaque white, so an annotation's magenta is visible against it.
        ..add(List.filled(stride * height, 255)))
      .toBytes();
}

void main() {
  late Directory work;

  setUp(() {
    work = Directory.systemTemp.createTempSync('fw_frame_capture_test');
  });

  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  /// A guest that writes [frame] where it is told and acknowledges it.
  FrameCapture obliging({Uint8List? frame, int width = 4, int height = 3}) {
    late FrameCapture capture;
    capture = FrameCapture(
      workDir: p.join(work.path, 'cap'),
      send: (message) async {
        var path = (message as CaptureMessage).path;
        File(path).writeAsBytesSync(frame ?? _rawFrame(width, height));
        capture.acknowledge(CapturedMessage(path));
      },
    );
    return capture;
  }

  test('the frame it was handed is the picture it returns', () async {
    var image = await obliging(width: 4, height: 3).capture();

    expect(image.width, 4);
    expect(image.height, 3);
  });

  test('the scratch file does not survive the read', () async {
    var capture = obliging();
    await capture.capture(name: 'shot');

    // Tens of megabytes per frame. One left behind is also one a later capture
    // could decode as its own answer if the guest never replied.
    expect(
      File(p.join(work.path, 'cap', 'shot.rawframe')).existsSync(),
      isFalse,
    );
  });

  test(
    'a stale file from a timed-out capture is not read as this one',
    () async {
      var dir = Directory(p.join(work.path, 'cap'))
        ..createSync(recursive: true);
      // A 9x9 frame nobody asked for, left by an earlier attempt.
      File(p.join(dir.path, 'screenshot.rawframe'))
          .writeAsBytesSync(_rawFrame(9, 9));

      var image = await obliging(width: 4, height: 3).capture();

      expect(image.width, 4, reason: 'the stale 9x9 frame should be gone');
    },
  );

  test('a guest that reports an error fails the capture with it', () async {
    late FrameCapture capture;
    capture = FrameCapture(
      workDir: p.join(work.path, 'cap'),
      send: (_) async => capture.failAll(StateError('the demo blew up')),
    );

    // Rather than leaving the caller on the 30-second timeout to be told less.
    await expectLater(
      capture.capture(timeout: const Duration(seconds: 30)),
      throwsA(isA<StateError>()),
    );
  });

  test('a guest that never answers times out rather than hanging', () async {
    var capture = FrameCapture(
      workDir: p.join(work.path, 'cap'),
      send: (_) async {},
    );

    await expectLater(
      capture.capture(timeout: const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('an ack for another path settles nothing', () async {
    var capture = FrameCapture(
      workDir: p.join(work.path, 'cap'),
      send: (_) async {},
    );
    var pending = capture.capture(timeout: const Duration(milliseconds: 200));

    // Two captures can be outstanding on one guest — a panel open while an
    // agent screenshots — so an ack settles the one it names and no other.
    expect(
      capture.acknowledge(const CapturedMessage('/somewhere/else')),
      isTrue,
    );

    await expectLater(pending, throwsA(isA<TimeoutException>()));
  });

  test('overlapping captures run one after the other', () async {
    // The host keeps one armed capture path and `free`s the previous one, so a
    // second request in flight replaces the first and the first frame is never
    // written. Both the copy button and its shortcut can ask, so the ordering
    // has to be enforced here rather than by every caller remembering.
    var armed = <String>[];
    late FrameCapture capture;
    capture = FrameCapture(
      workDir: p.join(work.path, 'cap'),
      send: (message) async {
        var path = (message as CaptureMessage).path;
        armed.add(path);
        // A frame takes a moment to arrive; the point is what happens meanwhile.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        File(path).writeAsBytesSync(_rawFrame(4, 3));
        capture.acknowledge(CapturedMessage(path));
      },
    );

    var both = await Future.wait([capture.capture(), capture.capture()]);

    // Unserialised, the second `send` armed its path while the first was still
    // waiting, and the first timed out after thirty seconds.
    expect(armed, hasLength(2));
    expect(both.every((image) => image.width == 4), isTrue);
  });

  test('a failed capture does not poison the one behind it', () async {
    var attempt = 0;
    late FrameCapture capture;
    capture = FrameCapture(
      workDir: p.join(work.path, 'cap'),
      send: (message) async {
        var path = (message as CaptureMessage).path;
        if (attempt++ == 0) {
          capture.failAll(StateError('the demo blew up'));
          return;
        }
        File(path).writeAsBytesSync(_rawFrame(4, 3));
        capture.acknowledge(CapturedMessage(path));
      },
    );

    var first = capture.capture();
    var second = capture.capture();

    await expectLater(first, throwsA(isA<StateError>()));
    // The queue carries order, not failure: one bad capture must not fail every
    // capture after it.
    expect((await second).width, 4);
  });

  test('the scratch file is gone after a failure too', () async {
    var capture = FrameCapture(
      workDir: p.join(work.path, 'cap'),
      // Writes the frame and never acks, which is what a guest that stopped
      // drawing looks like.
      send: (message) async =>
          File((message as CaptureMessage).path)
              .writeAsBytesSync(_rawFrame(64, 64)),
    );

    await expectLater(
      capture.capture(timeout: const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );

    // Tens of megabytes uncompressed. Deleted only on the success path, it
    // stayed until some later capture happened to reuse the same name.
    expect(
      File(p.join(work.path, 'cap', 'screenshot.rawframe')).existsSync(),
      isFalse,
    );
  });

  test('anything that is not an ack is left for the caller to handle', () {
    var capture = FrameCapture(
      workDir: p.join(work.path, 'cap'),
      send: (_) async {},
    );

    // Both engines offer this every message they read, so it has to say plainly
    // which ones it took.
    expect(capture.acknowledge(const ReadyMessage()), isFalse);
    expect(capture.acknowledge(const ErrorMessage('boom')), isFalse);
  });
}
