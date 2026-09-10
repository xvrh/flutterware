// A shader pass, read back as pixels. The probe shader writes the uniform
// under test as a colour, and the test font draws every glyph as a filled
// box, so the ink's colour is the uniform's value.
//
// Plain `test()`s with real async: a program's load never completes under
// `testWidgets`' fake clock.
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware/src/scene/shader_programs.dart'
    hide precacheSceneShaders;

const probe = 'test/scene/shaders/probe.frag';
const bare = 'test/scene/shaders/probe_bare.frag';

FillLayer shaderPass(
  double mode, {
  Map<String, List<double>> more = const {},
  SceneLayerBox box = SceneLayerBox.text,
  double dx = 0,
  double opacity = 1,
}) => FillLayer(
  paint: ShaderPaint(
    probe,
    uniforms: {
      'uMode': [mode],
      ...more,
    },
  ),
  box: box,
  dx: dx,
  opacity: opacity,
);

/// [layers] over [text] at 20px, painted by the stack painter alone — no
/// widget tree, so the box is exactly [width] by the text's height. Ten `M`s
/// are one 200×20 line. The image is widened by the furthest a pass is
/// moved, so a moved pass is still all in the picture.
Future<(SceneTextStackPainter, ui.Image)> _paintWith(
  List<TextLayer> layers, {
  String text = 'MMMMMMMMMM',
  double width = 200,
  Color color = const Color(0xFFFFFFFF),
  ValueListenable<Duration>? time,
}) async {
  var painter = SceneTextStackPainter(
    span: TextSpan(text: text),
    style: TextStyle(fontSize: 20, height: 1, color: color),
    layers: layers,
    textAlign: TextAlign.left,
    maxLines: null,
    overflow: TextOverflow.clip,
    textDirection: TextDirection.ltr,
    scaler: TextScaler.noScaling,
    widthBasis: TextWidthBasis.parent,
    heightBehavior: null,
    time: time,
  );
  _sizes[painter] = _sizeFor(text, width);
  return (painter, await _repaint(painter));
}

Future<ui.Image> _paint(
  List<TextLayer> layers, {
  String text = 'MMMMMMMMMM',
  double width = 200,
  Color color = const Color(0xFFFFFFFF),
}) async {
  var (_, image) = await _paintWith(
    layers,
    text: text,
    width: width,
    color: color,
  );
  return image;
}

/// The box each painter was made for.
final _sizes = Expando<Size>();

/// [painter] painted again, into a fresh picture.
Future<ui.Image> _repaint(SceneTextStackPainter painter) {
  var size = _sizes[painter]!;
  var reach = painter.layers.map((l) => l.dx).fold(0.0, max);
  var recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  return recorder.endRecording().toImage(
    (size.width + reach).ceil(),
    size.height.ceil(),
  );
}

/// The box a `Text` would have been given: [width], and the height its
/// lines take there.
Size _sizeFor(String text, double width) {
  var layout = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 20, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  var height = layout.height;
  layout.dispose();
  return Size(width, height);
}

/// An image's pixels, as `toByteData` hands them over: RGBA, premultiplied.
class _Pixels {
  _Pixels(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final ByteData bytes;

  int channel(int x, int y, int c) => bytes.getUint8((y * width + x) * 4 + c);
  bool inked(int x, int y) => channel(x, y, 3) >= 128;
}

Future<_Pixels> _pixels(ui.Image image) async =>
    _Pixels(image.width, image.height, (await image.toByteData())!);

/// Where to look, worked out from the pixels themselves.
typedef _Region = Rect Function(_Pixels pixels);

/// The mean colour of the inked pixels in [region] (the whole image when
/// null), each channel 0–1 — ink only, so the gaps between lines do not
/// dilute it.
Future<({double r, double g, double b, double a})> _mean(
  ui.Image image, {
  _Region? region,
}) async {
  var pixels = await _pixels(image);
  var whole = Rect.fromLTWH(0, 0, pixels.width + 0.0, pixels.height + 0.0);
  var rect = region?.call(pixels).intersect(whole) ?? whole;
  var (r, g, b, a, n) = (0, 0, 0, 0, 0);
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
      if (!pixels.inked(x, y)) continue;
      r += pixels.channel(x, y, 0);
      g += pixels.channel(x, y, 1);
      b += pixels.channel(x, y, 2);
      a += pixels.channel(x, y, 3);
      n++;
    }
  }
  expect(n, greaterThan(0), reason: 'no ink in $rect');
  return (r: r / n / 255, g: g / n / 255, b: b / n / 255, a: a / n / 255);
}

/// How many pixels are ink at all.
Future<int> _inkCount(ui.Image image) async {
  var pixels = await _pixels(image);
  var n = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (pixels.channel(x, y, 3) > 0) n++;
    }
  }
  return n;
}

/// The rows [line] covers: at 20px with a height of 1, every line is 20px
/// and they touch, so ink alone cannot tell where one ends.
(int, int) _lineRows(int line) => (line * 20, line * 20 + 20);

/// The first or last inked column of the rows [top] to [bottom], as a one
/// pixel wide strip down them.
Rect _edgeColumn(_Pixels pixels, int top, int bottom, {required bool left}) {
  var middle = (top + bottom) ~/ 2;
  var xs = [
    for (var x = 0; x < pixels.width; x++)
      if (pixels.inked(x, middle)) x,
  ];
  expect(xs, isNotEmpty, reason: 'no ink on row $middle');
  var x = left ? xs.first : xs.last;
  return Rect.fromLTRB(
    x.toDouble(),
    top.toDouble(),
    x + 1.0,
    bottom.toDouble(),
  );
}

