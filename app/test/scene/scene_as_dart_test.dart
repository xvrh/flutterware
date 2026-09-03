// One file, two graders.
//
// `sample.scene.dart` beside this test is a real scene file, in exactly the
// spelling the editor emits. It is imported below — so the compiler grades
// it — and read off disk and re-emitted — so the parser grades it. A change
// that satisfies one and not the other fails here, which is the only thing
// keeping the two halves of the format honest now that the file is Dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

import 'sample.scene.dart';
import 'sample_widget.dart' as app;

void main() {
  test('a scene file is a class an app can instantiate', () {
    // Typed arguments, no JSON, no lookup: the constructor is the thing an
    // export loop turns per language.
    var scene = SampleScene(headline: 'Kaffee, schneller');
    expect(scene.headline, 'Kaffee, schneller');
    expect(scene.root.width, 400);
    expect(scene.root.children.first.children.length, 2);
  });

  test('a parameter reaches the node that reads it', () {
    var scene = SampleScene(
      headline: 'Kaffee, schneller',
      tint: const SceneColor(0xFF00FF00),
    );
    expect(scene.title.text, 'Kaffee, schneller');
    expect(scene.badge.fill, const SceneColor(0xFF00FF00));
    // The default is the mockup, and a second instance is untouched by the
    // first — a scene is a value, not a singleton.
    expect(SampleScene().title.text, 'Fresh coffee, faster');
  });

  test('a node has no name until something reads the source', () {
    // Identity at runtime is the object. `scene.title` is the reference, and
    // it is the compiler that checks it.
    expect(SampleScene().title.name, isEmpty);
    expect(
      identical(SampleScene().root.children.first, SampleScene().bar),
      isFalse,
    );
    var one = SampleScene();
    expect(identical(one.root.children.first, one.bar), isTrue);
  });

  testWidgets('and it mounts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: SceneView(SampleScene(headline: 'Hello').scene)),
      ),
    );
    expect(find.text('Hello'), findsOneWidget);
    expect(tester.getSize(find.byType(SceneView)), const Size(400, 120));
  });

  test('a motion names its target with a checked identifier', () {
    var scene = SampleScene();
    var motion = SampleIntro(scene);

    // `scene.title` is the node itself, so the group needs nothing resolved
    // — and a motion pointed at a node the scene does not declare, or at a
    // property the node's kind cannot animate, does not compile. There is
    // no test that can be written for that, which is the point.
    expect(identical(motion.titleIn.node, scene.title), isTrue);
    expect(identical(motion.badgePop.node, scene.badge), isTrue);
    expect(motion.titleIn.tracks.keys, containsAll(['opacity', 'translateY']));
    // A property nobody animated is a track the group does not carry.
    expect(motion.titleIn.tracks.containsKey('scale'), isFalse);
  });

  test('a motion parameter reaches the key that reads it', () {
    var scene = SampleScene();
    var slid = SampleIntro(scene, slideFrom: 80);
    expect(slid.titleIn.tracks['translateY']!.keys.first.value, 80.0);
    expect(
      SampleIntro(scene).titleIn.tracks['translateY']!.keys.first.value,
      24.0,
    );
  });

  testWidgets('and the motion plays, with no document and no lookup', (
    tester,
  ) async {
    var scene = SampleScene();
    var motion = SampleIntro(scene);
    var play = playTimeline(motion.timeline);

    // Par of a 260ms group and a 240ms one placed at 120: 360, not 500.
    expect(play.duration, const Duration(milliseconds: 360));
    play.apply(Duration.zero);
    expect(scene.title.fxRendered('opacity'), 0.0);
    play.apply(const Duration(milliseconds: 260));
    expect(scene.title.fxRendered('opacity'), 1.0);
    // The badge is placed 120ms in, so at 260 it is 140 through its 240.
    expect(scene.badge.fxRendered('scale') as double, greaterThan(0.6));
    play.clearFx();
    expect(scene.title.fxRendered('opacity'), 1.0, reason: 'back to authored');
  });

  test('a repeat is a closure, and the compiler checks its fields', () {
    // `line.label` is a record field, so a cell reading one the data does
    // not have is a program that does not build — which is why this can
    // only assert the shape, never the failure.
    var scene = SampleScene(
      rows: const [
        (label: 'Cocoa', value: '2kg'),
        (label: 'Syrup', value: '6 × 750ml'),
        (label: 'Cups', value: '500'),
      ],
    );
    var rep = scene.table.repeated!;
    expect(rep.items, hasLength(3));
    // The frame's own cells are the FIRST item's, so the row in the file
    // and the row on screen are the same row.
    expect((scene.table.children.first as TextNode).text, 'Cocoa');
    // And it is still one frame: what multiplies is the picture.
    expect(scene.root.children, hasLength(3));
    expect(scene.scene.expand(scene.table), hasLength(3));
  });

  testWidgets('and every row of it is drawn', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Center(child: SceneView(SampleScene().scene))),
    );
    expect(find.text('Beans'), findsOneWidget);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('12L'), findsOneWidget);
  });

  testWidgets('an external node builds the app widget from the file', (
    tester,
  ) async {
    // No registry, and nothing to register: the builder is in the file, so
    // the widget and its mockup live where the compiler checks them.
    await tester.pumpWidget(
      MaterialApp(home: Center(child: SceneView(SampleScene().scene))),
    );
    expect(find.byType(app.SampleChip), findsOneWidget);
    expect(find.text('new'), findsOneWidget);
  });

  testWidgets('and a scene that arrived as data resolves it by label', (
    tester,
  ) async {
    // The editor's path: a closure is not data and cannot cross the wire,
    // so the builders are learned from the scene classes the app declared.
    var wire = jsonDecode(
      jsonEncode(SampleScene().scene.toWire()),
    ) as Map<String, Object?>;
    var arrived = sceneFromWire((wire['root']! as Map).cast<String, Object?>());
    // Found by its label, not its name: a compiled scene has no names, and
    // the label is exactly what does cross the wire.
    var ext = [
      for (var (node, _) in arrived.walk())
        if (node is ExternalNode) node,
    ].single;
    expect(ext.entry, 'SampleChip');
    expect(ext.build, isNull, reason: 'the closure did not travel');

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SceneView(
            arrived,
            externals: sceneExternalsFrom([SampleScene.new]),
          ),
        ),
      ),
    );
    expect(find.byType(app.SampleChip), findsOneWidget);
  });

  test('and the builder it could not read comes back verbatim', () {
    var source = File('test/scene/sample.scene.dart').readAsStringSync();
    var parsed = parseSceneFile(source);
    var chip = parsed.doc!.nodeNamed('chip')! as ExternalNode;
    // Kept as a span, because the tool cannot author app code — and must
    // not lose it either.
    expect(chip.buildSource, startsWith('(a) => app.SampleChip('));
    expect(chip.build, isNull, reason: 'read, not compiled');
  });

  test('and the parser reads the same file back, unchanged', () {
    var path = 'test/scene/sample.scene.dart';
    var source = File(path).readAsStringSync();
    var parsed = parseSceneFile(source);
    expect(parsed.refusals, isEmpty, reason: '$path must satisfy the grammar');
    expect(
      emitSceneFile(
        parsed.doc!,
        className: parsed.className!,
        motions: parsed.motions,
        imports: parsed.imports,
      ),
      source,
      reason: 'the file the compiler accepts is the file the editor writes',
    );
    // The names the compiler cannot see are exactly what the parser supplies.
    expect(parsed.doc!.nodeNamed('title'), isNotNull);
    expect(parsed.doc!.root.name, 'root');
    // And the parsed motion's groups hold the parsed scene's nodes, which is
    // the same relationship the compiled pair has.
    var group = parsed.motions['SampleIntro']!.groupNamed('titleIn')!;
    expect(identical(group.node, parsed.doc!.nodeNamed('title')), isTrue);
    // The read document's repeat draws the same rows the closure does,
    // rebuilt from what a reader could record.
    var table = parsed.doc!.nodeNamed('table')! as FrameNode;
    expect(table.repeated?.source, 'rows');
    expect(parsed.doc!.expand(table), hasLength(2));
  });
}
