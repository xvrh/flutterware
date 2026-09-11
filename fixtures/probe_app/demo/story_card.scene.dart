//@flutterware:scene=0.9
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class StoryCard({final SceneTokens tokens = const SceneTokens()})
    extends SceneDefinition {
  late final readMore = ExternalNode(
    OrderButtonArgs(label: 'Read the story', style: tokens.ctaStyle),
    x: 64,
    y: 380,
  );
  @override
  late final root = FrameNode(
    width: 1024,
    height: 500,
    fill: SceneColor(0xFFFFFFFF),
    children: [readMore],
  );
}
