// The painter's shape, which is what its cost rests on: no stack, no extra
// work; a stack, and the widget that does the LAYOUT draws nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

Widget _mount(List<TextLayer> layers) => MaterialApp(
  home: Center(
    child: LayeredText(
      span: const TextSpan(text: 'GAME OVER'),
      style: const TextStyle(fontSize: 32, color: Color(0xFFFFC400)),
      layers: layers,
      textAlign: TextAlign.left,
      maxLines: null,
    ),
  ),
);

/// Scoped, because a `MaterialApp` brings CustomPaints of its own.
final _passes = find.descendant(
  of: find.byType(LayeredText),
  matching: find.byType(CustomPaint),
);

void main() {
  testWidgets('no stack is the plain text it always was', (tester) async {
    await tester.pumpWidget(_mount(const []));
    expect(_passes, findsNothing);
    var text = tester.widget<Text>(find.byType(Text));
    expect(text.style?.color, const Color(0xFFFFC400));
  });

  testWidgets('a stack replaces the single draw rather than adding to it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mount(const [
        StrokeLayer(width: 8, paint: SolidPaint(SceneColor(0xFF120720))),
        FillLayer(),
      ]),
    );
    expect(_passes, findsOneWidget);
    var text = tester.widget<Text>(find.byType(Text));
    expect(
      text.style?.color,
      const Color(0x00000000),
      reason: 'transparent, not an Opacity: a save layer for the same nothing',
    );
  });

  testWidgets('the box is the same whether it is painted once or nine times', (
    tester,
  ) async {
    await tester.pumpWidget(_mount(const []));
    var plain = tester.getSize(find.byType(LayeredText));
    await tester.pumpWidget(
      _mount(const [
        FillLayer(paint: SolidPaint(SceneColor(0xFF120720)), dx: 8, dy: 8),
        StrokeLayer(width: 12, paint: SolidPaint(SceneColor(0xFF120720))),
        FillLayer(),
      ]),
    );
    expect(
      tester.getSize(find.byType(LayeredText)),
      plain,
      reason: 'a pass may change paint, never layout',
    );
  });
}
