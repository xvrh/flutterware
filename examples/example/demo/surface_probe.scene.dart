//@flutterware:scene=0.8
// Which way a surface faces, and whose slot it shows — from a camera at
// yaw 0, two rigs and two quads. The rigs both stand at rotation 0 and each
// must show its own slot (red on the left, green on the right): two loads
// of one asset share their materials, and this is the picture that caught
// it. The quads face the camera at 0 and away at 180; the label reads the
// right way round on the one that faces. `showcase_export_test.dart` walks
// this file; the frames it dumps are the check.
import 'package:flutterware/scene_authoring.dart';

class SurfaceProbe extends SceneDefinition {
  late final qla = TextNode(
    'quad 0',
    style: SceneTextStyle(
      fontSize: 40,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFF161A22),
    ),
  );
  late final qca = FrameNode(
    width: 320,
    height: 200,
    fill: SceneColor(0xFFFFD166),
    layout: NodeLayout.column,
    mainAlign: SceneMainAxisAlignment.center,
    crossAlign: SceneCrossAxisAlignment.center,
    children: [qla],
  );
  late final qa = SurfaceNode(
    positionX: -150,
    positionY: 70,
    rotationY: 0,
    size: 50,
    children: [qca],
  );
  late final rla = TextNode(
    'rig 0',
    style: SceneTextStyle(
      fontSize: 64,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  late final rca = FrameNode(
    width: 360,
    height: 780,
    fill: SceneColor(0xFFE53935),
    layout: NodeLayout.column,
    mainAlign: SceneMainAxisAlignment.center,
    crossAlign: SceneCrossAxisAlignment.center,
    children: [rla],
  );
  late final ra = SurfaceNode(
    asset: 'assets/models/probe_rig_blender.glb',
    mesh: 'Screen',
    positionX: -150,
    positionY: -60,
    rotationY: 0,
    size: 50,
    children: [rca],
  );
  late final qlc = TextNode(
    'quad 180',
    style: SceneTextStyle(
      fontSize: 40,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFF161A22),
    ),
  );
  late final qcc = FrameNode(
    width: 320,
    height: 200,
    fill: SceneColor(0xFF4DD0E1),
    layout: NodeLayout.column,
    mainAlign: SceneMainAxisAlignment.center,
    crossAlign: SceneCrossAxisAlignment.center,
    children: [qlc],
  );
  late final qc = SurfaceNode(
    positionX: 150,
    positionY: 70,
    rotationY: 180,
    size: 50,
    children: [qcc],
  );
  late final rlc = TextNode(
    'rig 180',
    style: SceneTextStyle(
      fontSize: 64,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  late final rcc = FrameNode(
    width: 360,
    height: 780,
    fill: SceneColor(0xFF43A047),
    layout: NodeLayout.column,
    mainAlign: SceneMainAxisAlignment.center,
    crossAlign: SceneCrossAxisAlignment.center,
    children: [rlc],
  );
  late final rc = SurfaceNode(
    asset: 'assets/models/probe_rig_blender.glb',
    mesh: 'Screen',
    positionX: 150,
    positionY: -60,
    rotationY: 0,
    size: 50,
    children: [rcc],
  );
  late final view = View3DNode(
    x: 0,
    y: 0,
    width: 1024,
    height: 576,
    yaw: 0,
    pitch: 0,
    distance: 420,
    fov: 40,
    children: [qa, ra, qc, rc],
  );
  @override
  late final root = FrameNode(
    width: 1024,
    height: 576,
    fill: SceneColor(0xFF161A22),
    children: [view],
  );
}

class SurfaceProbeHold(super.scene) extends SceneMotion<SurfaceProbe> {
  late final hold = scene.view.animate(
    exposure: MotionTrack([
      MotionKey(at: 0.ms, value: 1),
      MotionKey(at: 1000.ms, value: 1),
    ]),
  );
  @override
  late final timeline = ParExpr([hold]);
  SurfaceProbeHold copy(SurfaceProbe scene) =>
      copyStateInto(SurfaceProbeHold(scene));
}
