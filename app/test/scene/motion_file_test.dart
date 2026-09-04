import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/motion_file.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

void main() {
  var scene = coffeeBannerDraft();
  const sceneClass = 'BannerScene';

  // A motion has no file of its own (grammar 0.5): it is a class in the
  // scene file, beside the scene it animates. So every fixture here is a
  // whole pair — [filePrefix] is the scene half the fixture appends to,
  // and the helpers below read and write the motion through that one door.
  var filePrefix = emitSceneFile(scene, className: sceneClass).trimRight();

  String emitMotionFile(
    MotionDocument doc,
    SceneDocument scene, {
    required String className,
  }) => emitSceneFile(scene, className: sceneClass, motions: {className: doc});

  // The scene comes back with the motion, because a motion's groups hold
  // THAT scene's nodes — re-emitting one against a different document is a
  // pair the emitter is right to refuse.
  ({
    MotionDocument? doc,
    SceneDocument? scene,
    String? className,
    List<SceneRefusal> refusals,
    bool ok,
  })
  parseWithScene(String source) {
    var parsed = parseSceneFile(source);
    var motion = parsed.motions.entries.isEmpty
        ? null
        : parsed.motions.entries.first;
    return (
      doc: motion?.value,
      scene: parsed.doc,
      className: motion?.key,
      refusals: parsed.refusals,
      ok: parsed.ok && motion != null,
    );
  }

  test('the coffee intro round-trips', () {
    var doc = coffeeIntroDraft(scene);
    var emitted = emitMotionFile(doc, scene, className: 'BannerIntro');
    var parsed = parseWithScene(emitted);
    expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
    expect(parsed.ok, isTrue);
    expect(parsed.className, 'BannerIntro');
    var again = emitMotionFile(
      parsed.doc!,
      parsed.scene!,
      className: 'BannerIntro',
    );
    expect(again, emitted);
  });

  test('the emitted file carries the settled spellings', () {
    var emitted = emitMotionFile(
      coffeeIntroDraft(scene),
      scene,
      className: 'BannerIntro',
    );
    // The header: primary constructor, super.scene, the extends clause.
    expect(emitted, contains('class BannerIntro('));
    expect(emitted, contains('super.scene'));
    expect(emitted, contains('final double slideFrom = 24'));
    expect(emitted, contains('extends SceneMotion<BannerScene>'));
    // Groups are extension-form animate calls on typed targets.
    expect(
      emitted,
      contains('late final headlineIn = scene.headline.animate('),
    );
    expect(emitted, contains('late final badgePop = scene.badge.animate('));
    // The parameter feeds a key by name; the curve is allowlisted.
    expect(emitted, contains('value: slideFrom'));
    expect(emitted, contains('curve: SceneCurves.easeOut'));
    // An external widget's own arguments, through its generated tracks
    // class — no strings, and no slot for anything it does not declare.
    expect(emitted, contains('args: DrinkBadgeTracks('));
    // The timeline is mandatory and arranges by reference.
    expect(emitted, contains('late final timeline = ParExpr('));
    expect(emitted, contains('AtExpr(400.ms, badgePop)'));
    // tapPulse is a library asset: declared, playable, not in the timeline.
    expect(emitted, contains('late final tapPulse'));
    expect(emitted.contains('tapPulse,'), isFalse);
    // The derived copy member, canonical single expression.
    expect(emitted, contains('BannerIntro copy(BannerScene scene)'));
    expect(emitted, contains('copyStateInto('));
    expect(emitted, contains('slideFrom: slideFrom'));
  });

  test('emit ∘ parse is the identity on canonical files', () {
    var canonical = emitMotionFile(
      coffeeIntroDraft(scene),
      scene,
      className: 'BannerIntro',
    );
    var back = parseWithScene(canonical);
    var once = emitMotionFile(back.doc!, back.scene!, className: 'BannerIntro');
    expect(once, canonical);
  });

  test('accepted non-canonical spellings converge in one emit', () {
    // `final` for `late final`, SceneCurves.linear for no curve, a missing copy,
    // a type-less parameter formal: accepted, then canonical.
    var parsed = parseWithScene('''
$filePrefix
class M(super.scene, {final slideFrom = 24}) extends SceneMotion<BannerScene> {
  final glowIn = scene.glow.animate(
    opacity: MotionTrack([
      MotionKey(at: 0.ms, value: 0, curve: SceneCurves.linear),
      MotionKey(at: 400.ms, value: 1),
    ]),
  );
  final timeline = ParExpr([glowIn]);
}
''');
    expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
    var emitted = emitMotionFile(parsed.doc!, parsed.scene!, className: 'M');
    expect(emitted, contains('late final glowIn'));
    expect(emitted, contains('final double slideFrom = 24'));
    expect(emitted.contains('linear'), isFalse);
    expect(emitted, contains('M copy(BannerScene scene)'));
    var round = parseWithScene(emitted);
    var again = emitMotionFile(round.doc!, round.scene!, className: 'M');
    expect(again, emitted);
  });

  test('a stale copy is tolerated and converged, not refused', () {
    // The class gained a parameter but copy was not updated — the shape is
    // canonical, the argument list stale. Parse accepts; emit rewrites.
    var parsed = parseWithScene('''
$filePrefix
class M(super.scene, {final double tempo = 2}) extends SceneMotion<BannerScene> {
  late final glowIn = scene.glow.animate(
    opacity: MotionTrack([MotionKey(at: 0.ms, value: 0), MotionKey(at: 400.ms, value: 1)]),
  );
  late final timeline = ParExpr([glowIn]);
  M copy(BannerScene scene) => copyStateInto(M(scene));
}
''');
    expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
    var emitted = emitMotionFile(parsed.doc!, parsed.scene!, className: 'M');
    expect(emitted, contains('tempo: tempo'));
  });

  test('two keys of one param: the reference survives only at the default', () {
    var parsed = parseWithScene('''
$filePrefix
class M(super.scene, {final double slide = 24}) extends SceneMotion<BannerScene> {
  late final headlineIn = scene.headline.animate(
    translateY: MotionTrack([MotionKey(at: 0.ms, value: slide), MotionKey(at: 300.ms, value: 0)]),
  );
  late final timeline = ParExpr([headlineIn]);
}
''');
    expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
    var doc = parsed.doc!;
    var track = doc.groups.single.tracks['translateY']!;
    expect(track.keys.first.value, 24.0);
    expect(track.keys.first.paramRef, 'slide');

    // The divergence-bakes rule: edit the key, the reference is dropped —
    // never the edit.
    track.keys.first.value = 40.0;
    var emitted = emitMotionFile(doc, parsed.scene!, className: 'M');
    expect(emitted, contains('value: 40'));
    expect(emitted.contains('value: slide'), isFalse);
  });

  test('the track door keeps keys sorted through a drag past a neighbour', () {
    var doc = coffeeIntroDraft(scene);
    var track = doc.groups.first.tracks['opacity']!;
    var key = track.keys.first;
    track.moveKey(key, const Duration(milliseconds: 500));
    expect(track.keys.last, same(key));
    var emitted = emitMotionFile(doc, scene, className: 'BannerIntro');
    var parsed = parseWithScene(emitted);
    expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
  });

  test('fuzz: 150 random motions survive emit → parse → emit', () {
    var random = Random(20260901);
    for (var i = 0; i < 150; i++) {
      var doc = _randomMotion(random, scene);
      var emitted = emitMotionFile(doc, scene, className: 'Fuzz$i');
      var parsed = parseWithScene(emitted);
      expect(
        parsed.refusals,
        isEmpty,
        reason:
            'iteration $i refused its own emit:\n'
            '${parsed.refusals.join('\n')}\n$emitted',
      );
      var again = emitMotionFile(
        parsed.doc!,
        parsed.scene!,
        className: 'Fuzz$i',
      );
      expect(again, emitted, reason: 'iteration $i drifted');
    }
  });

  group('hostile hand edits are refused with a name and a line', () {
    String wrap(String members) =>
        '''
$filePrefix
class M(super.scene) extends SceneMotion<BannerScene> {
$members
  late final timeline = ParExpr([]);
}
''';

    var cases = <String, (String, String)>{
      'a target outside the scene': (
        wrap(
          '  late final g = scene.rocket.animate(opacity: '
          'MotionTrack([MotionKey(at: 0.ms, value: 1)]));',
        ),
        'unknown target',
      ),
      'a property the target kind cannot animate': (
        wrap(
          '  late final g = scene.glow.animate(fontSize: '
          'MotionTrack([MotionKey(at: 0.ms, value: 12)]));',
        ),
        'unknown property',
      ),
      'a color literal on a number track': (
        wrap(
          '  late final g = scene.glow.animate(opacity: '
          'MotionTrack([MotionKey(at: 0.ms, value: Color(0xFF000000))]));',
        ),
        'method call',
      ),
      'args on a node that is not external': (
        wrap(
          '  late final g = scene.glow.animate(args: '
          "{'x': MotionTrack([MotionKey(at: 0.ms, value: 1)])});",
        ),
        'args',
      ),
      'an empty track': (
        wrap('  late final g = scene.glow.animate(opacity: MotionTrack([]));'),
        'empty track',
      ),
      'keys out of time order': (
        wrap(
          '  late final g = scene.glow.animate(opacity: MotionTrack(['
          'MotionKey(at: 400.ms, value: 1), MotionKey(at: 0.ms, value: 0)]));',
        ),
        'keys out of order',
      ),
      'two keys at one time': (
        wrap(
          '  late final g = scene.glow.animate(opacity: MotionTrack(['
          'MotionKey(at: 100.ms, value: 1), MotionKey(at: 100.ms, value: 0)]));',
        ),
        'duplicate key time',
      ),
      'a curve off the allowlist': (
        wrap(
          '  late final g = scene.glow.animate(opacity: MotionTrack(['
          'MotionKey(at: 0.ms, value: 1, curve: SceneCurves.wobble)]));',
        ),
        'unknown curve',
      ),
      'a time not spelled in ms': (
        wrap(
          '  late final g = scene.glow.animate(opacity: MotionTrack(['
          'MotionKey(at: 100, value: 1)]));',
        ),
        'IntegerLiteralImpl',
      ),
      'an undeclared identifier as a value': (
        wrap(
          '  late final g = scene.glow.animate(opacity: MotionTrack(['
          'MotionKey(at: 0.ms, value: mystery)]));',
        ),
        'identifier',
      ),
      'arithmetic in a value': (
        wrap(
          '  late final g = scene.glow.animate(opacity: MotionTrack(['
          'MotionKey(at: 0.ms, value: 1 + 2)]));',
        ),
        'arithmetic',
      ),
      'a group name used twice': (
        wrap(
          '  late final g = scene.glow.animate(opacity: '
          'MotionTrack([MotionKey(at: 0.ms, value: 1)]));\n'
          '  late final g = scene.cup.animate(opacity: '
          'MotionTrack([MotionKey(at: 0.ms, value: 1)]));',
        ),
        'duplicate name',
      ),
      'a reserved name as a group': (
        wrap(
          '  late final copy = scene.glow.animate(opacity: '
          'MotionTrack([MotionKey(at: 0.ms, value: 1)]));',
        ),
        'duplicate name',
      ),
      'a method that is not copy': (wrap('  void play() {}'), 'member'),
      'a copy with a body of its own': (
        wrap('  M copy(BannerScene scene) { return this; }'),
        'copy',
      ),
      'an old-style constructor': (wrap('  M(this.scene);'), 'constructor'),
      'a comment inside the class': (
        wrap('  // tuned by hand, do not touch'),
        'comment',
      ),
    };

    for (var entry in cases.entries) {
      var (source, construct) = entry.value;
      test(entry.key, () {
        var parsed = parseWithScene(source);
        expect(parsed.ok, isFalse);
        expect(
          parsed.refusals.map((r) => r.construct),
          contains(construct),
          reason: parsed.refusals.join('\n'),
        );
        for (var r in parsed.refusals) {
          expect(r.line, greaterThan(0));
        }
      });
    }
  });

  group('the class header is half the grammar', () {
    test('a class without super.scene', () {
      var parsed = parseWithScene('''
$filePrefix
class M({final double x = 1}) extends SceneMotion<BannerScene> {
  late final timeline = ParExpr([]);
}
''');
      expect(parsed.refusals.map((r) => r.construct), contains('scene formal'));
    });

    test('a class extending nothing', () {
      var parsed = parseWithScene('''
$filePrefix
class M(super.scene) {
  late final timeline = ParExpr([]);
}
''');
      expect(parsed.refusals.map((r) => r.construct), contains('extends'));
    });

    test('a motion naming the wrong scene', () {
      var parsed = parseWithScene('''
$filePrefix
class M(super.scene) extends SceneMotion<OtherScene> {
  late final timeline = ParExpr([]);
}
''');
      var refusal = parsed.refusals.singleWhere(
        (r) => r.construct == 'scene class',
      );
      expect(refusal.message, contains('OtherScene'));
      expect(refusal.message, contains('BannerScene'));
    });

    test('a this. parameter teaches the header spelling', () {
      var parsed = parseWithScene('''
$filePrefix
class M(super.scene, {this.x = 1}) extends SceneMotion<BannerScene> {
  late final timeline = ParExpr([]);
}
''');
      expect(parsed.refusals.map((r) => r.construct), contains('parameter'));
    });
  });

  group('the timeline is mandatory and placement is single', () {
    test('a motion without a timeline', () {
      var parsed = parseWithScene('''
$filePrefix
class M(super.scene) extends SceneMotion<BannerScene> {
  late final g = scene.glow.animate(opacity: MotionTrack([MotionKey(at: 0.ms, value: 1)]));
}
''');
      expect(parsed.refusals.single.construct, 'no timeline');
    });

    test('a group placed twice', () {
      var parsed = parseWithScene('''
$filePrefix
class M(super.scene) extends SceneMotion<BannerScene> {
  late final g = scene.glow.animate(opacity: MotionTrack([MotionKey(at: 0.ms, value: 1)]));
  late final timeline = ParExpr([g, SeqExpr([g])]);
}
''');
      expect(parsed.refusals.map((r) => r.construct), contains('placed twice'));
    });

    test('an unknown reference and a parameter in the timeline', () {
      var parsed = parseWithScene('''
$filePrefix
class M(super.scene, {final double tempo = 2}) extends SceneMotion<BannerScene> {
  late final timeline = ParExpr([ghost, tempo]);
}
''');
      expect(
        parsed.refusals.map((r) => r.construct),
        containsAll(['unknown reference', 'parameter in timeline']),
      );
    });

    test('an unplaced group is NOT refused — it is a library asset', () {
      var parsed = parseWithScene('''
$filePrefix
class M(super.scene) extends SceneMotion<BannerScene> {
  late final tapPulse = scene.cta.animate(
    scale: MotionTrack([MotionKey(at: 0.ms, value: 1), MotionKey(at: 120.ms, value: 1.06)]),
  );
  late final timeline = ParExpr([]);
}
''');
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      expect(parsed.doc!.groups.single.name, 'tapPulse');
      expect(parsed.doc!.placedRefs(), isEmpty);
    });

    test('combinator argument rules refuse with names', () {
      var parsed = parseWithScene('''
$filePrefix
class M(super.scene) extends SceneMotion<BannerScene> {
  late final a = scene.glow.animate(opacity: MotionTrack([MotionKey(at: 0.ms, value: 1)]));
  late final b = scene.cup.animate(opacity: MotionTrack([MotionKey(at: 0.ms, value: 1)]));
  late final c = scene.cta.animate(opacity: MotionTrack([MotionKey(at: 0.ms, value: 1)]));
  late final timeline = ParExpr([SpeedExpr(0, a), RepeatExpr(0, b), Wobble(c)]);
}
''');
      expect(
        parsed.refusals.map((r) => r.construct),
        containsAll(['speed factor', 'repeat count', 'unknown combinator']),
      );
    });

    test('a nested arrangement round-trips', () {
      var parsed = parseWithScene('''
$filePrefix
class M(super.scene) extends SceneMotion<BannerScene> {
  late final a = scene.glow.animate(opacity: MotionTrack([MotionKey(at: 0.ms, value: 1)]));
  late final b = scene.cup.animate(opacity: MotionTrack([MotionKey(at: 0.ms, value: 1)]));
  late final c = scene.cta.animate(opacity: MotionTrack([MotionKey(at: 0.ms, value: 1)]));
  late final timeline = SeqExpr([a, AtExpr(120.ms, RepeatExpr(3, SpeedExpr(0.5, ParExpr([b, c]))))]);
}
''');
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var emitted = emitMotionFile(parsed.doc!, parsed.scene!, className: 'M');
      expect(
        emitted,
        contains(
          'AtExpr(120.ms, RepeatExpr(3, SpeedExpr(0.5, ParExpr([b, c]))))',
        ),
      );
    });
  });

  test('several hostile constructs are all reported at once', () {
    var parsed = parseWithScene('''
$filePrefix
class M(super.scene) extends SceneMotion<BannerScene> {
  late final g = scene.rocket.animate(opacity: MotionTrack([]));
  late final h = scene.glow.animate(warp: MotionTrack([MotionKey(at: 0.ms, value: 1)]));
  late final timeline = ParExpr([ghost]);
}
''');
    expect(parsed.ok, isFalse);
    expect(
      parsed.refusals.map((r) => r.construct),
      containsAll(['unknown target', 'unknown property', 'unknown reference']),
    );
  });

  test('broken syntax reports rather than throws', () {
    var parsed = parseWithScene('$filePrefix\nclass M(super.scene {');
    expect(parsed.ok, isFalse);
    expect(parsed.refusals, isNotEmpty);
  });

  test('a missing marker', () {
    var parsed = parseWithScene('''
class M(super.scene) extends SceneMotion<BannerScene> {
  late final timeline = ParExpr([]);
}
''');
    expect(parsed.refusals.map((r) => r.construct), contains('missing marker'));
  });
}

