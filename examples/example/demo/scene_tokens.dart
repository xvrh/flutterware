// The values this app's scenes share, declared once.
//
// A token is read by any scene of the package through its tokens formal —
// `color: tokens.ink` — and the generated `SceneTokens` class beside this
// file is what makes that a field the compiler checks. Written by hand, so
// it mentions nothing generated; the editor reads it as text and offers each
// token in the inspector for a property of its kind.
//
// Two kinds sit side by side. A value token (a colour, a number) the editor
// renders and any property may read. An opaque token — `ctaStyle` below is a
// ButtonStyle — is the app's own object: the editor names it, an external
// widget's argument takes it, and only this app ever sees inside.
import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

final sceneTokens = [
  // A token that differs by mode names the other value: the generated
  // `SceneTokens.dark` is the whole set with these swapped in.
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
  Token<ButtonStyle>(
    'ctaStyle',
    FilledButton.styleFrom(
      backgroundColor: const Color(0xFFE8632B),
      foregroundColor: Colors.white,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
    ),
  ),
];
