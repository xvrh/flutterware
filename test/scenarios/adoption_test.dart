import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

/// When `screen` names the picture the verb before it took, and when it takes
/// one of its own.
///
/// The rule is a frame count: nothing drawn since the last capture means the
/// screen is still as that capture photographed it, so there is a name to put
/// on it and no second picture to take. Everything here is a reason that
/// answer is no.
void main() {
  var captures = <ScenarioStepCapture>[];
  setUp(() {
    captures = [];
    scenarioRunListener = captures.add;
  });
  tearDown(() => scenarioRunListener = null);

  List<String> shape() => [
    for (var capture in captures) capture.name ?? '${capture.verb}',
  ];

  group('a screen after a verb that settled', () {
    scenario('names that verb’s capture instead of taking another', (s) async {
      await s.pumpWidget(const _App());
      await s.tap('Add');
      await s.screen('Added');
    });
    tearDown(() {
      expect(shape(), ['pumpWidget', 'Added']);
      // The merged step keeps the verb that drew the frame, so a comparison
      // reads the strongest signature available and the weaker one too.
      expect(captures.last.verb, 'tap');
      expect(captures.last.target, '"Add"');
    });
  });

  group('a screen whose frame has moved on', () {
    scenario('takes a picture of its own', (s) async {
      await s.pumpWidget(const _App());
      await s.tap('Add');
      // Outside the verbs, so the flow has no picture of it — which is
      // precisely the case a name must not be allowed to swallow.
      await s.tester.tap(find.text('Add'));
      await s.tester.pump();
      await s.screen('Added twice');
    });
    tearDown(() {
      expect(shape(), ['pumpWidget', 'tap', 'Added twice']);
      expect(captures.last.verb, 'screen');
      expect(captures.last.strayFrames, greaterThan(0));
    });
  });

  group('a name never overwrites a name', () {
    scenario('so two screens on one frame stay two steps', (s) async {
      await s.pumpWidget(const _App());
      await s.screen('First');
      await s.screen('Second');
    });
    // The first adopts `pumpWidget`'s capture; the second finds a step that is
    // already named and takes its own picture rather than renaming it.
    tearDown(() => expect(shape(), ['First', 'Second']));
  });

  group('force declines the adoption outright', () {
    scenario('for a deliberate second picture of the same frame', (s) async {
      await s.pumpWidget(const _App());
      await s.screen('Home', force: true);
    });
    tearDown(() {
      expect(shape(), ['pumpWidget', 'Home']);
      expect(captures.last.verb, 'screen');
    });
  });

  group('a verb that never settled', () {
    scenario('keeps its own picture, and the screen takes another', (s) async {
      await s.pumpWidget(const _SpinnerApp());
      // A spinner is still turning when the settle gives up, so this frame is
      // one pump away from a different one — which is what the screen's own
      // settle is about to do.
      await s.tap('Start');
      await s.screen('Spinning');
    });
    tearDown(() {
      expect(captures[1].settled, isFalse);
      expect(shape(), ['pumpWidget', 'tap', 'Spinning']);
    });
  });

  group('a branch’s first screen', () {
    scenario('does not put its name on the step before the fork', (s) async {
      await s.pumpWidget(const _App());
      await s.split({
        'left': () => s.screen('Left'),
        'right': () => s.screen('Right'),
      });
    });
    // Three steps, and the shared one is still anonymous: `pumpWidget`'s
    // capture is on every path, and a name belonging to one branch has no
    // business on a step the others also show.
    tearDown(() {
      expect(shape(), ['pumpWidget', 'Left', 'Right']);
      expect(captures.first.name, isNull);
    });
  });

  group('an adopted step on a shared prefix', () {
    scenario('is recognised by the replay, not captured again', (s) async {
      await s.pumpWidget(const _App());
      await s.tap('Add');
      await s.screen('Added');
      await s.split({
        'left': () => s.screen('Left'),
        'right': () => s.screen('Right'),
      });
    });
    // The adoption is keyed like an emitted step, at the index it landed on,
    // so the second replay walks the same positions and recognises both of
    // them. Without that the replay would find nothing at the screen's
    // position and emit a fresh step for it, and the branches would hang off
    // different parents.
    tearDown(() {
      expect(shape(), ['pumpWidget', 'Added', 'Left', 'Right']);
      var merged = captures[1];
      expect(merged.verb, 'tap');
      expect(captures[2].parent, merged.index);
      expect(captures[3].parent, merged.index);
    });
  });

  group('a step whose shot was skipped', () {
    scenario('is not a frame a later screen may claim', (s) async {
      await s.pumpWidget(const _App());
      // Captures nothing, but draws: the frame the screen below would name is
      // no longer the one `pumpWidget` photographed.
      await s.tap('Add', shot: Shot.skip);
      await s.screen('Added');
    });
    tearDown(() => expect(shape(), ['pumpWidget', 'Added']));
  });

  group('a scenario that ends on an adopted screen', () {
    scenario('still hands its last step over', (s) async {
      await s.pumpWidget(const _App());
      await s.tap('Add');
      await s.screen('Added');
    });
    // The capture is held one step so this adoption can happen at all; nothing
    // follows it to force the hand-over, so the end of the body has to.
    tearDown(() {
      expect(captures, hasLength(2));
      expect(captures.last.name, 'Added');
    });
  });
}

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Count: $_count'),
            TextButton(
              onPressed: () => setState(() => _count++),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// An app that puts a spinner on screen and leaves it there — so the settle
/// policy gives up rather than finishing, and the step says so.
class _SpinnerApp extends StatefulWidget {
  const _SpinnerApp();

  @override
  State<_SpinnerApp> createState() => _SpinnerAppState();
}

class _SpinnerAppState extends State<_SpinnerApp> {
  var _busy = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: _busy
            ? const CircularProgressIndicator()
            : TextButton(
                onPressed: () => setState(() => _busy = true),
                child: const Text('Start'),
              ),
      ),
    ),
  );
}
