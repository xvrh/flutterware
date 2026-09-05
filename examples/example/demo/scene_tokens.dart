// The values this app's scenes share, declared once.
//
// A token is read by any scene of the package through its tokens formal —
// `color: tokens.ink` — and the generated `SceneTokens` class beside this
// file is what makes that a field the compiler checks. Written by hand, so
// it mentions nothing generated; the editor reads it as text and offers each
// token in the inspector for a property of its kind.
import 'package:flutterware/scene_authoring.dart';

final sceneTokens = [
  const Token<SceneColor>('brand', SceneColor(0xFFE8632B)),
  const Token<SceneColor>('ink', SceneColor(0xFFFFFFFF)),
  const Token<SceneColor>('espresso', SceneColor(0xFF2B1B12)),
  const Token<double>('radius', 28),
];
