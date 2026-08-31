import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/render.dart';
import 'package:flutterware/src/render/capture.dart';
import 'package:flutterware/src/render/model.dart';
import 'package:flutterware/src/render/svg_writer.dart';

/// Layer effects used to vanish silently: pushLayer inlined the child and
/// the effect never existed. These tests pin the fix — every effect becomes
/// a span the unsupported-op policy decides over, and the raster lane
/// replays reproducible ones with the effect applied.
final _key = GlobalKey();

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: RepaintBoundary(key: _key, child: child),
    ),
  ),
);

RenderRepaintBoundary _boundary(WidgetTester tester) =>
    tester.renderObject(find.byKey(_key)) as RenderRepaintBoundary;

/// Red channel minus blue channel at a fractional position of a patch.
int _redMinusBlue(VgRecording rec, int rasterId, double fx) {
  var image = rec.images[rasterId]!;
  var rgba = rec.imageRgba[rasterId]!;
  var x = (image.width * fx).floor();
  var y = image.height ~/ 2;
  var o = (y * image.width + x) * 4;
  return rgba[o] - rgba[o + 2];
}

void main() {
  testWidgets('a shader mask replays into a patch with the mask applied', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ShaderMask(
          shaderCallback: (bounds) =>
              const LinearGradient(colors: [Colors.red, Colors.blue])
                  .createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Container(width: 100, height: 40, color: Colors.white),
        ),
      ),
    );
    var boundary = _boundary(tester);
    await tester.runAsync(() async {
      var recording = captureVector(boundary);
      var begin = recording.ops.whereType<VgBeginEffect>().single;
      expect(begin.kind, VgEffectKind.shaderMask);
      await recording.rasterizeUnsupported();
      await recording.encodeImages();
      expect(begin.rasterId, isNotNull);

      // The patch really carries the mask: red end left, blue end right.
      expect(_redMinusBlue(recording, begin.rasterId!, 0.05), greaterThan(60));
      expect(_redMinusBlue(recording, begin.rasterId!, 0.95), lessThan(-60));

      // The writer places the patch and swallows the child's own ops.
      var svg = writeSvg(recording, boundary.size, []);
      expect(svg, contains('<image'));
      expect(svg, isNot(contains('<rect')));
      expect(
        recording.collectWarnings(CaptureOptions()).map((w) => w.kind),
        contains(RenderWarningKind.effectRasterized),
      );
    });
  });

  testWidgets('a color filter routes through pushColorFilter into a patch', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Color(0xFFFF0000),
            BlendMode.srcIn,
          ),
          child: Container(width: 80, height: 40, color: Colors.white),
        ),
      ),
    );
    var boundary = _boundary(tester);
    await tester.runAsync(() async {
      var recording = captureVector(boundary);
      var begin = recording.ops.whereType<VgBeginEffect>().single;
      expect(begin.kind, VgEffectKind.colorFilter);
      await recording.rasterizeUnsupported();
      await recording.encodeImages();
      expect(begin.rasterId, isNotNull);
      // The white child came out red: the filter applied in the replay.
      expect(_redMinusBlue(recording, begin.rasterId!, 0.5), greaterThan(200));

      // UnsupportedPolicy.skip leaves the whole span out instead.
      var svg = writeSvg(
        recording,
        boundary.size,
        [],
        options: CaptureOptions(unsupported: UnsupportedPolicy.skip),
      );
      expect(svg, isNot(contains('<image')));
      expect(svg, isNot(contains('<rect')));
    });
  });

  testWidgets('a backdrop filter keeps its child and warns', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 120,
          height: 60,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.orange),
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: const Center(child: Text('frosted')),
              ),
            ],
          ),
        ),
      ),
    );
    var boundary = _boundary(tester);
    await tester.runAsync(() async {
      // Through the public facade: the honest contract is the point.
      var result = await captureSvg(boundary);
      expect(
        result.warnings.map((w) => w.kind),
        contains(RenderWarningKind.effectDropped),
      );
      // The child is not lost with the effect: the text still renders.
      expect(result.text, contains('frosted'));
    });
  });

  testWidgets('drawArc is captured as a path', (tester) async {
    await tester.pumpWidget(
      _host(CustomPaint(size: const Size(60, 60), painter: _ArcPainter())),
    );
    var recording = captureVector(_boundary(tester));
    expect(recording.unhandled, isEmpty);
    expect(recording.ops.whereType<VgDrawPath>(), isNotEmpty);
  });
}

class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      const Rect.fromLTWH(5, 5, 50, 50),
      0.4,
      3.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF1E88E5),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
