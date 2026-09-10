// The property table pinned to the model: every row reads back what it
// writes, survives the wire and the authored JSON, and is spelled and read
// by the file. A row that drifts from its field fails here, not in a demo.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

/// A value off the default for every kind, so a write is visible.
Object? sample(SceneProp p) => switch (p.kind) {
  // The two the file and the wire spell themselves: their value is the
  // node's other rows, so there is nothing of their own to sample.
  ScenePropKind.style || ScenePropKind.args => null,
  ScenePropKind.number => 7.5,
  ScenePropKind.integer => 3,
  ScenePropKind.string => 'Hello',
  ScenePropKind.boolean => !(p.defaultValue! as bool),
  ScenePropKind.color => const SceneColor(0xFF123456),
  ScenePropKind.size => p.name == 'width' ? double.infinity : 42.0,
  ScenePropKind.sizes => <double?>[double.infinity, 48, null],
  ScenePropKind.layers => const <TextLayer>[
    StrokeLayer(
      width: 14,
      join: SceneStrokeJoin.miter,
      paint: SolidPaint(SceneColor(0xFF120720)),
      blur: 3,
      dx: -1,
      dy: 2,
      opacity: 0.8,
    ),
    FillLayer(
      paint: LinearPaint(
        colors: [SceneColor(0xFFFFF3B0), SceneColor(0xFFFFB020)],
        stops: [0, 1],
        begin: SceneAlignment.centerLeft,
        end: SceneAlignment.centerRight,
      ),
    ),
    FillLayer(
      paint: RadialPaint(
        colors: [SceneColor(0xFFFFFFFF), SceneColor(0xFFFF2D95)],
        stops: [0, 0.8],
        center: SceneAlignment(0.2, -0.4),
        radius: 1.5,
      ),
    ),
    StrokeLayer(
      width: 3,
      paint: SweepPaint(
        colors: [SceneColor(0xFFFF2D95), SceneColor(0xFF00E5FF)],
        center: SceneAlignment(-0.5, 0),
        startAngle: 45,
        endAngle: 300,
      ),
    ),
    FillLayer(),
  ],
  ScenePropKind.axes => const {'wght': 640.0, 'wdth': 85.0},
  ScenePropKind.edges => p.quad!([1.0, 2.0, 3.0, 4.0]),
  ScenePropKind.choice => p.choices!.values.firstWhere(
    (v) => v != p.defaultValue,
  ),
};

SceneNode fresh(SceneProp p) => switch (p.kindName) {
  // A registered kind's row lives on that kind's node.
  var kind? => KindNode(sceneKindNamed(kind)!, name: 'n'),
  null => switch (p.owner) {
    ScenePropOwner.frame || ScenePropOwner.any => FrameNode(name: 'n'),
    ScenePropOwner.text => TextNode('', name: 'n'),
    ScenePropOwner.shape => ShapeNode(name: 'n'),
    ScenePropOwner.takesArgs => SceneRefNode.read('Card', name: 'n'),
  },
};

