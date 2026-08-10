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

  group('a second span, inserted at the playhead', () {
    /// Opacity's debut is 0 -> 1, so the far end from a resting 1 is 0.
    test('opens at what the property is already worth', () {
      var span = spanAt(
        property: 'opacity',
        atMs: 200,
        durationMs: 600,
        existing: const [(0, 200)],
        current: const MotionNumber(0.9),
      )!;
      // Nothing on screen jumps when the span appears, which is the whole
      // reason to insert here rather than at the end.
      expect((span.from as MotionNumber).value, 0.9);
      expect(span.startMs, 200);
    });

    test('runs to the next span rather than over it', () {
      var span = spanAt(
        property: 'opacity',
        atMs: 200,
        durationMs: 600,
        existing: const [(0, 150), (400, 600)],
      )!;
      expect(span.endMs, 400);
    });

    test('runs to the end of the motion when nothing follows', () {
      var span = spanAt(
        property: 'opacity',
        atMs: 200,
        durationMs: 600,
        existing: const [(0, 150)],
      )!;
      expect(span.endMs, 600);
    });

    test('goes to whichever end is further, so it always shows', () {
      // The commonest case: the first span already landed on rest, so a second
      // one closing on rest again would be a span that does nothing.
      var atRest = spanAt(
        property: 'opacity',
        atMs: 300,
        durationMs: 600,
        existing: const [(0, 300)],
        current: const MotionNumber(1),
      )!;
      expect((atRest.to as MotionNumber).value, 0);

      var away = spanAt(
        property: 'opacity',
        atMs: 300,
        durationMs: 600,
        existing: const [(0, 300)],
        current: const MotionNumber(0),
      )!;
      expect((away.to as MotionNumber).value, 1);
    });

    test('refuses when there is no room left', () {
      expect(
        spanAt(
          property: 'opacity',
          atMs: 600,
          durationMs: 600,
          existing: const [],
        ),
        isNull,
      );
      // The gap closed: the next span starts exactly here.
      expect(
        spanAt(
          property: 'opacity',
          atMs: 300,
          durationMs: 600,
          existing: const [(300, 600)],
        ),
        isNull,
      );
    });

    test('is nothing at all for a name the vocabulary does not carry', () {
      expect(
        spanAt(
          property: 'nonsense',
          atMs: 100,
          durationMs: 600,
          existing: const [],
        ),
        isNull,
      );
    });
  });

  group('putting a span into the file', () {
    var file = [
      MotionTargetValues(
        name: 'title',
        properties: [
          MotionPropertyValues(
            name: 'opacity',
            spans: [
              MotionSpan(
                startMs: 400,
                endMs: 600,
                from: const MotionNumber(0),
                to: const MotionNumber(1),
              ),
            ],
          ),
        ],
      ),
    ];

    test('inserts in start order, because the ends read first and last', () {
      // `evaluateSegments` answers "before the start" from `first` and "after
      // the end" from `last`, so an appended-out-of-order span would give the
      // property the wrong value at both ends of the motion.
      var next = withSpanAdded(
        file,
        'title',
        'opacity',
        MotionSpan(
          startMs: 0,
          endMs: 200,
          from: const MotionNumber(1),
          to: const MotionNumber(0),
        ),
      );
      var spans = next.single.properties.single.spans;
      expect(spans.map((s) => s.startMs), [0, 400]);
    });

    test('leaves other targets and properties alone', () {
      var next = withSpanAdded(
        [
          ...file,
          MotionTargetValues(
            name: 'cta',
            properties: [
              MotionPropertyValues(
                name: 'scale',
                spans: [
                  MotionSpan(
                    startMs: 0,
                    endMs: 100,
                    from: const MotionNumber(0),
                    to: const MotionNumber(1),
                  ),
                ],
              ),
            ],
          ),
        ],
        'title',
        'opacity',
        MotionSpan(
          startMs: 0,
          endMs: 200,
          from: const MotionNumber(1),
          to: const MotionNumber(0),
        ),
      );
      expect(next.last.name, 'cta');
      expect(next.last.properties.single.spans, hasLength(1));
    });
  });

  group('taking a span out again', () {
    MotionSpan span(int startMs, int endMs) => MotionSpan(
      startMs: startMs,
      endMs: endMs,
      from: const MotionNumber(0),
      to: const MotionNumber(1),
    );

    test('removes just the one', () {
      var next = withSpanRemoved(
        [
          MotionTargetValues(
            name: 'title',
            properties: [
              MotionPropertyValues(
                name: 'opacity',
                spans: [span(0, 100), span(200, 300)],
              ),
            ],
          ),
        ],
        'title',
        'opacity',
        0,
      );
      expect(next.single.properties.single.spans.single.startMs, 200);
    });

    test('takes the property with it when that was the last span', () {
      // A property with no spans is not a thing the file can spell, and an
      // empty lane would read as tuned-and-broken rather than as untuned.
      var next = withSpanRemoved(
        [
          MotionTargetValues(
            name: 'title',
            properties: [
              MotionPropertyValues(name: 'opacity', spans: [span(0, 100)]),
              MotionPropertyValues(name: 'scale', spans: [span(0, 100)]),
            ],
          ),
        ],
        'title',
        'opacity',
        0,
      );
      expect(next.single.properties.map((p) => p.name), ['scale']);
    });

    test('takes the target too when that was its last property', () {
      var next = withSpanRemoved(
        [
          MotionTargetValues(
            name: 'title',
            properties: [
              MotionPropertyValues(name: 'opacity', spans: [span(0, 100)]),
            ],
          ),
        ],
        'title',
        'opacity',
        0,
      );
      expect(next, isEmpty);
    });
  });

  group('where `+` actually lands', () {
    test('the playhead, when the playhead will do', () {
      var span = spanFor(
        property: 'opacity',
        atMs: 300,
        durationMs: 600,
        existing: const [(0, 200)],
        current: const MotionNumber(0.5),
      )!;
      expect(span.startMs, 300);
      expect((span.from as MotionNumber).value, 0.5);
    });

    test('a gap, when the motion has just finished playing', () {
      // The case that made `+` useless in the panel: play to the end and the
      // playhead sits at the duration, where by definition nothing fits.
      var span = spanFor(
        property: 'opacity',
        atMs: 600,
        durationMs: 600,
        existing: const [(0, 200)],
        current: const MotionNumber(1),
      )!;
      expect(span.startMs, 200);
      expect(span.endMs, 600);
      // No continuity claimed away from the playhead: the value at 200ms is
      // not the one the guest reported at 600ms.
      expect((span.from as MotionNumber).value, 0);
    });

    test('a gap, when the playhead is inside a span', () {
      var span = spanFor(
        property: 'opacity',
        atMs: 100,
        durationMs: 600,
        existing: const [(0, 200)],
      )!;
      expect(span.startMs, 200);
    });

    test('the widest gap, not the first', () {
      var span = spanFor(
        property: 'opacity',
        atMs: 50,
        durationMs: 1000,
        existing: const [(0, 100), (200, 300), (900, 1000)],
      )!;
      expect(span.startMs, 300);
      expect(span.endMs, 900);
    });

    test('nothing at all when the lane is covered end to end', () {
      expect(
        spanFor(
          property: 'opacity',
          atMs: 300,
          durationMs: 600,
          existing: const [(0, 300), (300, 600)],
        ),
        isNull,
      );
    });
  });

  group('the widest gap', () {
    test('finds the room before, between and after', () {
      expect(widestGap(const [(200, 300)], 600), 300);
      expect(widestGap(const [(0, 100), (150, 600)], 600), 100);
      expect(widestGap(const [], 600), 0);
    });

    test('is null when there is none', () {
      expect(widestGap(const [(0, 600)], 600), isNull);
    });

    test('sorts first, so a hand-edited file cannot fake a gap', () {
      // Out of order, and overlapping once sorted: 0..400 and 100..600 cover
      // the whole motion between them.
      expect(widestGap(const [(100, 600), (0, 400)], 600), isNull);
    });
  });
}
