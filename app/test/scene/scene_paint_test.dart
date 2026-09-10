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
      expect((plain as StrokeLayer).width, 6);
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
}
