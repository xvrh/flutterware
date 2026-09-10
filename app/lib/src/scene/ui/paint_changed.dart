import 'package:flutterware/scene_authoring.dart';

/// A change to the paint, with the words for its undo entry.
typedef PaintChanged = void Function(
  ScenePaint? next, {
  required String label,
  String? mergeKey,
});