Rect _leftmostInkColumn(_Pixels pixels) =>
    _edgeColumn(pixels, 0, pixels.height, left: true);

Rect _rightmostInkColumn(_Pixels pixels) =>
    _edgeColumn(pixels, 0, pixels.height, left: false);

_Region _leftInkOfLine(int line) => (pixels) {
  var (top, bottom) = _lineRows(line);
  return _edgeColumn(pixels, top, bottom, left: true);
};

_Region _rightInkOfLine(int line) => (pixels) {
  var (top, bottom) = _lineRows(line);
  return _edgeColumn(pixels, top, bottom, left: false);
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> loadBoth() async {
    await SceneShaderPrograms.instance.load(probe);
    await SceneShaderPrograms.instance.load(bare);
  }

  setUpAll(loadBoth);

  test("a shader pass paints the author's uniform", () async {
    var image = await _paint([
      shaderPass(
        0,
        more: {
          'uTint': [0, 1, 0],
        },
      ),
    ]);
    var ink = await _mean(image);
    expect(ink.g, greaterThan(0.95));
    expect(ink.r, lessThan(0.05));
  });

  test("uColor is the text's own colour", () async {
    var image = await _paint([shaderPass(3)], color: const Color(0xFF0000FF));
    expect((await _mean(image)).b, greaterThan(0.95));
  });

  test('scene time changes the picture with no relayout', () async {
    var time = ValueNotifier(const Duration(milliseconds: 250));
    var (painter, first) = await _paintWith([shaderPass(1)], time: time);
    expect((await _mean(first)).r, closeTo(0.25, 0.02));
    time.value = const Duration(milliseconds: 750);
    var second = await _repaint(painter);
    expect((await _mean(second)).r, closeTo(0.75, 0.02));
  });

  test('the box starts at zero wherever the pass is moved', () async {
    var image = await _paint([shaderPass(2, dx: 40)]);
    expect((await _mean(image, region: _leftmostInkColumn)).r, lessThan(0.1));
    expect(
      (await _mean(image, region: _rightmostInkColumn)).r,
      greaterThan(0.9),
    );
  });

  test('a line box restarts the shader on every line', () async {
    // Two lines: a width that wraps the text once.
    var image = await _paint(
      [shaderPass(2, box: SceneLayerBox.line)],
      text: 'MMMM MMMM',
      width: 90,
    );
    expect((await _mean(image, region: _leftInkOfLine(0))).r, lessThan(0.1));
    expect((await _mean(image, region: _leftInkOfLine(1))).r, lessThan(0.1));
    // And each line runs the whole of it: measured across the text, the end
    // of an 80px line in a 90px box would stop short of the red end.
    expect(
      (await _mean(image, region: _rightInkOfLine(0))).r,
      greaterThan(0.95),
    );
    expect(
      (await _mean(image, region: _rightInkOfLine(1))).r,
      greaterThan(0.95),
    );
  });

  test("the pass's opacity is the layer's", () async {
    // 0.6, not 0.5: `_mean` counts a pixel as ink from alpha 128.
    var image = await _paint([
      shaderPass(
        0,
        more: {
          'uTint': [1, 1, 1],
        },
        opacity: 0.6,
      ),
    ]);
    expect((await _mean(image)).a, closeTo(0.6, 0.05));
  });

  test('nothing is painted until the program has loaded', () async {
    addTearDown(loadBoth);
    var programs = SceneShaderPrograms.instance..reset();
    var image = await _paint([
      shaderPass(
        0,
        more: {
          'uTint': [1, 1, 1],
        },
      ),
    ]);
    expect(await _inkCount(image), 0);
    await programs.load(probe);
    var after = await _paint([
      shaderPass(
        0,
        more: {
          'uTint': [1, 1, 1],
        },
      ),
    ]);
    expect(await _inkCount(after), greaterThan(0));
  });

  test(
    'an undeclared uniform is skipped and reported once, never thrown',
    () async {
      var said = <String>[];
      var saved = debugPrint;
      debugPrint = (m, {wrapWidth}) => said.add(m ?? '');
      addTearDown(() => debugPrint = saved);
      await _paint([
        shaderPass(
          0,
          more: {
            'uTint': [1, 0, 0],
            'uNope': [1],
          },
        ),
      ]);
      await _paint([
        shaderPass(
          0,
          more: {
            'uTint': [1, 0, 0],
            'uNope': [1],
          },
        ),
      ]);
      expect(said.where((m) => m.contains('uNope')), hasLength(1));
    },
  );

  test('a shader with none of the renderer uniforms still paints', () async {
    var image = await _paint([
      const FillLayer(
        paint: ShaderPaint(
          bare,
          uniforms: {
            'uTint': [0, 0, 1],
          },
        ),
      ),
    ]);
    expect((await _mean(image)).b, greaterThan(0.95));
  });

  test('a pass with no asset paints nothing', () async {
    var image = await _paint([const FillLayer(paint: ShaderPaint(''))]);
    expect(await _inkCount(image), 0);
  });
}
