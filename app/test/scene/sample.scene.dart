//@flutterware:scene=0.8
// Owned by the flutterware scene editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar: every node is a
// `late final` field (the field name is the node's identity), placed exactly
// once in a children list; a parameter is a `final` in the class header
// whose default is the mockup. Anything outside the grammar is refused with
// a line number rather than silently dropped.
//
// This is ordinary Dart: it compiles, it analyzes, and an app mounts it.
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class SampleScene({
  final String headline = 'Fresh coffee, faster',
  final SceneColor tint = const SceneColor(0xFFE8632B),
  final List<({String label, String value})> rows = const [
    (label: 'Beans', value: '1kg'),
    (label: 'Milk', value: '12L'),
  ],
}) extends SceneDefinition {
  late final badge = ShapeNode(width: 24, height: 24, fill: tint, circle: true);
  late final title = TextNode(
    headline,
    fontSize: 32,
    weight: SceneFontWeight.w700,
    color: SceneColor(0xFFFFFFFF),
  );
  late final bar = FrameNode(
    layout: NodeLayout.row,
    gap: 12,
    padding: 16,
    children: [badge, title],
  );
  late final table = FrameNode.repeating(
    over: rows,
    row: (line) => [
      TextNode(line.label, fontSize: 11),
      TextNode(line.value, fontSize: 11, align: SceneTextAlign.right),
    ],
    layout: NodeLayout.row,
  );
  late final chip = ExternalNode(
    const SampleChipArgs(label: 'new'),
    width: 60,
    height: 20,
  );
  late final badgeRef = SceneRefNode(const SampleBadgeArgs(label: 'Open'));
  @override
  late final root = FrameNode(
    width: 400,
    height: 120,
    fill: SceneColor(0xFF2B1B12),
    children: [bar, table, chip, badgeRef],
  );
}

class SampleIntro(super.scene, {final double slideFrom = 24})
    extends SceneMotion<SampleScene> {
  late final titleIn = scene.title.animate(
    opacity: MotionTrack([
      MotionKey(at: 0.ms, value: 0),
      MotionKey(at: 260.ms, value: 1, curve: SceneCurves.easeOut),
    ]),
    translateY: MotionTrack([
      MotionKey(at: 0.ms, value: slideFrom),
      MotionKey(at: 260.ms, value: 0, curve: SceneCurves.easeOut),
    ]),
  );
  late final badgePop = scene.badge.animate(
    scale: MotionTrack([
      MotionKey(at: 0.ms, value: 0.6),
      MotionKey(at: 240.ms, value: 1, curve: SceneCurves.easeOutBack),
    ]),
  );
  @override
  late final timeline = ParExpr([titleIn, AtExpr(120.ms, badgePop)]);
  SampleIntro copy(SampleScene scene) =>
      copyStateInto(SampleIntro(scene, slideFrom: slideFrom));
}
