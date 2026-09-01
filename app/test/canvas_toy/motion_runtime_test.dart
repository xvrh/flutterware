import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/canvas_toy/main.dart';
import 'package:flutterware_app/canvas_toy/model.dart';
import 'package:flutterware_app/canvas_toy/motion_file.dart';
import 'package:flutterware_app/canvas_toy/motion_model.dart';
import 'package:flutterware_app/canvas_toy/motion_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the grammar and the runtime agree on the curve allowlist', () {
    expect(motionCurveObjects.keys.toSet(), motionCurves.toSet());
  });

  group('track evaluation', () {
    var track = MotionTrack(TrackKind.number, [
      MotionKey(at: Duration.zero, value: 0.0),
      MotionKey(
        at: const Duration(milliseconds: 400),
        value: 1.0,
        curve: 'easeOut',
      ),
    ]);

    test('the hold rule at both edges', () {
      expect(track.evaluate(const Duration(milliseconds: -50)), 0.0);
      expect(track.evaluate(Duration.zero), 0.0);
      expect(track.evaluate(const Duration(milliseconds: 400)), 1.0);
      expect(track.evaluate(const Duration(seconds: 9)), 1.0);
    });

    test('the curve rides the arriving key', () {
      var mid = track.evaluate(const Duration(milliseconds: 200)) as double;
      expect(mid, Curves.easeOut.transform(0.5));
      expect(mid, isNot(0.5));
    });

    test('a color track lerps through Color.lerp', () {
      var colors = MotionTrack(TrackKind.color, [
        MotionKey(at: Duration.zero, value: const Color(0xFF000000)),
        MotionKey(
          at: const Duration(milliseconds: 100),
          value: const Color(0xFFFFFFFF),
        ),
      ]);
      var mid = colors.evaluate(const Duration(milliseconds: 50));
      expect(
        mid,
        Color.lerp(const Color(0xFF000000), const Color(0xFFFFFFFF), 0.5),
      );
    });

    test('an empty track refuses to evaluate', () {
      expect(
        () => MotionTrack(TrackKind.number).evaluate(Duration.zero),
        throwsStateError,
      );
    });
  });

  group('the fx plane composes over the live base', () {
    test(
      'operators: opacity multiplies, translate adds, fontSize replaces',
      () {
        var node = TextNode('t', 'hi')..opacity = 0.8;
        Object writer1 = 'w1', writer2 = 'w2';
        node.writeFx(writer1, 'opacity', 0.5);
        node.writeFx(writer2, 'opacity', 0.5);
        expect(node.fxRendered('opacity'), closeTo(0.2, 1e-9));
        node.writeFx(writer1, 'translateY', 10.0);
        node.writeFx(writer2, 'translateY', -4.0);
        expect(node.fxRendered('translateY'), 6.0);
        node.writeFx(writer1, 'fontSize', 30.0);
        expect(node.fxRendered('fontSize'), 30.0);
      },
    );

    test('the base is read live: an authored mutation composes next read', () {
      var node = ShapeNode('s')..opacity = 0.8;
      node.writeFx('m', 'opacity', 0.5);
      expect(node.fxRendered('opacity'), closeTo(0.4, 1e-9));
      node.opacity = 0.4; // the app retunes mid-flight
      expect(node.fxRendered('opacity'), closeTo(0.2, 1e-9));
    });

    test('effect handles are independent writers', () {
      var node = ShapeNode('s');
      var hover = node.effect()..scale = 1.04;
      var press = node.effect()..scale = 0.96;
      node.writeFx('motion', 'scale', 1.2);
      expect(node.fxRendered('scale'), closeTo(1.2 * 1.04 * 0.96, 1e-9));
      press.clear();
      expect(node.fxRendered('scale'), closeTo(1.2 * 1.04, 1e-9));
      hover.scale = null;
      expect(node.fxRendered('scale'), closeTo(1.2, 1e-9));
    });

    test('a writer keeps its stack position through re-writes', () {
      var node = ShapeNode('s');
      var a = node.effect()..opacity = 0.5;
      var b = node.effect()..opacity = 0.8;
      a.opacity = 0.6;
      expect(a.opacity, 0.6); // a handle reads back its own contribution
      expect(b.opacity, 0.8);
      expect(
        node.fx.keys.map(
          (k) => identical(k.$1, a)
              ? 'a'
              : identical(k.$1, b)
              ? 'b'
              : '?',
        ),
        ['a', 'b'],
      );
    });

    test('an ext node folds arg contributions into renderedArgs', () {
      var node = ExternalNode('e', 'DrinkBadge', args: {'size': 140.0});
      node.writeFx('m', 'args.progress', 0.5);
      expect(node.renderedArgs, {'size': 140.0, 'progress': 0.5});
      expect(node.args, {'size': 140.0}); // authored untouched
    });
  });

  group('the bound pair', () {
    test('the coffee intro plays over the coffee banner', () {
      var scene = coffeeBannerDraft();
      var bound = BoundMotion.bind(coffeeIntroDraft(), scene);
      expect(bound.duration, const Duration(milliseconds: 1800));

      var headline = scene.nodeNamed('headline')!;
      var badge = scene.nodeNamed('badge')! as ExternalNode;
      var glow = scene.nodeNamed('glow')!;

      bound.apply(Duration.zero);
      expect(headline.fxRendered('opacity'), 0.0);
      expect(headline.fxRendered('translateY'), 24.0);
      // badgePop sits behind At(400.ms): its window has not opened.
      expect(badge.fxRendered('scale'), 0.6);

      bound.apply(const Duration(milliseconds: 130));
      expect(headline.fxRendered('opacity'), Curves.easeOut.transform(0.5));

      bound.apply(const Duration(milliseconds: 700));
      expect(headline.fxRendered('opacity'), 1.0);
      expect(badge.fxRendered('scale'), 1.0); // local 300, track ended at 240
      expect(badge.renderedArgs['progress'], 1.0);

      bound.apply(const Duration(milliseconds: 900));
      // glow's authored opacity is 0.7; the mood dims it to 0.85 of that.
      expect(glow.fxRendered('opacity'), closeTo(0.7 * 0.85, 1e-9));

      // Backwards seek is pure.
      bound.apply(Duration.zero);
      expect(headline.fxRendered('opacity'), 0.0);

      // Cancel: fx drops, authored untouched.
      bound.clearFx();
      expect(headline.fx, isEmpty);
      expect(headline.fxRendered('opacity'), 1.0);
    });

    test('an unplaced group plays independently', () {
      var scene = coffeeBannerDraft();
      var bound = BoundMotion.bind(coffeeIntroDraft(), scene);
      var cta = scene.nodeNamed('cta')!;
      var headline = scene.nodeNamed('headline')!;

      bound.group('tapPulse').apply(const Duration(milliseconds: 120));
      expect(cta.fxRendered('scale'), 1.06);
      expect(headline.fx, isEmpty); // the timeline never played

      // And the timeline never plays the asset: apply leaves it at its
      // last written value only because we wrote it ourselves.
      expect(() => bound.group('ghost'), throwsArgumentError);
    });

    test('binding against a scene missing the target refuses, named', () {
      var scene = SceneDocument(FrameNode('root'));
      expect(
        () => BoundMotion.bind(coffeeIntroDraft(), scene),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('"headline"'),
          ),
        ),
      );
    });
  });

  group('combinators are pure time transforms', () {
    (SceneDocument, MotionDocument) pair(TimelineExpr Function() timeline) {
      var scene = coffeeBannerDraft();
      var doc = MotionDocument(sceneClassName: 'BannerScene');
      var a = AnimateGroup('a', 'glow');
      a.tracks['opacity'] = MotionTrack(TrackKind.number, [
        MotionKey(at: Duration.zero, value: 0.0),
        MotionKey(at: const Duration(milliseconds: 200), value: 1.0),
      ]);
      var b = AnimateGroup('b', 'cup');
      b.tracks['opacity'] = MotionTrack(TrackKind.number, [
        MotionKey(at: Duration.zero, value: 1.0),
        MotionKey(at: const Duration(milliseconds: 300), value: 0.0),
      ]);
      doc.groups.addAll([a, b]);
      doc.timeline = timeline();
      return (scene, doc);
    }

    test('Seq: the second child waits, holding its start', () {
      var (scene, doc) = pair(() => SeqExpr([GroupRef('a'), GroupRef('b')]));
      var bound = BoundMotion.bind(doc, scene);
      expect(bound.duration, const Duration(milliseconds: 500));
      var cup = scene.nodeNamed('cup')!;
      bound.apply(const Duration(milliseconds: 100));
      expect(cup.fxRendered('opacity'), 1.0); // held at its start
      bound.apply(const Duration(milliseconds: 350));
      expect(cup.fxRendered('opacity'), closeTo(0.5, 1e-9));
    });

    test('Speed halves or doubles the clock', () {
      var (scene, doc) = pair(
        () => ParExpr([SpeedExpr(2, GroupRef('a')), GroupRef('b')]),
      );
      var bound = BoundMotion.bind(doc, scene);
      var glow = scene.nodeNamed('glow')!;
      bound.apply(const Duration(milliseconds: 50));
      // 50ms at 2x is local 100 of 200 — and the contribution composes
      // over glow's authored 0.7.
      expect(glow.fxRendered('opacity'), closeTo(0.7 * 0.5, 1e-9));
    });

    test('Repeat cycles, and its last frame holds the end', () {
      var (scene, doc) = pair(() => RepeatExpr(3, GroupRef('a')));
      var bound = BoundMotion.bind(doc, scene);
      expect(bound.duration, const Duration(milliseconds: 600));
      var glow = scene.nodeNamed('glow')!;
      bound.apply(const Duration(milliseconds: 300)); // cycle 2, local 100
      expect(glow.fxRendered('opacity'), closeTo(0.7 * 0.5, 1e-9));
      bound.apply(const Duration(milliseconds: 600)); // the very end
      expect(glow.fxRendered('opacity'), closeTo(0.7 * 1.0, 1e-9));
    });
  });

  group('the player', () {
    (SceneDocument, BoundMotion) shortPair() {
      var scene = coffeeBannerDraft();
      var doc = MotionDocument(sceneClassName: 'BannerScene');
      var g = AnimateGroup('g', 'glow');
      g.tracks['translateY'] = MotionTrack(TrackKind.number, [
        MotionKey(at: Duration.zero, value: 0.0),
        MotionKey(at: const Duration(milliseconds: 200), value: 100.0),
      ]);
      doc.groups.add(g);
      doc.timeline = ParExpr([GroupRef('g')]);
      return (scene, BoundMotion.bind(doc, scene));
    }

    testWidgets('play ticks, applies, and stops itself at the end', (
      tester,
    ) async {
      var (scene, bound) = shortPair();
      var glow = scene.nodeNamed('glow')!;
      var player = MotionPlayer(bound);
      player.play();
      expect(player.status, MotionPlayerStatus.playing);
      await tester.pump(); // the ticker's first tick stamps its start time
      await tester.pump(const Duration(milliseconds: 100));
      expect(glow.fxRendered('translateY'), 50.0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(player.status, MotionPlayerStatus.completed);
      expect(player.position, const Duration(milliseconds: 200));
      expect(glow.fxRendered('translateY'), 100.0);
      // Completed: the picture holds, the authored value was never touched.
      expect(glow.y, -110.0);
      player.dispose();
    });

    testWidgets('rate is the player knob: 2x finishes in half the time', (
      tester,
    ) async {
      var (_, bound) = shortPair();
      var player = MotionPlayer(bound)..rate = 2;
      player.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      expect(player.status, MotionPlayerStatus.completed);
      player.dispose();
    });

    testWidgets('pause holds, seek is pure in any direction', (tester) async {
      var (scene, bound) = shortPair();
      var glow = scene.nodeNamed('glow')!;
      var player = MotionPlayer(bound);
      player.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      player.pause();
      await tester.pump(const Duration(milliseconds: 500));
      expect(player.position, const Duration(milliseconds: 100));
      expect(glow.fxRendered('translateY'), 50.0);
      player.seek(const Duration(milliseconds: 40));
      expect(glow.fxRendered('translateY'), 20.0);
      player.dispose();
    });

    testWidgets('stop is cancel: fx drops, base untouched', (tester) async {
      var (scene, bound) = shortPair();
      var glow = scene.nodeNamed('glow')!;
      var player = MotionPlayer(bound);
      player.play();
      await tester.pump(const Duration(milliseconds: 100));
      player.stop();
      expect(glow.fx, isEmpty);
      expect(glow.fxRendered('translateY'), 0.0);
      expect(player.status, MotionPlayerStatus.idle);
      player.dispose();
    });

    testWidgets('one driver at a time, refused with a teaching message', (
      tester,
    ) async {
      var (_, bound) = shortPair();
      var first = MotionPlayer(bound)..play();
      var second = MotionPlayer(bound);
      expect(second.play, throwsStateError);
      first.dispose();
      // Released on stop: now the second may drive.
      second.play();
      second.dispose();
    });

    testWidgets('the wire carries the rendered picture', (tester) async {
      var scene = coffeeBannerDraft();
      var bound = BoundMotion.bind(coffeeIntroDraft(), scene);
      bound.apply(const Duration(milliseconds: 130));
      var root = scene.toJson()['root'] as Map<String, dynamic>;
      var copy = (root['children'] as List)[2] as Map<String, dynamic>;
      var headline = (copy['children'] as List)[0] as Map<String, dynamic>;
      expect(headline['opacity'], Curves.easeOut.transform(0.5));
      var fx = headline['fx'] as List;
      expect(fx[1], isNot(0)); // translateY mid-slide
      expect(fx[2], 1); // scale untouched
      var badge = (root['children'] as List)[3] as Map<String, dynamic>;
      // badgePop sits behind At(400.ms): its window has not opened, so the
      // arg holds its first key.
      expect(badge['args'], containsPair('progress', 0.0));
      bound.apply(const Duration(milliseconds: 550));
      var later = scene.toJson()['root'] as Map<String, dynamic>;
      var badge2 = (later['children'] as List)[3] as Map<String, dynamic>;
      expect(badge2['args'], containsPair('progress', 0.5));
      // Cancel: the wire returns to the authored picture, no fx field.
      bound.clearFx();
      var again = scene.toJson()['root'] as Map<String, dynamic>;
      var headline2 =
          ((((again['children'] as List)[2] as Map)['children'] as List)[0])
              as Map<String, dynamic>;
      expect(headline2['opacity'], 1.0);
      expect(headline2.containsKey('fx'), isFalse);
    });

    testWidgets('the local mirror draws the rendered plane', (tester) async {
      var scene = coffeeBannerDraft();
      var headline = scene.nodeNamed('headline')!;
      headline.writeFx('m', 'opacity', 0.25);
      headline.writeFx('m', 'translateY', 12.0);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(width: 1024, height: 500, child: NodeView(scene.root)),
        ),
      );
      var text = find.text('Fresh coffee, faster');
      var fade = tester.widget<Opacity>(
        find.ancestor(of: text, matching: find.byType(Opacity)).first,
      );
      expect(fade.opacity, 0.25);
      var moved = tester.widget<Transform>(
        find.ancestor(of: text, matching: find.byType(Transform)).first,
      );
      expect(moved.transform.getTranslation().y, 12.0);
    });

    testWidgets('the transport plays the pair end to end', (tester) async {
      var scene = coffeeBannerDraft();
      var headline = scene.nodeNamed('headline')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MotionTransport(scene, coffeeIntroDraft())),
        ),
      );
      await tester.tap(find.byTooltip('Play'));
      await tester.pump(); // the ticker's first tick stamps its start time
      await tester.pump(const Duration(milliseconds: 130));
      expect(headline.fxRendered('opacity'), Curves.easeOut.transform(0.5));
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump(const Duration(seconds: 1));
      expect(headline.fxRendered('opacity'), Curves.easeOut.transform(0.5));
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      expect(headline.fx, isEmpty);
      expect(headline.fxRendered('opacity'), 1.0);
    });

    testWidgets('a parked scrub repaints the mirror with the parked frame', (
      tester,
    ) async {
      // The full toy wiring: transport + AnimatedBuilder(doc) + NodeView —
      // a slider seek AFTER completion must rebuild the mirror (the flush
      // rides notifyListeners; without a listener the picture goes stale).
      var scene = coffeeBannerDraft();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MotionTransport(scene, coffeeIntroDraft()),
                Expanded(
                  child: AnimatedBuilder(
                    animation: scene,
                    builder: (context, _) =>
                        FittedBox(child: NodeView(scene.root)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2)); // runs to completion
      await tester.pump(const Duration(milliseconds: 50));
      var opacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity);
      expect(opacities, isNot(contains(0.0))); // end pose: identity fx

      await tester.drag(find.byType(Slider), const Offset(-800, 0));
      await tester.pump(); // the flush's post-frame notify
      await tester.pump(); // the rebuild it schedules
      opacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity);
      expect(opacities, contains(0.0)); // headline parked at t=0: invisible
    });

    testWidgets('a burst of fx writes is one notification', (tester) async {
      var (scene, bound) = shortPair();
      var notifications = 0;
      scene.addListener(() => notifications++);
      for (var i = 0; i < 500; i++) {
        bound.apply(Duration(milliseconds: i % 200));
      }
      expect(notifications, 0); // nothing until the frame
      await tester.pump();
      expect(notifications, 1);
    });
  });
}
