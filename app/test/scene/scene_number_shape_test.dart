// What a number field WRITES, as against what it merely shows.
//
// A drag accumulates in display units and lands on whatever the arithmetic
// produces. The field printed `19.96` and the model held
// `19.959895833333427`, which is not a private number: it goes into the
// library file, into the generated `SceneTokens` and into every scene that
// reads the token, where a decision nobody made becomes seventeen digits of
// noise in a diff.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/layer_presets.dart';
import 'package:flutterware_app/src/scene/ui/number_shape.dart';
import 'package:flutterware_app/src/scene/ui/tokens_host.dart';

void main() {
  group('a shape settles a value', () {
    test('to the precision it prints, and inside its bounds', () {
      var size = shapeFor(TextNode('', name: 't'), 'fontSize');
      expect(size.decimals, 2);
      expect(size.settled(19.959895833333427), 19.96);
      expect(size.format(size.settled(19.959895833333427)), '19.96');
      // Leading lives in 0.8..2, so a pixel of drag is worth 0.004 — the
      // rounding is what keeps the sum of four hundred of them clean.
      var leading = shapeFor(TextNode('', name: 't'), 'lineHeight');
      expect(leading.settled(3.6031249999999986), 3.6);
      // Clamped first: an opacity is a proportion.
      const opacity = SceneNumberShape(
        perPixel: 0.005,
        decimals: 2,
        min: 0,
        max: 1,
      );
      expect(opacity.settled(1.4), 1.0);
      expect(opacity.settled(-0.2), 0.0);
      expect(opacity.settled(0.33333333), 0.33);
    });

    test('a whole number stays whole, and milliseconds have no decimals', () {
      const pixels = SceneNumberShape.pixels;
      expect(pixels.settled(28), 28.0);
      expect(SceneNumberShape.milliseconds.settled(16.6667), 17.0);
    });

    test('leaves a non-finite value alone rather than making one up', () {
      const shape = SceneNumberShape(perPixel: 1, decimals: 2);
      expect(shape.settled(double.infinity), double.infinity);
      expect(shape.settled(double.nan).isNaN, isTrue);
    });
  });

  test('a preset retold at another size rounds as it scales', () {
    // A stroke of 3 authored at 21 becomes 7.714285714285714 at 54 unless
    // the arithmetic rounds where the field that edits it rounds.
    for (var preset in layerPresets) {
      for (var layer in preset.forSize(54)) {
        for (var v in [
          layer.blur,
          layer.dx,
          layer.dy,
          if (layer case StrokeLayer(:var width)) width,
        ]) {
          expect(
            v,
            (v * 100).roundToDouble() / 100,
            reason: '${preset.name} carries $v',
          );
        }
      }
    }
  });

  test('a caption prints two decimals at most', () {
    // The editor's own values are rounded already; a hand-written file's
    // are not, and a caption is not the place to print all of one.
    expect(shortNumber(28), '28');
    expect(shortNumber(19.959895833333427), '19.96');
    expect(shortNumber(1.5), '1.5');
    expect(shortNumber(1.10), '1.1');
    expect(shortNumber(-0.125), '-0.13');
  });
}
