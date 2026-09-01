import 'package:flutterware/scene_authoring.dart';

/// Writes what a renderer measured onto the nodes, and bumps the geometry
/// epoch once if anything moved — the door both renderers use: the guest
/// over the wire, and a `SceneView` mounted beside the editor in a demo.
void applyMeasuredRects(SceneDocument doc, Map<String, SceneRect> rects) {
  var changed = false;
  for (var (node, _) in doc.walk()) {
    var rect = rects[node.name];
    if (rect == null || node.measured == rect) continue;
    node.measured = rect;
    changed = true;
  }
  if (changed) doc.geometryEpoch.value++;
}
