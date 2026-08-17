import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

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
