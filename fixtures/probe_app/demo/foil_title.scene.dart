//@flutterware:scene=0.9
import 'package:flutterware/scene_authoring.dart';

class FoilTitle extends SceneDefinition {
  late final headline = TextNode(
    'Gold\nEdition',
    style: SceneTextStyle(
      fontFamily: 'Archivo',
      fontSize: 150,
      letterSpacing: -3,
      lineHeight: 0.95,
      color: SceneColor(0xFFB9852F),
      textCase: SceneTextCase.upper,
      layers: [
        StrokeLayer(width: 14, paint: SolidPaint(SceneColor(0xFF140D05))),
        FillLayer(
          paint: ShaderPaint(
            'shaders/foil.frag',
            uniforms: {
              'uAngle': [0.6],
              'uSpeed': [0.35],
              'uShine': [1, 0.92, 0.6],
            },
          ),
          box: SceneLayerBox.line,
        ),
      ],
      axes: {'wght': 900},
    ),
    align: SceneTextAlign.center,
  );
  @override
  late final root = FrameNode(
    width: 1080,
    height: 720,
    fill: SceneColor(0xFF1A140C),
    layout: NodeLayout.column,
    clip: true,
    mainAlign: SceneMainAxisAlignment.center,
    children: [headline],
  );
}

class FoilShimmer(super.scene) extends SceneMotion<FoilTitle> {
  late final settle = scene.headline.animate(
    opacity: MotionTrack([
      MotionKey(at: 0.ms, value: 0.9),
      MotionKey(at: 3000.ms, value: 1),
    ]),
  );
  @override
  late final timeline = ParExpr([settle]);
  FoilShimmer copy(FoilTitle scene) => copyStateInto(FoilShimmer(scene));
}
