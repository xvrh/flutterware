//@flutterware:tokens=1
// Owned by the flutterware scene editor, which reads and writes this whole
// file. A token is `Token<T>('name', value, modes: {…})`; every scene of a
// group that lists this library reads it as `tokens.name`. Hand edits are
// welcome inside the grammar; anything outside it is refused with a line
// number rather than silently dropped.
import 'package:flutterware/scene_authoring.dart';

const brandTokensModes = ['dark'];

final brandTokens = [
  const Token<SceneColor>(
    'brand',
    SceneColor(0xFFE8632B),
    modes: {'dark': SceneColor(0xFFFF8A5C)},
  ),
  const Token<SceneColor>(
    'ink',
    SceneColor(0xFFFFFFFF),
    modes: {'dark': SceneColor(0xFF1A1208)},
  ),
  const Token<SceneColor>(
    'espresso',
    SceneColor(0xFF2B1B12),
    modes: {'dark': SceneColor(0xFFF3E9E1)},
  ),
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
