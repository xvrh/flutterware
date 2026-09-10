// A per-line gradient pass used to size a vector capture's raster patch
// from a band that ran 1e4px past the box — Picture.toImage fails outright
// on a patch that size, unhandled, taking flutter_tester down with it.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/render.dart';
import 'package:flutterware/src/scene/core/values.dart';
import 'package:flutterware/src/scene/layered_text.dart';

final _key = GlobalKey();

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(key: _key, child: child),
    ),
  ),
);

void main() {
  testWidgets('captureSvg of a per-line gradient pass completes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 200,
          height: 60,
          child: LayeredText(
            span: const TextSpan(text: 'One\nTwo'),
            style: const TextStyle(fontSize: 20),
            layers: const [
              FillLayer(
                paint: LinearPaint(
                  colors: [SceneColor(0xFFFF0000), SceneColor(0xFF0000FF)],
                ),
                box: SceneLayerBox.line,
              ),
            ],
            textAlign: TextAlign.left,
            maxLines: null,
          ),
        ),
      ),
    );
    var boundary =
        tester.renderObject(find.byKey(_key)) as RenderRepaintBoundary;
    await tester.runAsync(() async {
      var result = await captureSvg(boundary);
      expect(result.text, contains('<svg'));
    });
  }, timeout: const Timeout(Duration(seconds: 30)));
}
