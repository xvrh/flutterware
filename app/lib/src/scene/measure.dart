import 'package:flutterware/scene_authoring.dart';

/// Writes what a renderer measured onto the nodes, and bumps the geometry
/// epoch once if anything moved — the door both renderers use: the guest
/// over the wire, and a `SceneView` mounted beside the editor in a demo.
void applyMeasuredRects(SceneDocument doc, Map<SceneNode, SceneRect> rects) {
  var changed = false;
  for (var entry in rects.entries) {
    if (entry.key.measured == entry.value) continue;
    entry.key.measured = entry.value;
    changed = true;
  }
  if (changed) doc.geometryEpoch.value++;
}
