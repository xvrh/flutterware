import 'dart:math' as math;

import 'package:flutterware/motion_vocabulary.dart';
import 'package:flutterware_app/src/motion/property_editor.dart';
import 'package:test/test.dart';

void main() {
  group('which control a number gets', () {
    test('an angle gets a dial, because degrees do not say which way', () {
      expect(shapeFor('rotate').editor, MotionEditorShape.dial);
    });

    test('a property whose range is its meaning gets a slider', () {
      for (var name in ['opacity', 'progress', 'scale', 'scaleX', 'scaleY']) {
        expect(shapeFor(name).editor, MotionEditorShape.slider, reason: name);
      }
    });

    test('an open-ended property is scrubbed, not slid', () {
      // ±200px, 0..64px, 0..40σ — a position along those says nothing a nudge
      // does not say better, and a slider would cap what is legitimate.
      for (var name in ['translateX', 'translateY', 'padding', 'blur']) {
        expect(shapeFor(name).editor, MotionEditorShape.scrub, reason: name);
      }
    });

    test('a property the vocabulary does not carry still gets an editor', () {
      expect(shapeFor('nonsense').editor, MotionEditorShape.scrub);
    });

    test('milliseconds are scrubbed', () {
      expect(MotionNumberShape.milliseconds.editor, MotionEditorShape.scrub);
    });

    test('every property in the vocabulary has one', () {
      for (var prop in motionVocabulary) {
        expect(
          () => MotionNumberShape.of(prop).editor,
          returnsNormally,
          reason: prop.name,
        );
      }
    });
  });

  group('the drag', () {
    test('covers a bounded range in a few hundred pixels', () {
      // The same gesture has to mean a sensible amount whether the property
      // runs 0..1 or 0..64, which is the whole reason this is not a constant.
      expect(shapeFor('opacity').perPixel, closeTo(1 / 300, 1e-9));
      expect(shapeFor('padding').perPixel, closeTo(64 / 300, 1e-9));
    });

    test('falls back to a unit a pixel when nothing is bounded', () {
      expect(shapeFor('nonsense').perPixel, 1);
      expect(MotionNumberShape.milliseconds.perPixel, 1);
    });

    test('moves an angle in degrees, not radians', () {
      // A pixel worth of radians would be a third of a turn.
      expect(shapeFor('rotate').perPixel, 0.5);
    });
  });

  group('degrees in, radians out', () {
    var rotate = shapeFor('rotate');

    test('the file keeps radians and the field shows degrees', () {
      expect(rotate.toDisplay(math.pi), closeTo(180, 1e-9));
      expect(rotate.fromDisplay(180), closeTo(math.pi, 1e-9));
    });

    test('round-trips, so typing back what is shown changes nothing', () {
      expect(
        rotate.fromDisplay(rotate.toDisplay(-0.055)),
        closeTo(-0.055, 1e-9),
      );
    });

    test('leaves everything else alone', () {
      var opacity = shapeFor('opacity');
      expect(opacity.toDisplay(0.4), 0.4);
      expect(opacity.fromDisplay(0.4), 0.4);
    });

    test('the dial spans a whole turn either way', () {
      var (min, max) = rotate.displayRange;
      expect(min, closeTo(-360, 0.1));
      expect(max, closeTo(360, 0.1));
    });
  });

  group('printing', () {
    test('degrees to a tenth, everything else to a hundredth', () {
      expect(shapeFor('rotate').format(math.pi / 4), '45.0');
      expect(shapeFor('opacity').format(0.5), '0.50');
    });

    test('milliseconds are whole', () {
      expect(MotionNumberShape.milliseconds.format(420), '420');
    });

    test('the unit is shown, never parsed back', () {
      expect(shapeFor('rotate').unit, '°');
      expect(shapeFor('translateY').unit, 'px');
      expect(shapeFor('opacity').unit, '');
      expect(MotionNumberShape.milliseconds.unit, 'ms');
    });
  });

  group('the floor', () {
    test('a duration cannot be dragged below zero', () {
      // A hard floor, unlike a soft bound: a span of -20ms is not a span, where
      // a scale of 40 is merely unusual.
      expect(MotionNumberShape.milliseconds.clampStored(-20), 0);
      expect(MotionNumberShape.milliseconds.clampStored(20), 20);
    });

    test('a tuned property has none, because a soft bound is a hint', () {
      expect(shapeFor('opacity').clampStored(-3), -3);
      expect(shapeFor('scale').clampStored(40), 40);
    });
  });
}
