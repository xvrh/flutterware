// One file, two graders.
//
// `sample.scene.dart` beside this test is a real scene file, in exactly the
// spelling the editor emits. It is imported below — so the compiler grades
// it — and read off disk and re-emitted — so the parser grades it. A change
// that satisfies one and not the other fails here, which is the only thing
// keeping the two halves of the format honest now that the file is Dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

import 'sample.scene.dart';

void main() {
  test('a scene file is a class an app can instantiate', () {
    // Typed arguments, no JSON, no lookup: the constructor is the thing an
    // export loop turns per language.
    var scene = SampleScene(headline: 'Kaffee, schneller');
    expect(scene.headline, 'Kaffee, schneller');
    expect(scene.root.width, 400);
    expect(scene.root.children.single.children.length, 2);
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
      identical(SampleScene().root.children.single, SampleScene().bar),
      isFalse,
    );
    var one = SampleScene();
    expect(identical(one.root.children.single, one.bar), isTrue);
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
  });
}
