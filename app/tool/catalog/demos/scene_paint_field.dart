import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/ui/paint_field.dart';
import 'package:flutterware_app/src/ui/design/design.dart';

import 'app_theme.dart';

/// One paint field per kind a pass can be painted with, at the width the
/// inspector gives a layer's detail — each live, so a kind can be switched
/// and a stop dragged in the preview.
///
/// What it answers is whether the four shapes read as one control: the
/// picker, then a colour or a bar, then the numbers that shape it, at one
/// type size down the column.
@Preview(name: 'Paint field', group: 'Scene', wrapper: wrapInAppTheme)
Widget scenePaintField() => const _Paints();

@Preview(name: 'Paint field · dark', group: 'Scene', wrapper: wrapInDarkTheme)
Widget scenePaintFieldDark() => const _Paints();

class _Paints extends StatefulWidget {
  const _Paints();

  @override
  State<_Paints> createState() => _PaintsState();
}

class _PaintsState extends State<_Paints> {
  final _paints = <ScenePaint?>[
    const SolidPaint(SceneColor(0xFFFFC400)),
    const LinearPaint(
      colors: [
        SceneColor(0xFFFFF3B0),
        SceneColor(0xFFFFB020),
        SceneColor(0xFF8A4B00),
      ],
      stops: [0, 0.55, 1],
    ),
    const RadialPaint(
      colors: [SceneColor(0xFFFFFFFF), SceneColor(0x00FFFFFF)],
      radius: 0.8,
    ),
    const SweepPaint(
      colors: [
        SceneColor(0xFFFF2D95),
        SceneColor(0xFF00E5FF),
        SceneColor(0xFFFF2D95),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.panel,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(FwSpacing.lg),
      child: Wrap(
        spacing: FwSpacing.xxl,
        runSpacing: FwSpacing.xxl,
        children: [
          for (var i = 0; i < _paints.length; i++)
            SizedBox(
              width: 240,
              child: ScenePaintField(
                paint: _paints[i],
                own: const SceneColor(0xFFFFFFFF),
                onChanged: (next, {required label, mergeKey}) =>
                    setState(() => _paints[i] = next),
              ),
            ),
        ],
      ),
    ),
  );
}
