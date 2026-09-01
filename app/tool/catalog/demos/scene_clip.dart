import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

/// A scene and its motion, built in code and mounted with `SceneView`.
///
/// This is the studio's own picture of what an export walks: mounting the
/// view with a bound motion registers a playhead, and every stop of a walk is
/// `evaluate(t)` on the same document. `walk_determinism_test` takes this
/// entry forwards, backwards and twice, and expects the same pixels each
/// time — which is the property the whole export lane rests on.
///
/// Built here rather than parsed from a `*.scene.dart`, because the catalog
/// compiles this file into the guest and a fixture that read another file at
/// run time would tie the picture to the working directory.
@Preview(name: 'Scene clip', group: 'Scene')
Widget sceneClip() => const _SceneClip();

class _SceneClip extends StatefulWidget {
  const _SceneClip();

  @override
  State<_SceneClip> createState() => _SceneClipState();
}

class _SceneClipState extends State<_SceneClip> {
  late final SceneDocument _scene = _buildScene();
  late final Playable _motion = BoundMotion.bind(_buildMotion(), _scene);

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: const Color(0xFF26282C),
      child: Align(
        alignment: Alignment.topLeft,
        child: SceneView(_scene, motion: _motion),
      ),
    ),
  );
}

SceneDocument _buildScene() {
  var headline = TextNode('headline', 'Fresh coffee, faster')
    ..x = 32
    ..y = 48
    ..fontSize = 32
    ..weight = SceneFontWeight.w700
    ..color = const SceneColor(0xFFFFFFFF);
  var subtitle = TextNode('subtitle', 'Order ahead. Skip the line.')
    ..x = 32
    ..y = 96
    ..fontSize = 16
    ..color = const SceneColor(0xFFD8C9BD);
  var badge = ShapeNode('badge', circle: true)
    ..x = 400
    ..y = 40
    ..width = 96
    ..height = 96
    ..fill = const SceneColor(0xFFE8632B);
  var root = FrameNode('root')
    ..width = 540
    ..height = 180
    ..fill = const SceneColor(0xFF3B2A1F)
    ..children.addAll([headline, subtitle, badge]);
  return SceneDocument(root);
}

MotionDocument _buildMotion() {
  var headlineIn = AnimateGroup('headlineIn', 'headline')
    ..tracks['opacity'] = MotionTrack(TrackKind.number, [
      MotionKey(at: Duration.zero, value: 0.0),
      MotionKey(at: const Duration(milliseconds: 600), value: 1.0),
    ])
    ..tracks['translateY'] = MotionTrack(TrackKind.number, [
      MotionKey(at: Duration.zero, value: 24.0, curve: 'easeOut'),
      MotionKey(at: const Duration(milliseconds: 600), value: 0.0),
    ]);
  var subtitleIn = AnimateGroup('subtitleIn', 'subtitle')
    ..tracks['opacity'] = MotionTrack(TrackKind.number, [
      MotionKey(at: Duration.zero, value: 0.0),
      MotionKey(at: const Duration(milliseconds: 500), value: 1.0),
    ]);
  var badgePop = AnimateGroup('badgePop', 'badge')
    ..tracks['scale'] = MotionTrack(TrackKind.number, [
      MotionKey(at: Duration.zero, value: 0.0, curve: 'easeOutBack'),
      MotionKey(at: const Duration(milliseconds: 500), value: 1.0),
    ]);
  return MotionDocument(sceneClassName: 'SceneClip')
    ..groups.addAll([headlineIn, subtitleIn, badgePop])
    ..timeline = ParExpr([
      GroupRef('headlineIn'),
      AtExpr(const Duration(milliseconds: 200), GroupRef('subtitleIn')),
      AtExpr(const Duration(milliseconds: 400), GroupRef('badgePop')),
    ]);
}