void main() {
  test('names are unique per kind and every node kind has its common rows', () {
    // A row name is per kind — `scenePropNamed` reads the node's own rows —
    // so two kinds may share one (the model and the surface share their
    // placement), and the hand-written kinds' rows must not collide with
    // the common ones or each other.
    var handWritten = sceneProps.where((p) => p.kindName == null);
    var names = handWritten.map((p) => p.name).toList();
    expect(names.toSet().length, names.length);
    for (var kind in sceneKinds) {
      var own = kind.props.map((p) => p.name).toList();
      expect(own.toSet().length, own.length, reason: kind.name);
      expect(
        own.toSet().intersection(sceneCommonProps.map((p) => p.name).toSet()),
        isEmpty,
        reason: kind.name,
      );
    }
    for (var node in [FrameNode(), TextNode(''), ShapeNode()]) {
      expect(
        scenePropsOf(node).map((p) => p.name),
        containsAll(sceneCommonProps.map((p) => p.name)),
      );
    }
  });

  test("the style fields are the table's style subset, both ways", () {
    expect(
      sceneTextStyleFields.map((f) => f.name),
      sceneStyleProps.map((p) => p.name),
      reason: 'a style sets exactly the style rows, in the same order',
    );
    // The rest of a text's rows are its own — the positional text, and the
    // two the paragraph decides rather than the type.
    expect(sceneTextOwnProps.map((p) => p.name), [
      'text',
      'style',
      'align',
      'maxLines',
    ]);
  });

  test('a style round-trips through its own values, and copyWith deltas', () {
    var set = <String, Object>{};
    for (var p in sceneStyleProps) {
      set[p.name] = sample(p)!;
    }
    var style = SceneTextStyle.fromValues(set);
    expect(style.values, set, reason: 'fromValues is the inverse of values');
    // Every field survives a copy, and a delta lands on exactly one of them.
    expect(style.copyWith(), style);
    var bigger = style.copyWith(fontSize: 99);
    expect(bigger.fontSize, 99);
    expect(bigger.copyWith(fontSize: style.fontSize), style);
  });

  test('a node built from a style reads every property back', () {
    var set = <String, Object>{};
    for (var p in sceneStyleProps) {
      set[p.name] = sample(p)!;
    }
    var node = TextNode('x', style: SceneTextStyle.fromValues(set));
    for (var p in sceneStyleProps) {
      expect(p.read(node), set[p.name], reason: p.name);
    }
  });

  test('every kind of key resolves, and an unknown one does not', () {
    // Four kinds of thing answer to one flat namespace of strings. Each used
    // to be recognised by an ad-hoc test in whichever file needed it, which
    // is how a side came to be known to the grammar and unknown to the read
    // plane. This is the list; a fifth kind that is not on it fails here.
    var frame = FrameNode(name: 'f');
    var text = TextNode('x', name: 't');
    var ref = SceneRefNode.read('Card', name: 'r');
    expect(resolveSceneKey(frame, 'fill'), isA<ScenePropertyKey>());
    expect(
      resolveSceneKey(frame, 'paddingLeft'),
      isA<ScenePartKey>()
          .having((k) => k.prop.name, 'row', 'padding')
          .having((k) => k.part, 'side', 'paddingLeft'),
    );
    expect(
      resolveSceneKey(ref, 'args.headline'),
      isA<ScenePartKey>()
          .having((k) => k.prop.name, 'row', 'args')
          .having((k) => k.part, 'name', 'headline'),
    );
    expect(
      resolveSceneKey(text, styleBindingKey),
      isA<ScenePropertyKey>().having((k) => k.prop.name, 'row', 'style'),
      reason: 'a style is a property whose type is a style',
    );
    // And what each node kind cannot hold.
    expect(resolveSceneKey(frame, styleBindingKey), isNull, reason: 'no type');
    expect(resolveSceneKey(frame, 'args.headline'), isNull, reason: 'no args');
    expect(resolveSceneKey(frame, 'fontSize'), isNull, reason: 'not a text');
    expect(resolveSceneKey(frame, 'nonesuch'), isNull);
  });

  for (var p in sceneProps) {
    // The two rows the file and the wire spell themselves have no value of
    // their own to sample, spell or encode — their value IS the node's other
    // rows. They are rows to be KEYS; `every kind of key resolves` is what
    // covers them.
    if (p.byHand && p.kind != ScenePropKind.string) continue;
    var label = p.kindName == null ? p.name : '${p.kindName}.${p.name}';
    test('$label reads back what it writes, and starts at its default', () {
      var node = fresh(p);
      expect(isSceneDefault(p, p.read(node)), isTrue, reason: 'fresh node');
      var v = sample(p);
      p.write(node, v);
      expect(p.read(node), v);
      expect(p.fromWire(p.toWire(v)), v, reason: 'wire codec');
    });

    test('$label survives the authored JSON', () {
      var node = fresh(p);
      p.write(node, sample(p));
      var doc = SceneDocument(FrameNode(name: 'root')..children.add(node));
      var back = sceneFromJson(doc.toJson());
      expect(p.read(back.root.children.single), sample(p));
    });

    test('$label is spelled and read by the file', () {
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
