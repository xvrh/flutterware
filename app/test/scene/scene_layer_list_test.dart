// The layer list's paint editor, driven: a colour pass becomes a gradient
// through the kind picker, and a gradient pass can be laid across each line.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/ui/layer_list.dart';
import 'package:flutterware_app/src/ui/theme.dart';

const _red = SceneColor(0xFFFF0000);

void main() {
  late List<TextLayer> layers;
  late List<String> labels;

  Future<void> pump(WidgetTester tester, List<TextLayer> start) async {
    // Tall enough for the blend picker's sixteen rows to open on screen.
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    layers = start;
    labels = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: StatefulBuilder(
                builder: (context, setState) => SceneLayerList(
                  layers: layers,
                  fontSize: 54,
                  color: const Color(0xFFFFFFFF),
                  onChanged: (next, {required label, mergeKey}) {
                    labels.add(label);
                    setState(() => layers = next);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pick(WidgetTester tester, Key picker, String choice) async {
    await tester.tap(find.byKey(picker));
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a colour pass becomes a gradient that fades out of it', (
    tester,
  ) async {
    await pump(tester, const [FillLayer(paint: SolidPaint(_red))]);
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();
    await pick(tester, const ValueKey('paint:kind'), 'Linear');
    expect(
      layers.single.paint,
      const LinearPaint(colors: [_red, SceneColor(0x00FF0000)]),
    );
    expect(find.byKey(const ValueKey('gradient:bar')), findsOneWidget);
  });

  testWidgets('a gradient pass can be laid across each line', (tester) async {
    await pump(tester, const [
      FillLayer(paint: LinearPaint(colors: [_red, SceneColor(0xFF0000FF)])),
    ]);
    await tester.tap(find.textContaining('Fill'));
    await tester.pumpAndSettle();
    await pick(tester, const ValueKey('layer:box'), 'Each line');
    expect(layers.single.box, SceneLayerBox.line);
    expect(find.textContaining('per line'), findsOneWidget);
  });

  testWidgets('a colour pass offers no box: it would change nothing', (
    tester,
  ) async {
    await pump(tester, const [FillLayer(paint: SolidPaint(_red))]);
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('layer:box')), findsNothing);
  });
}
