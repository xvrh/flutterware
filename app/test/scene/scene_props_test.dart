// The property table pinned to the model: every row reads back what it
// writes, survives the wire and the authored JSON, and is spelled and read
// by the file. A row that drifts from its field fails here, not in a demo.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

/// A value off the default for every kind, so a write is visible.
Object? sample(SceneProp p) => switch (p.kind) {
  ScenePropKind.number => 7.5,
  ScenePropKind.integer => 3,
  ScenePropKind.string => 'Hello',
  ScenePropKind.boolean => !(p.defaultValue! as bool),
  ScenePropKind.color => const SceneColor(0xFF123456),
  ScenePropKind.size => p.name == 'width' ? double.infinity : 42.0,
  ScenePropKind.sizes => <double?>[double.infinity, 48, null],
  ScenePropKind.edges => p.quad!([1.0, 2.0, 3.0, 4.0]),
  ScenePropKind.choice => p.choices!.values.firstWhere(
    (v) => v != p.defaultValue,
  ),
};

SceneNode fresh(SceneProp p) => switch (p.owner) {
  ScenePropOwner.frame || ScenePropOwner.any => FrameNode(name: 'n'),
  ScenePropOwner.text => TextNode('', name: 'n'),
  ScenePropOwner.shape => ShapeNode(name: 'n'),
};

void main() {
  test('names are unique and every node kind has its common rows', () {
    var names = sceneProps.map((p) => p.name).toList();
    expect(names.toSet().length, names.length);
    for (var node in [FrameNode(), TextNode(''), ShapeNode()]) {
      expect(
        scenePropsOf(node).map((p) => p.name),
        containsAll(sceneCommonProps.map((p) => p.name)),
      );
    }
  });

  for (var p in sceneProps) {
    test('${p.name} reads back what it writes, and starts at its default', () {
      var node = fresh(p);
      expect(isSceneDefault(p, p.read(node)), isTrue, reason: 'fresh node');
      var v = sample(p);
      p.write(node, v);
      expect(p.read(node), v);
      expect(p.fromWire(p.toWire(v)), v, reason: 'wire codec');
    });

    test('${p.name} survives the authored JSON', () {
      var node = fresh(p);
      p.write(node, sample(p));
      var doc = SceneDocument(FrameNode(name: 'root')..children.add(node));
      var back = sceneFromJson(doc.toJson());
      expect(p.read(back.root.children.single), sample(p));
    });

    test('${p.name} is spelled and read by the file', () {
      var node = fresh(p);
      p.write(node, sample(p));
      var doc = SceneDocument(
        FrameNode(name: 'root')
          ..width = 100
          ..height = 100
          ..children.add(node),
      );
      var out = emitSceneFile(doc, className: 'Pin');
      expect(
        out,
        contains(
          p.name == 'text'
              ? "'Hello'"
              : p.sides == null
              ? '${p.name}:'
              : '${p.sides![0]}:',
        ),
      );
      var parsed = parseSceneFile(out);
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      expect(p.read(parsed.doc!.root.children.single), sample(p));
    });
  }

  test(
    'a property bound at its default is still written, as the reference',
    () {
      var node = FrameNode(name: 'box')
        ..width = 10
        ..height = 10
        ..opacity = 1
        ..bindings['opacity'] = const ParamRef('alpha');
      var doc = SceneDocument(
        FrameNode(name: 'root')
          ..width = 100
          ..height = 100
          ..children.add(node),
      )..params.add(SceneParamDecl('alpha', SceneParamKind.number, 1.0));
      var out = emitSceneFile(doc, className: 'Pin');
      expect(out, contains('opacity: alpha'));
    },
  );
}
