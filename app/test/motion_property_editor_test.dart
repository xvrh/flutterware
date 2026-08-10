import 'dart:math' as math;

import 'package:flutterware/motion_vocabulary.dart';
import 'package:flutterware_app/src/motion/property_editor.dart';
import 'package:test/test.dart';

void main() {
  group('which control a property gets', () {
    test('an angle gets a dial, because degrees do not say which way', () {
      expect(editorShapeFor(propFor('rotate')), MotionEditorShape.dial);
    });

    test('a property whose range is its meaning gets a slider', () {
      for (var name in ['opacity', 'progress', 'scale', 'scaleX', 'scaleY']) {
        expect(
          editorShapeFor(propFor(name)),
          MotionEditorShape.slider,
          reason: name,
        );
      }
    });

    test('an open-ended property is scrubbed, not slid', () {
      // ±200px, 0..64px, 0..40σ — a position along those says nothing a nudge
      // does not say better, and a slider would cap what is legitimate.
      for (var name in ['translateX', 'translateY', 'padding', 'blur']) {
        expect(
          editorShapeFor(propFor(name)),
          MotionEditorShape.scrub,
          reason: name,
        );
      }
    });

    test('a property the vocabulary does not carry still gets an editor', () {
      expect(editorShapeFor(propFor('nonsense')), MotionEditorShape.scrub);
      expect(editorShapeFor(null), MotionEditorShape.scrub);
    });

    test('every property in the vocabulary has one', () {
      for (var prop in motionVocabulary) {
        expect(() => editorShapeFor(prop), returnsNormally, reason: prop.name);
      }
    });
  });

  group('the drag', () {
    test('covers a bounded range in a few hundred pixels', () {
      // The same gesture has to mean a sensible amount whether the property
      // runs 0..1 or 0..64, which is the whole reason this is not a constant.
      expect(scrubPerPixel(propFor('opacity')), closeTo(1 / 300, 1e-9));
      expect(scrubPerPixel(propFor('padding')), closeTo(64 / 300, 1e-9));
    });

    test('falls back to a unit a pixel when nothing is bounded', () {
      expect(scrubPerPixel(null), 1);
      expect(scrubPerPixel(propFor('nonsense')), 1);
    });

    test('moves an angle in degrees, not radians', () {
      // A pixel worth of radians would be a third of a turn.
      expect(scrubPerPixel(propFor('rotate')), 0.5);
    });
  });

  group('degrees in, radians out', () {
    var rotate = propFor('rotate');

    test('the file keeps radians and the field shows degrees', () {
      expect(toDisplay(rotate, math.pi), closeTo(180, 1e-9));
      expect(fromDisplay(rotate, 180), closeTo(math.pi, 1e-9));
    });

    test('round-trips, so typing back what is shown changes nothing', () {
      expect(
        fromDisplay(rotate, toDisplay(rotate, -0.055)),
        closeTo(-0.055, 1e-9),
      );
    });

    test('leaves everything else alone', () {
      var opacity = propFor('opacity');
      expect(toDisplay(opacity, 0.4), 0.4);
      expect(fromDisplay(opacity, 0.4), 0.4);
    });

    test('the dial spans a whole turn either way', () {
      var (min, max) = displayRange(rotate);
      expect(min, closeTo(-360, 0.1));
      expect(max, closeTo(360, 0.1));
    });
  });

  group('printing', () {
    test('degrees to a tenth, everything else to a hundredth', () {
      expect(formatDisplay(propFor('rotate'), math.pi / 4), '45.0');
      expect(formatDisplay(propFor('opacity'), 0.5), '0.50');
    });

    test('the unit is shown, never parsed back', () {
      expect(unitOf(propFor('rotate')), '°');
      expect(unitOf(propFor('translateY')), 'px');
      expect(unitOf(propFor('opacity')), '');
      expect(unitOf(null), '');
    });
  });
}