/// Random motions over the coffee banner's nodes: random groups with random
/// tracks from each target's animatable table, occasional param bindings and
/// ext args, and a random arrangement placing each group at most once.
MotionDocument _randomMotion(Random random, SceneDocument scene) {
  var doc = MotionDocument(sceneClassName: 'BannerScene');
  if (random.nextBool()) {
    doc.params.add(
      SceneParamDecl('p0', SceneParamKind.number, random.nextInt(100) / 2),
    );
  }
  var nodes = [for (var (n, _) in scene.walk()) n]..shuffle(random);
  var groupCount = 1 + random.nextInt(4);
  for (var i = 0; i < groupCount && i < nodes.length; i++) {
    var target = nodes[i];
    var group = AnimateGroup(target, name: 'g$i');
    var props = animatableProps(target)..shuffle(random);
    var trackCount = 1 + random.nextInt(2);
    for (var spec in props.take(trackCount)) {
      group.tracks[spec.name] = _randomTrack(random, spec.kind, doc);
    }
    if (target is ExternalNode && random.nextBool()) {
      group.args['arg${random.nextInt(3)}'] = _randomTrack(
        random,
        TrackKind.number,
        doc,
      );
    }
    doc.groups.add(group);
  }
  var placeable = [...doc.groups]..shuffle(random);
  if (random.nextBool() && placeable.isNotEmpty) placeable.removeLast();
  TimelineExpr wrap(TimelineExpr e) => switch (random.nextInt(4)) {
    0 => AtExpr(Duration(milliseconds: random.nextInt(500)), e),
    1 => SpeedExpr(0.5 + random.nextInt(4) / 2, e),
    2 => RepeatExpr(1 + random.nextInt(3), e),
    _ => e,
  };
  var arranged = [for (var r in placeable) wrap(r)];
  doc.timeline = random.nextBool() ? ParExpr(arranged) : SeqExpr(arranged);
  return doc;
}

MotionTrack _randomTrack(Random random, TrackKind kind, MotionDocument doc) {
  var track = MotionTrack([], kind: kind);
  var at = 0;
  var keyCount = 1 + random.nextInt(3);
  for (var i = 0; i < keyCount; i++) {
    Object value;
    String? paramRef;
    if (kind == TrackKind.color) {
      value = SceneColor(0xFF000000 | random.nextInt(0xFFFFFF));
    } else if (doc.params.isNotEmpty && random.nextInt(4) == 0) {
      var p = doc.params.first;
      value = p.defaultValue;
      paramRef = p.name;
    } else {
      value = random.nextInt(200) / 4;
    }
    track.keys.add(
      MotionKey(
        at: Duration(milliseconds: at),
        value: value,
        curve: random.nextBool()
            ? sceneCurvesByName[motionCurves[1 +
                  random.nextInt(motionCurves.length - 1)]]
            : null,
        paramRef: paramRef,
      ),
    );
    at += 1 + random.nextInt(600);
  }
  return track;
}
