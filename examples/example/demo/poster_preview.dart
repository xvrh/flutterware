import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import 'arcade_poster.scene.dart';

/// A scene mounted as a preview, which is how a poster gets looked at at the
/// size it will be printed rather than at whatever fraction fits a pane.
///
/// The scene itself is `arcade_poster.scene.dart` — ordinary Dart the editor
/// owns, instantiated here like any other widget, with its parameters filled
/// the way a caller would fill them.
@Preview(name: 'Arcade poster', group: 'Scene')
Widget arcadePoster() => const _Poster();

class _Poster extends StatelessWidget {
  const _Poster();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: const Color(0xFF0C0714),
      child: Align(
        alignment: Alignment.topLeft,
        child: SceneView(ArcadePoster()),
      ),
    ),
  );
}

/// The same poster with its parameters answered differently — the point of a
/// scene having parameters at all.
@Preview(name: 'Arcade poster · win', group: 'Scene')
Widget arcadePosterWin() => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ColoredBox(
    color: const Color(0xFF0C0714),
    child: Align(
      alignment: Alignment.topLeft,
      child: SceneView(
        ArcadePoster(
          title: 'new record',
          kicker: 'enter your initials',
          score: '00312750',
          neon: const SceneColor(0xFF39FF14),
        ),
      ),
    ),
  ),
);
