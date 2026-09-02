// Zooming the canvas: the guest renders more pixels rather than bigger ones,
// and a trackpad gesture is the canvas's, never a node's.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/measure.dart';
import 'package:flutterware_app/src/scene/ui/canvas.dart';
import 'package:flutterware_app/src/scene/zoom.dart';
import 'package:flutterware_app/src/ui/theme.dart';

void main() {
  group('guest ratio', () {
    test('below life-size the host ratio; above, more texels per point', () {
      expect(
        sceneGuestRatio(width: 1024, height: 500, hostRatio: 2, zoom: 0.5),
        2,
      );
      expect(
        sceneGuestRatio(width: 1024, height: 500, hostRatio: 2, zoom: 3),
        6,
      );
    });

    test('snapped so the texture is a whole number of texels wide', () {
      var ratio = sceneGuestRatio(
        width: 1024,
        height: 500,
        hostRatio: 2,
        zoom: 1.37,
      );
      expect((1024 * ratio) % 1, closeTo(0, 1e-9));
      expect(ratio, closeTo(2.74, 0.002));
    });

    test('capped by the pixel budget, never refused', () {
      var ratio = sceneGuestRatio(
        width: 1024,
        height: 500,
        hostRatio: 2,
        zoom: 40,
      );
      expect(1024 * ratio * 500 * ratio, lessThanOrEqualTo(64e6 * 1.001));
      expect(ratio, greaterThan(2));
    });
  });

  group('on the canvas', () {
    late SceneEditor editor;
    var zooms = <double>[];

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      zooms = [];
      editor = SceneEditor(coffeeBannerDraft());
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme,
          home: Material(
            child: SceneCanvas(
              editor,
              onZoom: zooms.add,
              content: SceneView(
                editor.doc,
                onMeasured: (r) => applyMeasuredRects(editor.doc, r),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets(
      'a two-finger scroll over a node pans the canvas, not the node',
      (tester) async {
        await pump(tester);
        var headline = editor.doc.nodeNamed('headline')!;
        var view = tester.getRect(find.byType(SceneView));
        var scale = view.width / 1024;
        var over = view.topLeft + Offset(200 * scale, 150 * scale);
        var before = tester.getRect(find.byType(SceneView));
        var (x, y) = (headline.x, headline.y);

        var gesture = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await gesture.panZoomStart(over);
        await tester.pump();
        await gesture.panZoomUpdate(over, pan: const Offset(0, -40));
        await tester.pump();
        await gesture.panZoomEnd();
        await tester.pump();

        expect((headline.x, headline.y), (x, y), reason: 'the node stayed');
        expect(editor.selectionNames, isEmpty);
        expect(
          tester.getRect(find.byType(SceneView)).top,
          isNot(before.top),
          reason: 'the canvas moved',
        );
      },
    );

    testWidgets('a pinch zooms, and the zoom is reported', (tester) async {
      await pump(tester);
      var view = tester.getRect(find.byType(SceneView));
      var gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(view.center);
      await tester.pump();
      await gesture.panZoomUpdate(view.center, scale: 2);
      await tester.pump();
      await gesture.panZoomEnd();
      await tester.pump();
      expect(zooms, isNotEmpty);
      expect(zooms.last, greaterThan(1.5));
      expect(
        tester.getRect(find.byType(SceneView)).width,
        greaterThan(view.width * 1.5),
      );
    });

    testWidgets('a mouse drag still moves the node', (tester) async {
      await pump(tester);
      // `copy` is the addressable node at that point: its children only
      // become targets once it is selected.
      var copy = editor.doc.nodeNamed('copy')!;
      var view = tester.getRect(find.byType(SceneView));
      var scale = view.width / 1024;
      var over = view.topLeft + Offset(200 * scale, 150 * scale);
      var (x, y) = (copy.x, copy.y);
      var gesture = await tester.startGesture(
        over,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(Offset(30 * scale, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(editor.selectionNames, ['copy']);
      expect(copy.x, closeTo(x + 30, 2));
      expect(copy.y, y);
    });
  });
}
