//@flutterware:tokens=1
// The fixture group's tokens: what `sample.scene.dart` reads through its
// tokens formal, with a dark mode so a set can be flipped under a scene.
import 'package:flutterware/scene_authoring.dart';

// Declared by name: a mode exists before any token differs in it.
const sampleTokensModes = ['dark', 'dense'];

final sampleTokens = [
  const Token<SceneColor>(
    'surface',
    SceneColor(0xFF2B1B12),
    modes: {'dark': SceneColor(0xFF111111)},
  ),
  const Token<SceneColor>(
    'ink',
    SceneColor(0xFFFFFFFF),
    modes: {'dark': SceneColor(0xFFEEEEEE)},
  ),
];
