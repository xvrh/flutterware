// The paint values on their own: a pass changes by copy and keeps what it
// was not told to change, and every paint survives the wire it crosses to
// the guest on.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';

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
}
