//@flutterware:scene=0.9
import 'package:flutterware/scene_authoring.dart';

class PromoBadge({
  final String label = 'New',
  final SceneColor tint = const SceneColor(0xFFE8632B),
}) extends SceneDefinition {
  late final text = TextNode(
    label,
    style: SceneTextStyle(
      fontSize: 14,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  @override
  late final root = FrameNode(
    width: 96,
    height: 32,
    fill: tint,
    corner: 16,
    layout: NodeLayout.row,
    mainAlign: SceneMainAxisAlignment.center,
    children: [text],
  );
}
