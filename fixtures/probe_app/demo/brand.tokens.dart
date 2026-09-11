//@flutterware:tokens=1
import 'package:flutterware/scene_authoring.dart';

final brandTokens = [
  const Token<SceneColor>('brand', SceneColor(0xFFE8632B)),
  const Token<SceneColor>('ink', SceneColor(0xFFFFFFFF)),
  const Token<SceneColor>('espresso', SceneColor(0xFF2B1B12)),
  const Token<double>('radius', 28),
  const Token<SceneTextStyle>(
    'title',
    SceneTextStyle(fontSize: 54, weight: SceneFontWeight.w700),
  ),
  const Token<SceneTextStyle>(
    'body',
    SceneTextStyle(fontSize: 20, color: SceneColor(0xFFD8C9BD)),
  ),
];
