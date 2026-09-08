import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/film.dart';
import 'package:flutterware/src/scenarios/run_args.dart';

/// Rendering a scenario as a **film**: every pumped frame kept, the beats a
/// viewer needs pumped between the verbs, and a cursor drawn over the lot.
/// Design: `docs/superpowers/specs/2026-09-08-scenario-video-design.md`.
///
/// Like `motion_test.dart`, these tests stand in for the harness: they set the
/// run args the runner would set and read what landed on disk.
void main() {
  late Directory directory;

  void film(
    FilmSettings Function(String directory) settings, {
    ScenarioAssignment? on,
  }) {
    setUp(() {
      directory = Directory.systemTemp.createTempSync('fw-film');
      var args = ScenarioRunArgs(film: settings(directory.path));
      // `withDevice` is what the harness applies when a run names a device:
      // the geometry, the platform and the assignment the keyboard reads.
      scenarioRunArgs = on == null ? args : args.withDevice(on.device!);
    });
    tearDown(() {
      scenarioRunArgs = null;
      resetFilms();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  }

  group('a filmed scenario', () {
    film(
      (directory) => FilmSettings(
        directory: directory,
        fps: 30,
        scale: 1,
        // Short beats: the point of the assertions below is the shape of the
        // timeline, and a default-paced film of a two-verb scenario is 60
        // frames of holding still.
        open: const Duration(milliseconds: 100),
        travel: const Duration(milliseconds: 200),
        press: const Duration(milliseconds: 100),
        dwell: const Duration(milliseconds: 100),
        close: const Duration(milliseconds: 100),
      ),
    );

    scenario('writes a frame per pump, and a timeline for them', (s) async {
      await s.pumpWidget(const _App());
      await s.tap('Fade in');
    });

    tearDown(() {
      var film = _timeline(directory);
      var frames = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.raw'))
          .toList();
      expect(frames, hasLength(film['frames']));
      expect(film['frames'], greaterThan(20));
      expect(film['dropped'], isNull);
      // Every frame is whole: raw video carries no header, so a short file is
      // not a small frame, it is the rest of the clip sheared.
      var bytes = (film['width']! as int) * (film['height']! as int) * 4;
      for (var frame in frames) {
        expect(frame.lengthSync(), bytes, reason: frame.path);
      }
      // The default test view, at the film's scale.
      expect(film['width'], 800);
      expect(film['height'], 600);
      expect(film['fps'], 30);
      expect(film['pointer'], 'touch');
    });
  });

  group("a filmed scenario's beats", () {
    film(
      (directory) => FilmSettings(
        directory: directory,
        scale: 1,
        open: const Duration(milliseconds: 100),
        travel: const Duration(milliseconds: 200),
        press: const Duration(milliseconds: 100),
        dwell: const Duration(milliseconds: 100),
        close: const Duration(milliseconds: 100),
      ),
    );

    scenario('name every stretch of it, in order and without gaps', (s) async {
      await s.pumpWidget(const _App());
      await s.tap('Fade in');
    });

    tearDown(() {
      var beats = _beats(_timeline(directory));
      expect(
        [for (var beat in beats) beat['kind']],
        [
          // The app arrives and is held; the cursor flies to the button, rests
          // a moment over it and presses; the fade plays; the result is held;
          // the film ends on a hold rather than on the frame the verb landed
          // on.
          'act',
          'open',
          'travel',
          'aim',
          'press',
          'act',
          'dwell',
          'close',
        ],
      );
      expect(
        [for (var beat in beats) beat['verb']],
        ['pumpWidget', null, 'tap', 'tap', 'tap', 'tap', null, null],
      );
      // Contiguous: every frame of the film belongs to exactly one beat, so a
      // caption hung on a beat cannot fall in a gap between two of them.
      var next = 0;
      for (var beat in beats) {
        expect(beat['frame'], next, reason: '${beat['kind']}');
        next += beat['frames']! as int;
      }
      expect(next, _timeline(directory)['frames']);
      // 200ms of travel at 30fps — a full-height reach on this screen, so the
      // nominal — then the pause over the target and the press.
      expect(beats[2]['frames'], 6);
      expect(beats[3]['frames'], 4);
      expect(beats[4]['frames'], 3);
    });
  });

  group("a filmed verb's cursor", () {
    film((directory) => FilmSettings(directory: directory, scale: 1));

    scenario('flies to the target, presses it, and is drawn on the frame', (
      s,
    ) async {
      await s.pumpWidget(const _App());
      await s.tap('Fade in');
    });

    tearDown(() async {
      var timeline = _timeline(directory);
      var samples = [
        for (var sample in timeline['samples']! as List)
          sample as Map<String, Object?>,
      ];
      var travel = _beats(timeline).firstWhere((b) => b['kind'] == 'travel');
      var press = _beats(timeline).firstWhere((b) => b['kind'] == 'press');
      var during = [
        for (var sample in samples)
          if ((sample['frame']! as int) >= (travel['frame']! as int)) sample,
      ];
      expect(during, isNotEmpty);
      // Nothing before the first travel: a film that opens with a cursor
      // parked on the screen opens on a claim about a user who has not
      // arrived.
      expect(
        samples.first['frame'],
        travel['frame'],
        reason: 'the cursor exists only once a verb has somewhere to send it',
      );
      // It comes in from below the stage and climbs to the button, which is
      // above the middle of this app.
      expect(during.first['y']! as num, greaterThan(600));
      expect(during.last['y']! as num, lessThan(300));
      expect(during.first['down'], isNull);
      // Down for the press, and only there.
      var pressed = [
        for (var sample in samples)
          if (sample['down'] == true) sample['frame']! as int,
      ];
      expect(pressed.first, press['frame']);
      expect(pressed, hasLength(press['frames']));

      // And it is on the pixels. The app is black under the button and every
      // mark the cursor makes carries a light edge — that is how it survives a
      // dark screen as well as a light one — so a bright pixel near the
      // contact point is the cursor, and the frame before it arrived has none.
      var at = samples.firstWhere((s) => s['down'] == true);
      var x = (at['x']! as num).round();
      var y = (at['y']! as num).round();
      var width = timeline['width']! as int;
      expect(
        _bright(_frame(directory, at['frame']! as int), width, x, y),
        isTrue,
        reason: 'the cursor is drawn on the frame it is pressing',
      );
      expect(
        _bright(_frame(directory, 0), width, x, y),
        isFalse,
        reason: 'and the app under it is dark',
      );
    });
  });

  group('a filmed long press', () {
    film(
      (directory) => FilmSettings(
        directory: directory,
        scale: 1,
        open: const Duration(milliseconds: 100),
        travel: const Duration(milliseconds: 100),
        press: const Duration(milliseconds: 100),
        dwell: const Duration(milliseconds: 100),
        close: const Duration(milliseconds: 100),
      ),
    );

    scenario('is held long enough to read as one', (s) async {
      await s.pumpWidget(const _App());
      await s.longPress('Fade in');
    });

    tearDown(() {
      var beats = _beats(_timeline(directory));
      var press = beats.firstWhere((beat) => beat['kind'] == 'press');
      // `tester.longPress` spends no fake time at all, so a film that took the
      // beat at its word would show a tap. 550ms at 30fps is 17 frames; the
      // 100ms beat above would have been 3.
      expect(press['frames'], 17);
      expect(press['verb'], 'longPress');
    });
  });

  // What the drag carried, filled by the scenario below and read by the plain
  // widget test after it — the two halves of one comparison.
  var carried = <double>[];

  group('a filmed drag', () {
    var controller = ScrollController();
    film(
      (directory) => FilmSettings(
        directory: directory,
        scale: 1,
        open: const Duration(milliseconds: 100),
        travel: const Duration(milliseconds: 100),
        press: const Duration(milliseconds: 100),
        dwell: const Duration(milliseconds: 100),
        close: const Duration(milliseconds: 100),
      ),
    );

    scenario('moves the finger frame by frame', (s) async {
      await s.pumpWidget(_ScrollApp(controller));
      await s.drag(find.byType(ListView), const Offset(0, -300));
      carried.add(controller.offset);
    });

    tearDown(() {
      var timeline = _timeline(directory);
      var drag = _beats(timeline).firstWhere((beat) => beat['kind'] == 'drag');
      // A scenario's own drag dispatches down, move and up with no frames
      // between them, so a film of it shows a list that teleports.
      expect(drag['frames']! as int, greaterThan(10));
      // From the frame the finger went down on — the drag's own first frame
      // has already moved a little, which is the point.
      var during = [
        for (var sample in timeline['samples']! as List)
          if (((sample as Map)['frame']! as int) >= (drag['frame']! as int) - 1)
            (sample['y']! as num).toDouble(),
      ];
      // The finger travels with the frames rather than ahead of them, and it
      // travels the whole way.
      expect(during.first - during.last, closeTo(300, 0.01));
      // And it rests before it lifts, which is what keeps the list from
      // flinging past where the suite's own drag leaves it.
      expect(during.sublist(during.length - 4).toSet(), hasLength(1));
    });
  });

  testWidgets("a filmed drag lands where the suite's own drag lands", (
    tester,
  ) async {
    var controller = ScrollController();
    await tester.pumpWidget(_ScrollApp(controller));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // The property this rests on, and the reason the film holds the finger
    // still before it lifts: a drag spread over frames has *velocity*, and a
    // list that flings past where the suite left it is a film of a different
    // app — one whose next assertion may not hold.
    expect(controller.offset, 300);
    expect(carried.single, closeTo(controller.offset, 0.5));
  });

  // Where the filmed scroll left the list, against where the suite's own walk
  // leaves it.
  var scrolled = <double>[];

  group('a filmed scroll', () {
    var controller = ScrollController();
    film(
      (directory) => FilmSettings(
        directory: directory,
        scale: 1,
        open: const Duration(milliseconds: 100),
        travel: const Duration(milliseconds: 100),
        press: const Duration(milliseconds: 100),
        dwell: const Duration(milliseconds: 100),
        close: const Duration(milliseconds: 100),
      ),
    );

    scenario('walks the list with a thumb', (s) async {
      await s.pumpWidget(_ScrollApp(controller));
      await s.scrollTo('Row 40');
      scrolled.add(controller.offset);
    });

    tearDown(() {
      var timeline = _timeline(directory);
      var beats = _beats(timeline);
      var swipes = [
        for (var beat in beats)
          if (beat['kind'] == 'swipe') beat,
      ];
      // A list that scrolls itself is the one thing in a reel that reads as a
      // bug rather than as a user: one swipe per iteration of the walk, each
      // one a drag the finger is on.
      expect(swipes, isNotEmpty);
      expect(swipes.first['verb'], 'scrollTo');
      var down = [
        for (var sample in timeline['samples']! as List)
          if ((sample as Map)['down'] == true) (sample['y']! as num).toDouble(),
      ];
      expect(down, isNotEmpty);
      // The finger travels while it is down — it is the finger that moves the
      // list, not the other way round.
      expect(
        down.reduce((a, b) => a > b ? a : b) -
            down.reduce((a, b) => a < b ? a : b),
        greaterThan(100),
      );
    });
  });

  testWidgets("a filmed scroll lands where the suite's own walk lands", (
    tester,
  ) async {
    var controller = ScrollController();
    await tester.pumpWidget(_ScrollApp(controller));
    await tester.scrollUntilVisible(find.text('Row 40'), 200);
    await tester.pumpAndSettle();

    // Same walk, same step, same stopping condition, same tail — so the film
    // stops on the same iteration and the list ends where the suite's does.
    expect(scrolled.single, closeTo(controller.offset, 0.5));
  });

  group('filmed typing', () {
    film(
      (directory) => FilmSettings(
        directory: directory,
        scale: 1,
        open: const Duration(milliseconds: 100),
        travel: const Duration(milliseconds: 100),
        press: const Duration(milliseconds: 100),
        dwell: const Duration(milliseconds: 100),
        close: const Duration(milliseconds: 100),
      ),
    );

    scenario('goes in a character at a time', (s) async {
      await s.pumpWidget(const _FormApp());
      await s.enterText(TextField, 'hello world');
      expect(find.text('hello world'), findsOneWidget);
    });

    tearDown(() {
      var typing = _beats(_timeline(directory))
          .firstWhere((beat) => beat['kind'] == 'type');
      expect(typing['verb'], 'enterText');
      // `enterText` spends no fake time of its own, so every one of these
      // frames is the film's: ten characters at three frames each, and five
      // for the word gap.
      expect(typing['frames'], 35);
      expect(typing['target'], 'hello world');
    });
  });

  group('filmed typing on a phone', () {
    film(
      (directory) => FilmSettings(
        directory: directory,
        scale: 1,
        open: const Duration(milliseconds: 100),
        travel: const Duration(milliseconds: 100),
        press: const Duration(milliseconds: 100),
        dwell: const Duration(milliseconds: 100),
        close: const Duration(milliseconds: 100),
      ),
      on: const ScenarioAssignment(device: Devices.iphone16),
    );

    scenario('waits for the keyboard before the words appear', (s) async {
      await s.pumpWidget(const _FormApp());
      await s.enterText(TextField, 'hi');
    });

    tearDown(() {
      var beats = _beats(_timeline(directory));
      var kinds = [for (var beat in beats) beat['kind']];
      // The order nothing does: type into a screen with no keyboard on it and
      // raise one afterwards. The focus beat is where the slab slides up, and
      // its frames exist because something was animating through them.
      expect(kinds.indexOf('focus'), lessThan(kinds.indexOf('type')));
      var focus = beats.firstWhere((beat) => beat['kind'] == 'focus');
      expect(focus['frames']! as int, greaterThan(3));
    });
  });

  group('a filmed scenario that splits', () {
    film((directory) => FilmSettings(directory: directory, scale: 1));

    scenario('refuses a branch it was not given', (s) async {
      await s.pumpWidget(const _App());
      await expectLater(
        s.split({
          'fades in': () async => s.tap('Fade in'),
          'stays put': () async => s.screen('Still'),
        }),
        throwsA(
          isA<ScenarioFilmRefusal>().having(
            (refusal) => refusal.message,
            'message',
            allOf(
              contains('`fades in` and `stays put`'),
              contains("--branch='fades in'"),
            ),
          ),
        ),
      );
    });
  });

  group('a filmed scenario given its branch', () {
    film(
      (directory) =>
          FilmSettings(directory: directory, scale: 1, branches: ['stays put']),
    );

    var walked = <String>[];
    scenario('walks that one, once', (s) async {
      await s.pumpWidget(const _App());
      await s.split({
        'fades in': () async {
          walked.add('fades in');
          await s.tap('Fade in');
        },
        'stays put': () async {
          walked.add('stays put');
          await s.screen('Still');
        },
      });
    });

    tearDown(() {
      // One path, not both, and not the first by default: a suite wants every
      // branch and a film wants the one worth watching.
      expect(walked, ['stays put']);
      walked = [];
    });
  });

  group('a film that runs long', () {
    film(
      (directory) =>
          FilmSettings(directory: directory, scale: 1, maxFrames: 12),
    );

    scenario('is cut, and says so', (s) async {
      await s.pumpWidget(const _App());
      await s.tap('Fade in');
    });

    tearDown(() {
      var timeline = _timeline(directory);
      expect(timeline['frames'], 12);
      // Reported rather than swallowed: a clip that stops early is not a
      // scenario that ended there.
      expect(timeline['dropped']! as int, greaterThan(0));
    });
  });
}

Map<String, Object?> _timeline(Directory directory) => jsonDecode(
  File('${directory.path}/${ScenarioFilm.timelineFileName}').readAsStringSync(),
) as Map<String, Object?>;

List<Map<String, Object?>> _beats(Map<String, Object?> timeline) => [
  for (var beat in timeline['beats']! as List) beat as Map<String, Object?>,
];

Uint8List _frame(Directory directory, int index) =>
    File('${directory.path}/${'$index'.padLeft(6, '0')}.raw').readAsBytesSync();

/// Whether anything within the cursor's own reach of a point is close to
/// white — which on this scenario's black screen means the cursor is there.
///
/// A box rather than a pixel, and a threshold rather than a colour: the mark's
/// radius, its ring width and its fill are a *look*, and a test that pinned
/// them would fail every time the look improved.
bool _bright(Uint8List frame, int width, int x, int y) {
  for (var dy = -26; dy <= 26; dy++) {
    for (var dx = -26; dx <= 26; dx++) {
      var at = ((y + dy) * width + (x + dx)) * 4;
      if (at < 0 || at + 2 >= frame.length) continue;
      if (frame[at] > 0xC0 && frame[at + 1] > 0xC0 && frame[at + 2] > 0xC0) {
        return true;
      }
    }
  }
  return false;
}

class _FormApp extends StatelessWidget {
  const _FormApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Padding(padding: EdgeInsets.all(40), child: TextField()),
    ),
  );
}

class _ScrollApp extends StatelessWidget {
  const _ScrollApp(this.controller);

  final ScrollController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ListView.builder(
        controller: controller,
        itemCount: 200,
        itemExtent: 60,
        itemBuilder: (context, index) => Text('Row $index'),
      ),
    ),
  );
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () {}, child: const Text('Fade in')),
            const SizedBox(height: 200),
          ],
        ),
      ),
    ),
  );
}
