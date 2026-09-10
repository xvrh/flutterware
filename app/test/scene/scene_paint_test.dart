// The paint values on their own: a pass changes by copy and keeps what it
// was not told to change, and every paint survives the wire it crosses to
// the guest on.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/layer_presets.dart';

void main() {
  group('a pass changes by copy', () {
    const stroke = StrokeLayer(
      width: 6,
      join: SceneStrokeJoin.bevel,
      paint: SolidPaint(SceneColor(0xFF120720)),
      blur: 2,
      dx: 1,
      dy: 2,
      opacity: 0.5,
    );

    test('one field changes and the rest are kept', () {
      expect(
        stroke.copyWith(dx: 9, width: 3),
        const StrokeLayer(
          width: 3,
          join: SceneStrokeJoin.bevel,
          paint: SolidPaint(SceneColor(0xFF120720)),
          blur: 2,
          dx: 9,
          dy: 2,
          opacity: 0.5,
        ),
      );
      expect(stroke.copyWith(), stroke);
    });

    test('a paint can be taken away, which copyWith cannot say', () {
      var plain = stroke.withPaint(null);
      expect(plain.paint, isNull);
      expect(plain, isA<StrokeLayer>());
      expect(plain.width, 6);
    });

    test('a fill copies the same way', () {
      const fill = FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400)), dy: 4);
      expect(
        fill.copyWith(opacity: 0.25),
        const FillLayer(
          paint: SolidPaint(SceneColor(0xFFFFC400)),
          dy: 4,
          opacity: 0.25,
        ),
      );
      expect(fill.withPaint(null), const FillLayer(dy: 4));
    });
  });

  group('a gradient', () {
    const a = SceneColor(0xFFFF0000);
    const b = SceneColor(0xFF00FF00);
    const c = SceneColor(0xFF0000FF);

    test('spreads its colours evenly when it names no stops', () {
      expect(const LinearPaint(colors: [a, b, c]).resolvedStops, [0, 0.5, 1]);
    });

    test('keeps stops that give one per colour, and ignores any others', () {
      expect(
        const LinearPaint(colors: [a, b], stops: [0.2, 0.9]).resolvedStops,
        [0.2, 0.9],
      );
      expect(
        const LinearPaint(colors: [a, b, c], stops: [0, 1]).resolvedStops,
        [0, 0.5, 1],
      );
    });

    test('changes its stops and keeps its shape', () {
      const g = LinearPaint(
        colors: [a, b],
        begin: SceneAlignment.centerLeft,
        end: SceneAlignment.centerRight,
      );
      expect(
        g.withStops([a, b, c], [0, 0.3, 1]),
        const LinearPaint(
          colors: [a, b, c],
          stops: [0, 0.3, 1],
          begin: SceneAlignment.centerLeft,
          end: SceneAlignment.centerRight,
        ),
      );
    });
  });

  group('a radial gradient', () {
    const a = SceneColor(0xFFFFFFFF);
    const b = SceneColor(0xFF000000);

    test('says nothing on the wire that a default already says', () {
      expect(const RadialPaint(colors: [a, b]).toWire(), {
        'k': 'radial',
        'colors': [a.argb, b.argb],
      });
    });

    test('round-trips its centre and radius', () {
      const g = RadialPaint(
        colors: [a, b],
        stops: [0, 0.7],
        center: SceneAlignment(0.2, -0.4),
        radius: 1.5,
      );
      expect(ScenePaint.fromWire(g.toWire()), g);
    });

    test('changes its shape by copy and keeps its stops', () {
      const g = RadialPaint(colors: [a, b], stops: [0, 0.7]);
      expect(
        g.copyWith(radius: 0.5),
        const RadialPaint(colors: [a, b], stops: [0, 0.7], radius: 0.5),
      );
    });
  });

  group('a sweep gradient', () {
    const a = SceneColor(0xFFFF0000);
    const b = SceneColor(0xFF0000FF);

    test('says nothing on the wire that a default already says', () {
      expect(const SweepPaint(colors: [a, b]).toWire(), {
        'k': 'sweep',
        'colors': [a.argb, b.argb],
      });
    });

    test('round-trips its centre and angles', () {
      const g = SweepPaint(
        colors: [a, b],
        center: SceneAlignment(-0.5, 0),
        startAngle: 45,
        endAngle: 300,
      );
      expect(ScenePaint.fromWire(g.toWire()), g);
      expect(g.copyWith(startAngle: 90).startAngle, 90);
      expect(g.copyWith(startAngle: 90).endAngle, 300);
    });
  });

  group("a pass's box", () {
    test('is on the wire only when it is not the text', () {
      expect(const FillLayer().toWire(), {'k': 'fill'});
      const lined = StrokeLayer(width: 4, box: SceneLayerBox.line);
      expect(lined.toWire()['box'], 'line');
      expect(TextLayer.fromWire(lined.toWire()), lined);
    });

    test('is carried by every copy', () {
      const lined = FillLayer(box: SceneLayerBox.line);
      expect(lined.copyWith(dx: 3).box, SceneLayerBox.line);
      expect(
        lined.withPaint(const SolidPaint(SceneColor(0xFF000000))).box,
        SceneLayerBox.line,
      );
      expect(const FillLayer().copyWith(box: SceneLayerBox.line), lined);
    });
  });

  test('a pass says its blend on the wire only when it is not normal', () {
    expect(const FillLayer().toWire().containsKey('blend'), isFalse);
    const multiplied = FillLayer(blend: SceneBlendMode.multiply);
    expect(multiplied.toWire()['blend'], 'multiply');
    expect(TextLayer.fromWire(multiplied.toWire()), multiplied);
    expect(multiplied.copyWith(dx: 2).blend, SceneBlendMode.multiply);
    expect(multiplied.withPaint(null).blend, SceneBlendMode.multiply);
  });

  group('wire decoding is total', () {
    test(
      'a stroke layer falls back to its defaults on garbage numeric fields',
      () {
        expect(
          TextLayer.fromWire({
            'k': 'stroke',
            'w': 'wide',
            'blur': true,
            'dx': 'x',
            'dy': false,
            'o': [],
          }),
          const StrokeLayer(),
        );
      },
    );

    test('a colour list skips an element that is not a number', () {
      var paint = ScenePaint.fromWire({
        'k': 'linear',
        'colors': [0xFFFF0000, 'x', 0xFF0000FF],
      });
      expect(
        paint,
        const LinearPaint(
          colors: [SceneColor(0xFFFF0000), SceneColor(0xFF0000FF)],
        ),
      );
    });

    test('a colors field that is not a list is treated as empty', () {
      expect(
        ScenePaint.fromWire({'k': 'linear', 'colors': 'oops'}),
        const LinearPaint(colors: []),
      );
    });

    test('a stops list skips an element that is not a number', () {
      var paint =
          ScenePaint.fromWire({
                'k': 'linear',
                'colors': [0xFFFF0000, 0xFF00FF00],
                'stops': [0, 'x'],
              })!
              as LinearPaint;
      // Skipping the bad element leaves a stops list shorter than colors;
      // resolvedStops already falls back to the even spread for that case.
      expect(paint.stops, [0.0]);
      expect(paint.resolvedStops, [0, 1]);
    });

    test(
      'an alignment with a non-number element falls back to the default',
      () {
        var paint =
            ScenePaint.fromWire({
                  'k': 'radial',
                  'colors': [0xFFFF0000, 0xFF00FF00],
                  'center': ['a', 1],
                })!
                as RadialPaint;
        expect(paint.center, SceneAlignment.center);
      },
    );

    test(
      'a radius or angle that is not a number falls back to the default',
      () {
        var radial =
            ScenePaint.fromWire({
                  'k': 'radial',
                  'colors': [0xFFFF0000, 0xFF00FF00],
                  'r': 'wide',
                })!
                as RadialPaint;
        expect(radial.radius, 1);

        var sweep =
            ScenePaint.fromWire({
                  'k': 'sweep',
                  'colors': [0xFFFF0000, 0xFF00FF00],
                  'a0': true,
                  'a1': 'x',
                })!
                as SweepPaint;
        expect(sweep.startAngle, 0);
        expect(sweep.endAngle, 360);
      },
    );
  });

  test('the gloss preset keeps its sheen per line when scaled', () {
    var gloss = layerPresets.firstWhere((p) => p.name == 'Gloss');
    var small = gloss.forSize(27);
    expect(small.last.box, SceneLayerBox.line);
    expect(small.last.paint, isA<LinearPaint>());
    expect(small.first.paint, isNull, reason: 'the text keeps its own colour');
  });
}
