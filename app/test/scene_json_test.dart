// The authored round trip: what a guest is handed when it has to evaluate the
// motion itself, rather than be fed rendered frames.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';

void main() {
  test('the wire round-trips as the picture it is', () {
    var scene = coffeeBannerDraft();
    var headline = scene.nodeNamed('headline')!;
    // A motion frame: opacity halved and the node lifted, as fx.
    headline.effect()
      ..opacity = 0.5
      ..translateY = 12;
    var wire = jsonDecode(
      jsonEncode(scene.toWire(selected: ['headline'])),
    ) as Map<String, Object?>;
    var back = sceneFromWire((wire['root']! as Map).cast<String, Object?>());
    var drawn = back.nodeNamed('headline')!;
    // The composed values arrive already composed…
    expect(drawn.fxRendered('opacity'), closeTo(0.5, 1e-9));
    // …and the transform, which has no authored slot, comes back as fx.
    expect(drawn.fxRendered('translateY'), 12);
    expect(back.nodeNamed('glow')!.fill, const SceneColor(0xFF4A2F1F));
    expect((back.nodeNamed('cup')! as TextNode).text, '☕');
    expect(back.nodeNamed('badge'), isA<ExternalNode>());
  });

  test('a whole file survives JSON, authored values and all', () {
    var scene = coffeeBannerDraft();
    scene.params.add(
      SceneParamDecl(
        'accent',
        SceneParamKind.color,
        const SceneColor(0xFFE8632B),
      ),
    );
    scene.nodeNamed('cta')!.bindings['fill'] = const ParamRef('accent');
    var encoded = jsonEncode(
      sceneFileToJson(
        scene,
        className: 'BannerScene',
        motions: {'BannerIntro': coffeeIntroDraft(scene)},
      ),
    );
    var back = sceneFileFromJson(jsonDecode(encoded) as Map<String, Object?>);

    expect(back.className, 'BannerScene');
    expect(back.scene.walk().length, scene.walk().length);
    var headline = back.scene.nodeNamed('headline')! as TextNode;
    expect(headline.text, 'Fresh coffee, faster');
    expect(headline.fontSize, 54);
    expect(headline.weight, SceneFontWeight.w700);
    expect(headline.color, const SceneColor(0xFFFFFFFF));
    expect(back.scene.nodeNamed('glow')!.fill, const SceneColor(0xFF4A2F1F));
    expect((back.scene.nodeNamed('glow')! as ShapeNode).circle, true);
    expect(
      back.scene.nodeNamed('cta')!.bindings['fill'],
      const ParamRef('accent'),
    );
    // A colour parameter comes back a colour, not the int it travelled as.
    expect(back.scene.params.single.defaultValue, isA<SceneColor>());

    var motion = back.motions['BannerIntro']!;
    expect(motion.groups.map((g) => g.name), [
      'headlineIn',
      'glowMood',
      'badgePop',
      'tapPulse',
    ]);
    expect(motion.params.single.name, 'slideFrom');
    var track = motion.groupNamed('headlineIn')!.tracks['opacity']!;
    expect(track.keys.map((k) => k.at.inMilliseconds), [0, 260]);
    expect(track.keys.last.curve, SceneCurves.easeOut);
    expect(motion.groupNamed('badgePop')!.args['size'], isNotNull);
  });

  test('the decoded pair binds and evaluates like the original', () {
    var scene = coffeeBannerDraft();
    var json = sceneFileToJson(
      scene,
      className: 'BannerScene',
      motions: {'BannerIntro': coffeeIntroDraft(scene)},
    );
    var back = sceneFileFromJson(
      jsonDecode(jsonEncode(json)) as Map<String, Object?>,
    );
    var bound = BoundMotion.bind(back.motions['BannerIntro']!, back.scene);
    bound.apply(const Duration(milliseconds: 130));
    expect(
      back.scene.nodeNamed('headline')!.fxRendered('opacity'),
      closeTo(0.68359375, 1e-9),
      reason: 'the same frame the file itself evaluates to',
    );
  });

  test('the timeline tree survives, nesting included', () {
    var scene = coffeeBannerDraft();
    var motion = coffeeIntroDraft(scene);
    motion.timeline = SeqExpr([
      motion.groupNamed('headlineIn')!,
      AtExpr(
        const Duration(milliseconds: 200),
        SpeedExpr(2, RepeatExpr(3, motion.groupNamed('tapPulse')!)),
      ),
    ]);
    var back = motionFromJson(
      jsonDecode(jsonEncode(motion.toJson())) as Map<String, Object?>,
      sceneClassName: 'BannerScene',
      scene: scene,
    );
    var seq = back.timeline as SeqExpr;
    var at = seq.children[1] as AtExpr;
    var speed = at.child as SpeedExpr;
    var repeat = speed.child as RepeatExpr;
    expect(at.offset, const Duration(milliseconds: 200));
    expect(speed.factor, 2);
    expect(repeat.times, 3);
    expect((repeat.child as AnimateGroup).name, 'tapPulse');
  });
}
