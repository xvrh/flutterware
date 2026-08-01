import 'package:flutterware/motion_vocabulary.dart';
import 'package:flutterware_app/src/motion/new_span.dart';
import 'package:flutterware_app/src/motion/values_file.dart';
import 'package:test/test.dart';

void main() {
  group('what `+` opens at', () {
    test('every property in the vocabulary has an answer', () {
      // The panel offers `+` on anything a MotionBox applies, so a property
      // with no debut is a button that does nothing.
      for (var prop in motionVocabulary) {
        expect(newSpanFor(prop.name), isNotNull, reason: prop.name);
      }
      expect(newSpanFor('nonsense'), isNull);
    });

    test('lands on the resting value, so t=1 looks correct straight away', () {
      for (var name in ['opacity', 'translateY', 'scale', 'rotate', 'blur']) {
        var span = newSpanFor(name)!;
        expect(
          (span.to as MotionNumber).value,
          motionVocabularyByName[name]!.identity,
          reason: name,
        );
        expect(span.from, isNot(span.to), reason: '$name would not move');
      }
    });

    test('a property whose rest is absence arrives instead of settling', () {
      // A shadow going from 8 to 0 is a thing that disappears.
      expect((newSpanFor('elevation')!.to as MotionNumber).value, 8);
      expect((newSpanFor('elevation')!.from as MotionNumber).value, 0);
    });

    test('a colour opens flat, because nothing knows what it is now', () {
      var span = newSpanFor('color')!;
      expect(span.isColor, isTrue);
      expect(span.from, span.to);
    });

    test('it runs the whole motion, or 400ms when there is none yet', () {
      expect(newSpanFor('opacity', durationMs: 900)!.endMs, 900);
      expect(newSpanFor('opacity')!.endMs, 400);
      expect(newSpanFor('opacity', durationMs: 0)!.endMs, 400);
    });

    test('it names a curve rather than falling back to linear', () {
      expect(newSpanFor('opacity')!.curve, isNotNull);
    });
  });

  group('adding it to a file', () {
    MotionTargetValues target(String name, List<String> properties) =>
        MotionTargetValues(
          name: name,
          properties: [
            for (var property in properties)
              MotionPropertyValues(
                name: property,
                spans: [
                  MotionSpan(
                    startMs: 0,
                    endMs: 10,
                    from: const MotionNumber(0),
                    to: const MotionNumber(1),
                  ),
                ],
              ),
          ],
        );

    test('appends to an existing target, keeping the file order', () {
      // A `+` that re-sorted the file to insert one line would make every edit
      // unreviewable.
      var next = withNewProperty(
        [
          target('a', ['opacity']),
          target('b', ['scale']),
        ],
        'a',
        'blur',
        newSpanFor('blur')!,
      );
      expect(next.map((t) => t.name), ['a', 'b']);
      expect(next.first.properties.map((p) => p.name), ['opacity', 'blur']);
    });

    test('creates the target when it is not there yet', () {
      var next = withNewProperty(
        [
          target('a', ['opacity']),
        ],
        'newcomer',
        'opacity',
        newSpanFor('opacity')!,
      );
      expect(next.map((t) => t.name), ['a', 'newcomer']);
      // Spaced off the one above it, as a hand-written file would be.
      expect(next.last.blankBefore, isTrue);
      expect(next.first.blankBefore, isFalse);
    });

    test('replaces rather than duplicates a property already there', () {
      var next = withNewProperty(
        [
          target('a', ['opacity']),
        ],
        'a',
        'opacity',
        newSpanFor('opacity', durationMs: 900)!,
      );
      expect(next.single.properties, hasLength(1));
      expect(next.single.properties.single.spans.single.endMs, 900);
    });

    test('survives a round trip through the emitter', () {
      var source = '''
const demoMotion = MotionValues(
  targets: {
    'title': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 400),
          from: 0,
          to: 1,
        ),
      ],
    },
  },
);
''';
      var file = readMotionValues(source).file!;
      var written = file.rewrite(
        withNewProperty(
          file.targets,
          'title',
          'translateY',
          newSpanFor('translateY', durationMs: 400)!,
        ),
      );
      expect(written, contains("'translateY': ["));
      expect(written, contains('from: 24,'));
      expect(written, contains('to: 0,'));
      expect(written, contains('curve: Curves.easeOutCubic,'));
      // And it is still readable, which is the only check that matters.
      var reread = readMotionValues(written);
      expect(reread.writable, isTrue);
      expect(reread.file!.target('title')!.properties, hasLength(2));
    });
  });
}
