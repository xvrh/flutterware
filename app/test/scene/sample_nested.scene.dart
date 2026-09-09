//@flutterware:scene=0.9
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class SampleBadge({
  final String label = 'New',
  final SceneTokens tokens = const SceneTokens(),
}) extends SceneDefinition {
  late final text = TextNode(
    label,
    style: SceneTextStyle(
      fontSize: 11,
      weight: SceneFontWeight.w700,
      color: tokens.ink,
    ),
  );
  @override
  late final root = FrameNode(
    width: 70,
    height: 22,
    fill: SceneColor(0xFFE8632B),
    corner: 11,
    layout: NodeLayout.row,
    mainAlign: SceneMainAxisAlignment.center,
    children: [text],
  );
}
