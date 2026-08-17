import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/motion.dart';
import 'package:flutterware/src/scenarios/run_args.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

import 'raster_fixture.dart';

/// A widget whose *paint* depends on work that resolves on the real event
/// loop, mounted mid-scenario — and the step that photographs it.
///
/// `vector_graphics` is the instance this was found through: a consumer's
/// scenario captured every screen as it arrived and every one of them was
/// missing its illustration, one step late. But nothing here is about SVG.
/// Lottie, a PDF or thumbnail renderer, an `ImageProvider` decoding off the
/// fake clock and a `FutureBuilder` on a real future all have the same shape —
/// a decode that finishes on the **real** event loop and schedules no frame
/// while it is in flight.
///
/// The work is a root-zone timer rather than an asset read on purpose. Under a
/// bare `flutter test` an asset read is not real-loop work at all:
/// `UNIT_TEST_ASSETS` makes `flutter_test` answer `flutter/assets` from a
/// `readAsBytesSync`, so it completes under FakeAsync and this file would be
/// green while the runner's lane — which spawns `flutter_tester` directly and
/// gets the engine's answer — stayed red. `Zone.root` is the one spelling of
/// "off the fake clock" that both lanes agree on.
void main() {
  var captures = <ScenarioStepCapture>[];
  setUp(() {
    captures = [];
    scenarioRunListener = captures.add;
  });
  tearDown(() => scenarioRunListener = null);

  scenario('the step that mounts the artwork is the step that shows it', (
    s,
  ) async {
    await s.pumpWidget(const _App());
    await s.tap('Show');
    await s.screen('one step later');

    var mounting = captures[captures.length - 2];
    var after = captures.last;
    // Byte-identical, because there is nothing left for the next step to add.
    // Before this, the mounting step photographed a frame the tree was about to
    // replace: the decode landed inside the capture's own `runAsync` — which is
    // why one more step always fixed it and more pumping inside the step never
    // did.
    expect(mounting.bytes, after.bytes);
  });

  scenario('nothing a scenario can assert says the picture is short', (
    s,
  ) async {
    await s.pumpWidget(const _App());
    await s.tap('Show');

    // The trap, and why this cost a consumer an afternoon: every one of these
    // was already true on the step whose picture was missing the artwork. Only
    // the pixels differed, and nothing was watching them.
    expect(find.byType(_Art), findsOneWidget);
    expect(captures.last.settled, isTrue);
    expect(captures.last.strayFrames, 0);
  });

  // The same shape with an `ImageProvider` on the end of it — the half of the
  // class the timer above does not cover, and the half a consumer hit next.
  //
  // **Size is the discriminator, and a counted bound is why.** The decode is
  // the same code either way; what differs is how long it runs, and a turn of
  // the real loop is not a wait — it yields once while the engine's decoder
  // works on another thread. So the old twelve-turn ceiling was really
  // "however much wall time twelve yields happen to cost here", and the payload
  // that fits under it is a property of the machine. Measured under it: 8×8 and
  // 780×609 land, 1500×1200 does not, and a bigger image only moves that line.
  // Both ends are here so a fix that merely buys headroom fails the large one,
  // and one that reintroduces the cliff further out fails both on a slower
  // machine.
  for (var (label, width, height) in [
    ('8×8', 8, 8),
    ('2400×1800', 2400, 1800),
  ]) {
    scenario('a $label image lands on the step that mounts it', (s) async {
      var bytes = rasterFixture(width, height);
      await s.pumpWidget(_ImageApp(bytes));
      await s.tap('Show');
      await s.screen('one step later');

      var mounting = captures[captures.length - 2];
      var after = captures.last;
      expect(mounting.bytes, after.bytes);
      // `pendingImageCount` is what was waited on, so a step that gave up says
      // so — the whole point of the flag is that this cannot go wrong quietly.
      expect(mounting.landed, isTrue);
    });
  }

  // **A still that is right does not make the movie behind it right**, and the
  // difference is what a reader actually looks at: the recording is what the
  // GUI plays when you hover a step.
  //
  // A landing that happens *after* the settle loop puts the artwork in the last
  // frame and no earlier one. Measured before this: a tap whose ripple runs 21
  // recorded frames produced `[0, 0, 0, …, 0, present]` — one frame of artwork
  // at the very end of a movie that is otherwise a hole, which plays as never
  // having decoded at all. Fake time is why the app never catches up: a
  // transition of several hundred fake milliseconds is spent in a few real
  // ones, so a decode a device would have finished inside the first frame
  // cannot finish inside any of them.
  //
  // So the frames are counted, not compared. Two captures that are both missing
  // the artwork are equal, and the equality assertion this replaces was passing
  // on exactly that.
  group('the transition, recorded', () {
    setUp(() {
      scenarioRunArgs = const ScenarioRunArgs(
        captureRaw: true,
        record: MotionRecording(
          interval: Duration(milliseconds: 33),
          scale: 0.5,
        ),
      );
    });
    tearDown(() => scenarioRunArgs = null);

    scenario('carries the image, not just the frame it ends on', (s) async {
      await s.pumpWidget(_ImageApp(solidRed(400, 400)));
      await s.tap('Show');
      await s.screen('one step later');

      var motion = captures[1].motion;
      var blank = motion.bytes.where((frame) => _redPixels(frame) == 0);
      expect(motion.bytes, hasLength(greaterThan(10)));
      // Two frames legitimately have no artwork and no more: the screen as it
      // stood before the tap, banked so the movie opens on where it came from,
      // and the pump that mounts the widget — which is where the decode starts,
      // so no frame drawn at that instant could show it.
      expect(blank, hasLength(2));
      expect(_redPixels(motion.bytes.last), greaterThan(0));
    });
  });

  scenario('a decode that never arrives is reported, not waited on forever', (
    s,
  ) async {
    await s.pumpWidget(const _ImageApp.provider(_NeverDecodes()));
    await s.tap('Show');

    // The one case the ceiling exists for. It is still photographed — a picture
    // of a screen that never filled in is the evidence — but it no longer
    // claims to be finished.
    expect(captures.last.landed, isFalse);
    expect(captures.last.settled, isTrue);
  });
}

