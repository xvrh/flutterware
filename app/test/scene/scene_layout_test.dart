// Auto-layout, first half: a size is fixed, hug or fill, and the root's
// three shapes are the three things a scene is for.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

void main() {
  /// A column of two boxes inside a root, with sizes the test sets.
  (SceneDocument, FrameNode, ShapeNode, ShapeNode) column() {
    var top = ShapeNode('top')..fill = const SceneColor(0xFFFF0000);
    var bottom = ShapeNode('bottom')..fill = const SceneColor(0xFF00FF00);
    var stack = FrameNode('stack', layout: NodeLayout.column)
      ..gap = 0
      ..children.addAll([top, bottom]);
    var root = FrameNode('root')
      ..width = 200
      ..height = 400
      ..children.add(stack);
    return (SceneDocument(root), stack, top, bottom);
  }

  testWidgets('fill takes what the parent has left', (tester) async {
    var (doc, stack, top, bottom) = column();
    stack
      ..width = 200
      ..height = 400;
    top.height = 100;
    bottom.height = double.infinity;

    var rects = <String, SceneRect>{};
    await tester.pumpWidget(
      MaterialApp(home: SceneView(doc, onMeasured: rects.addAll)),
    );
    await tester.pump();

    expect(rects['top']!.height, 100);
    expect(
      rects['bottom']!.height,
      300,
      reason: 'the rest of the column, not its content',
    );
  });

  testWidgets('a filling child cannot take what a hugging parent has not', (
    tester,
  ) async {
    var (doc, stack, top, bottom) = column();
    // The column hugs its height, so there is no leftover to hand out. This
    // must render rather than throw: the editor is where the contradiction
    // is shown, not the renderer.
    stack.height = null;
    top.height = 60;
    bottom.height = double.infinity;

    var rects = <String, SceneRect>{};
    await tester.pumpWidget(
      MaterialApp(home: SceneView(doc, onMeasured: rects.addAll)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(rects['top']!.height, 60);
  });

  testWidgets('the root comes in three shapes', (tester) async {
    Future<Size> rootSize(
      void Function(FrameNode root) shape, {
      NodeLayout layout = NodeLayout.absolute,
    }) async {
      var child = ShapeNode('block')
        ..width = 120
        ..height = 90;
      var root = FrameNode('root', layout: layout)..children.add(child);
      shape(root);
      var doc = SceneDocument(root);
      await tester.pumpWidget(
        MaterialApp(
          // Loose, not tight: a tight box would force every root to the
          // same size and prove nothing.
          home: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
              child: SceneView(doc),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byType(SceneView));
    }

    // A banner: fixed on both axes.
    expect(
      await rootSize(
        (r) => r
          ..width = 300
          ..height = 150,
      ),
      const Size(300, 150),
    );

    // A screen: whatever the app gives it.
    expect(
      await rootSize(
        (r) => r
          ..width = double.infinity
          ..height = double.infinity,
      ),
      const Size(500, 400),
    );

    // A document: fixed across, growing down. It has to be a column, not a
    // free-positioned frame: a stack of positioned children has no content
    // extent, so an absolute frame takes the room it is offered and cannot
    // hug. That is a rule the editor owes the author, not a bug here.
    expect(
      await rootSize(
        (r) => r
          ..width = 400
          ..height = null,
        layout: NodeLayout.column,
      ),
      const Size(400, 90),
      reason: 'as tall as its content',
    );
  });

  test('fill survives the wire, the JSON and the file', () {
    var child = ShapeNode('block')
      ..width = double.infinity
      ..height = 40;
    var root = FrameNode('root', layout: NodeLayout.column)
      ..width = 320
      ..height = double.infinity
      ..children.add(child);
    var doc = SceneDocument(root);

    // The wire and the JSON both refuse a non-finite double, so the word is
    // what travels.
    expect(jsonEncode(doc.toWire()), contains('fill'));
    var back = sceneFromJson(
      jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>,
    );
    expect(back.root.heightFills, isTrue);
    expect(back.root.width, 320);
    expect(back.root.children.single.widthFills, isTrue);

    // And the file spells it the way Flutter does.
    var source = emitSceneFile(doc, className: 'Sized');
    expect(source, contains('double.infinity'));
    var parsed = parseSceneFile(source);
    expect(parsed.ok, isTrue, reason: parsed.refusals.join('; '));
    expect(parsed.doc!.root.heightFills, isTrue);
    expect(parsed.doc!.root.children.single.widthFills, isTrue);
    expect(
      emitSceneFile(parsed.doc!, className: 'Sized'),
      source,
      reason: 'and round trips',
    );
  });
}
