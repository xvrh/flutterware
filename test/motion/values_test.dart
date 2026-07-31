import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/src/motion/values.dart';

Duration ms(int value) => Duration(milliseconds: value);

/// A single 100→400ms span, 0 → 1, linear.
final _fade = <Seg<Object?>>[
  Seg<double>(start: ms(100), end: ms(400), from: 0, to: 1),
];

void main() {
  group('hold', () {
    test('before the first segment a property is its from', () {
      expect(evaluateSegments(_fade, ms(0)), 0.0);
      expect(evaluateSegments(_fade, ms(99)), 0.0);
    });

    test('after the last segment a property is its to', () {
      expect(evaluateSegments(_fade, ms(400)), 1.0);
      expect(evaluateSegments(_fade, ms(10000)), 1.0);
    });

    test("a gap holds the earlier segment's to", () {
      var segments = <Seg<Object?>>[
        Seg<double>(start: ms(0), end: ms(100), from: 0, to: 0.5),
        Seg<double>(start: ms(300), end: ms(400), from: 0.5, to: 1),
      ];
      expect(evaluateSegments(segments, ms(200)), 0.5);
    });

    test('no segments is null, not a default', () {
      // The fallback belongs to the getter, not to evaluation — otherwise
      // "untuned" and "tuned to the resting value" become the same thing and
      // the panel cannot tell them apart.
      expect(evaluateSegments(const [], ms(0)), isNull);
    });
  });

  group('interpolation', () {
    test('linear, halfway', () {
      expect(evaluateSegments(_fade, ms(250)), closeTo(0.5, 1e-9));
    });

    test('the curve is applied, not ignored', () {
      var eased = <Seg<Object?>>[
        Seg<double>(
          start: ms(0),
          end: ms(100),
          from: 0,
          to: 1,
          curve: Curves.easeInCubic,
        ),
      ];
      var value = evaluateSegments(eased, ms(50))! as double;
      expect(value, lessThan(0.25));
      expect(value, greaterThan(0));
    });

    test('colours interpolate', () {
      var segments = <Seg<Object?>>[
        Seg<Color>(
          start: ms(0),
          end: ms(100),
          from: Color(0xFF000000),
          to: Color(0xFFFFFFFF),
        ),
      ];
      var value = evaluateSegments(segments, ms(50))! as Color;
      expect(value.r, closeTo(0.5, 0.02));
      expect(value.a, 1.0);
    });

    test('a zero-length span lands on its end', () {
      var segments = <Seg<Object?>>[
        Seg<double>(start: ms(100), end: ms(100), from: 0, to: 1),
      ];
      expect(evaluateSegments(segments, ms(100)), 1.0);
    });

    test('anything but a double or a Color is refused, by name', () {
      expect(
        () => lerpMotionValue(Offset.zero, Offset.zero, 0.5),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('composed at the read site'),
          ),
        ),
      );
    });
  });

  group('duration', () {
    test('is the end of the last segment when not declared', () {
      var values = MotionValues(
        anchors: {
          'a': {
            'opacity': _fade,
            'translateY': [
              Seg<double>(start: ms(0), end: ms(650), from: 24, to: 0),
            ],
          },
        },
      );
      expect(values.resolveDuration(), ms(650));
    });

    test('a declared duration wins, even a shorter one', () {
      var values = MotionValues(
        duration: ms(200),
        anchors: {
          'a': {'opacity': _fade},
        },
      );
      expect(values.resolveDuration(), ms(200));
    });

    test('empty is zero, not an error', () {
      expect(MotionValues.empty.resolveDuration(), Duration.zero);
    });
  });

  group('overlap', () {
    test('is reported rather than silently resolved', () {
      var segments = <Seg<Object?>>[
        Seg<double>(start: ms(0), end: ms(200), from: 0, to: 1),
        Seg<double>(start: ms(100), end: ms(300), from: 1, to: 0),
      ];
      var clash = findOverlap(segments);
      expect(clash, isNotNull);
      expect(clash!.$1.start, ms(0));
      expect(clash.$2.start, ms(100));
    });

    test('touching spans do not overlap', () {
      var segments = <Seg<Object?>>[
        Seg<double>(start: ms(0), end: ms(100), from: 0, to: 1),
        Seg<double>(start: ms(100), end: ms(200), from: 1, to: 0),
      ];
      expect(findOverlap(segments), isNull);
    });

    test('unsorted input is still caught', () {
      var segments = <Seg<Object?>>[
        Seg<double>(start: ms(100), end: ms(300), from: 1, to: 0),
        Seg<double>(start: ms(0), end: ms(200), from: 0, to: 1),
      ];
      expect(findOverlap(segments), isNotNull);
    });
  });

  group('the vocabulary', () {
    test('every property has a name nothing else uses', () {
      expect(
        motionVocabularyByName.length,
        motionVocabulary.length,
        reason: 'two properties share a name',
      );
    });

    test('MotionBox only claims properties the vocabulary declares', () {
      for (var name in motionBoxProps) {
        expect(
          motionVocabularyByName.containsKey(name),
          isTrue,
          reason: 'MotionBox applies "$name", which is not in the vocabulary',
        );
      }
    });

    test('MotionBox applies only properties with a resting value', () {
      // A nullable property has no identity to skip against, so MotionBox
      // could not decide whether to add its layer.
      for (var name in motionBoxProps) {
        expect(
          motionVocabularyByName[name]!.isNullable,
          isFalse,
          reason: '"$name" is nullable and cannot have a frozen resting value',
        );
      }
    });

    test('colour is the only non-number', () {
      var colours = motionVocabulary.where(
        (p) => p.kind == MotionValueKind.color,
      );
      expect(colours.map((p) => p.name), ['color']);
    });
  });
}