/// Pixels close to pure red in an rgba8888 frame — "is the artwork in this
/// picture", asked of a fixture chosen so that counting answers it.
int _redPixels(Uint8List raw) {
  var found = 0;
  for (var i = 0; i + 3 < raw.length; i += 4) {
    if (raw[i] > 200 &&
        raw[i + 1] < 60 &&
        raw[i + 2] < 60 &&
        raw[i + 3] > 200) {
      found++;
    }
  }
  return found;
}

/// An `ImageProvider` whose codec never arrives — `pendingImageCount` stays at
/// one for as long as anybody is willing to wait.
class _NeverDecodes extends ImageProvider<_NeverDecodes> {
  const _NeverDecodes();

  @override
  Future<_NeverDecodes> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_NeverDecodes key, ImageDecoderCallback _) =>
      MultiFrameImageStreamCompleter(
        codec: Completer<Codec>().future,
        scale: 1,
      );

  @override
  bool operator ==(Object other) => other is _NeverDecodes;

  @override
  int get hashCode => (_NeverDecodes).hashCode;
}

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  var _shown = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _shown = true),
            child: const Text('Show'),
          ),
          if (_shown) const Expanded(child: _Art()),
        ],
      ),
    ),
  );
}

/// The same app with an `Image.memory` in place of [_Art] — mounted a step
/// after `pumpWidget`, because `pumpWidget` already takes a real turn for boot
/// and lands whatever the first frame asked for.
class _ImageApp extends StatefulWidget {
  _ImageApp(Uint8List bytes) : image = MemoryImage(bytes);

  const _ImageApp.provider(this.image);

  final ImageProvider image;

  @override
  State<_ImageApp> createState() => _ImageAppState();
}

class _ImageAppState extends State<_ImageApp> {
  var _shown = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _shown = true),
            child: const Text('Show'),
          ),
          if (_shown) Image(image: widget.image, width: 200, height: 200),
        ],
      ),
    ),
  );
}

/// Paints nothing until a real-loop future hands it something to paint.
class _Art extends StatefulWidget {
  const _Art();

  @override
  State<_Art> createState() => _ArtState();
}

class _ArtState extends State<_Art> {
  Color? _decoded;

  @override
  void initState() {
    super.initState();
    // Root zone, so the timer is a real one: nothing FakeAsync flushes can
    // complete it, and it schedules no frame while it is in flight.
    Zone.root
        .run(() => Future<Color>.delayed(Duration.zero, () => Colors.red))
        .then((color) {
          if (mounted) setState(() => _decoded = color);
        });
  }

  @override
  Widget build(BuildContext context) =>
      _decoded == null ? const SizedBox.expand() : ColoredBox(color: _decoded!);
}
