// A node kind as data — the property table's move, one level up.
//
// The table made a property a row: the wire, the JSON, the file's named
// arguments, the read plane, a copy and an undo restore walk it, and what
// stays hand-written is the constructor, the renderer and the structure. A
// *kind* was still five hand switches — the parser's dispatch, the emitter's
// head, the deep copy, the renderer, the inspector — plus an owner enum and
// the motion's own list. A kind described here is data those hosts consult:
// what the file spells it, which rows it carries, whether it holds children.
// What a kind still owns by hand is exactly what a property does: its
// constructor, because a scene file IS a call to it, and its renderer,
// because a renderer is what the kind MEANS — and the renderer is registered
// on the view rather than written into it, so a kind and its renderer can
// live in a package the core never imports.
//
// `KindNode` (model.dart) is the one node class every registered kind
// shares: its rows live in a map the table reads and writes, and a thin
// subclass per kind gives the file its constructor and the motion its typed
// `animate()`.
library;

import 'props.dart';
import 'view3d.dart';

/// One node kind, as the file, the wire and the editor know it.
class SceneKind {
  const SceneKind(
    this.name, {
    required this.constructor,
    required this.props,
    this.children = false,
    this.help,
  });

  /// The wire's and the JSON's `kind`, and the node's `typeName`.
  final String name;

  /// What the file spells — the constructor's name.
  final String constructor;

  /// The kind's own rows, after the common ones. Each is a map-backed row
  /// made with [SceneProp.value].
  final List<SceneProp> props;

  /// Whether the file's `children: [...]` places nodes under it.
  final bool children;

  /// One line the editor shows under the kind's rows — how the kind is
  /// worked on the canvas, when that is not obvious from the rows.
  final String? help;
}

/// Every registered kind. Seeded with the kinds the core ships as data;
/// a package adds its own with [registerSceneKind] before a scene is read.
final sceneKinds = <SceneKind>[view3dKind, modelKind, surfaceKind];

void registerSceneKind(SceneKind kind) {
  if (sceneKinds.any((k) => k.name == kind.name)) return;
  sceneKinds.add(kind);
}

SceneKind? sceneKindNamed(String name) {
  for (var k in sceneKinds) {
    if (k.name == name) return k;
  }
  return null;
}

SceneKind? sceneKindByConstructor(String constructor) {
  for (var k in sceneKinds) {
    if (k.constructor == constructor) return k;
  }
  return null;
}
