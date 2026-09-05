import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/tappable.dart';

/// The palette a scene's colours are picked from. A scene's own palette will
/// come from the project (its theme, its tokens); until then this is the
/// spike's, kept so the panel is usable.
const scenePalette = <SceneColor>[
  SceneColor(0xFFFFFFFF),
  SceneColor(0xFF1A1A1A),
  SceneColor(0xFF2B1B12),
  SceneColor(0xFF4A2F1F),
  SceneColor(0xFF6B4226),
  SceneColor(0xFFD8C9BD),
  SceneColor(0xFFE8632B),
  SceneColor(0xFFF2B705),
  SceneColor(0xFF3E7C4F),
  SceneColor(0xFF4A64D0),
];

/// A row of colour dots, the current one ringed. [allowNone] adds the "no
/// colour" dot first — right for a fill, wrong for a text colour or a colour
/// parameter, which always have one.
class SceneSwatches extends StatelessWidget {
  const SceneSwatches({
    super.key,
    required this.current,
    required this.onPick,
    this.allowNone = true,
  });

  final SceneColor? current;
  final void Function(SceneColor?) onPick;
  final bool allowNone;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: FwSpacing.sm,
    runSpacing: FwSpacing.sm,
    children: [
      for (var color in [if (allowNone) null, ...scenePalette])
        Tappable(
          onTap: () => onPick(color),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color?.flutter,
              shape: BoxShape.circle,
              border: Border.all(
                color: current == color
                    ? context.colors.accent
                    : context.colors.line,
                width: current == color ? 2 : 1,
              ),
            ),
            child: color == null
                ? Icon(
                    Icons.block,
                    size: FwIconSize.sm,
                    color: context.colors.mut2,
                  )
                : null,
          ),
        ),
    ],
  );
}
