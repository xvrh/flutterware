import 'dart:io';

import 'package:flutterware_app/src/motion/values_file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _wrap(String body) =>
    '''
import 'dart:ui' show Color;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

const demoMotion = $body;
''';

MotionFileResult _read(String body) => readMotionValues(_wrap(body));

void main() {
  group('reading', () {
    test('a target, a property and a span', () {
      var result = _read('''MotionValues(
  duration: Duration(milliseconds: 400),
  targets: {
    'title': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 300),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
    },
  },
)''');

      expect(result.writable, isTrue);
      var file = result.file!;
      expect(file.constName, 'demoMotion');
      expect(file.durationMs, 400);
      var span = file.target('title')!.property('opacity')!.spans.single;
      expect(span.startMs, 0);
      expect(span.endMs, 300);
      expect(span.from, const MotionNumber(0));
      expect(span.to, const MotionNumber(1));
      expect(span.curve, 'easeOut');
    });

    test('a colour span, and a negative number', () {
      var result = _read('''MotionValues(
  targets: {
    'a': {
      'color': [
        Seg<Color>(
          start: Duration.zero,
          end: Duration(milliseconds: 10),
          from: Color(0xFF102030),
          to: Color(0x00A0B0C0),
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 10),
          from: -12.5,
          to: 0,
        ),
      ],
    },
  },
)''');
      expect(result.writable, isTrue);
      var target = result.file!.target('a')!;
      expect(
        target.property('color')!.spans.single.from,
        const MotionColor(0xFF102030),
      );
      expect(
        target.property('color')!.spans.single.to,
        const MotionColor(0x00A0B0C0),
      );
      expect(
        target.property('translateY')!.spans.single.from,
        const MotionNumber(-12.5),
      );
    });

    test('comments above an entry are kept', () {
      var result = _read('''MotionValues(
  targets: {
    // Why the title moves at all.
    // Two lines of it.
    'title': {
      // And why this property.
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 10),
          from: 0,
          to: 1,
        ),
      ],
    },
  },
)''');
      var target = result.file!.target('title')!;
      expect(target.comments, [
        '// Why the title moves at all.',
        '// Two lines of it.',
      ]);
      expect(target.property('opacity')!.comments, [
        '// And why this property.',
      ]);
    });

    test('a comment separated by a blank line belongs to the gap', () {
      var result = _read('''MotionValues(
  targets: {
    // A section heading, not a note about `title`.

    'title': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 10),
          from: 0,
          to: 1,
        ),
      ],
    },
  },
)''');
      var target = result.file!.target('title')!;
      expect(target.comments, isEmpty);
      // …and the gap it belongs to is kept, so a rewrite does not close it up.
      expect(target.blankBefore, isTrue);
    });
  });

  group('refusing to write', () {
    // The safety property: a file this cannot fully understand is a file it
    // will not rewrite. Every one of these is somebody's deliberate work, and
    // re-emitting only the parts we understood would delete it.
    void refuses(String body, String because) {
      var result = _read(body);
      expect(result.writable, isFalse, reason: because);
      expect(result.problems, isNotEmpty);
    }

    test('a curve that is not a Curves member', () {
      refuses('''MotionValues(
  targets: {
    'a': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 10),
          from: 0,
          to: 1,
          curve: Cubic(0.1, 0.2, 0.3, 0.4),
        ),
      ],
    },
  },
)''', 'a hand-rolled curve would be re-emitted as the default');
    });

    test('a value that is not a literal', () {
      refuses('''MotionValues(
  targets: {
    'a': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 10),
          from: kHidden,
          to: 1,
        ),
      ],
    },
  },
)''', 'a shared constant would become a number');
    });

    test('a duration in units a motion is not written in', () {
      refuses('''MotionValues(
  targets: {
    'a': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(microseconds: 10500),
          from: 0,
          to: 1,
        ),
      ],
    },
  },
)''', 'microseconds would be silently rounded to milliseconds');
    });

    test('a target key built from something', () {
      refuses(r'''MotionValues(
  targets: {
    'row$i': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 10),
          from: 0,
          to: 1,
        ),
      ],
    },
  },
)''', 'an interpolated key names a target we cannot reproduce');
    });

    test('a spread into the map', () {
      refuses('''MotionValues(
  targets: {
    ...sharedTargets,
    'a': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 10),
          from: 0,
          to: 1,
        ),
      ],
    },
  },
)''', 'the spread would vanish');
    });

    test('no MotionValues at all', () {
      var result = readMotionValues('const x = 1;');
      expect(result.writable, isFalse);
      expect(result.problems.single.message, contains('no `MotionValues'));
    });

    test('two motions in one file, unless one is named', () {
      var source = '''
const a = MotionValues(targets: {});
const b = MotionValues(targets: {});
''';
      expect(readMotionValues(source).writable, isFalse);
      expect(readMotionValues(source, constName: 'b').writable, isTrue);
      expect(readMotionValues(source, constName: 'c').writable, isFalse);
    });
  });

  group('rewriting', () {
    test('touches only the expression', () {
      var result = _read('''MotionValues(
  targets: {
    'a': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 10),
          from: 0,
          to: 1,
        ),
      ],
    },
  },
)''');
      var file = result.file!;
      var rewritten = file.rewrite(file.targets);
      // The imports and the const declaration survive verbatim, because the
      // editor replaces one expression rather than producing a file.
      expect(rewritten, startsWith("import 'dart:ui' show Color;"));
      expect(rewritten, contains('const demoMotion = MotionValues('));
      expect(rewritten, endsWith(';\n'));
      expect(rewritten, file.source);
    });

    test('an edit changes one number and nothing else', () {
      var result = _read('''MotionValues(
  targets: {
    'a': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 300),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
    },
  },
)''');
      var file = result.file!;
      var target = file.targets.single;
      var property = target.properties.single;
      var edited = [
        MotionTargetValues(
          name: target.name,
          comments: target.comments,
          properties: [
            MotionPropertyValues(
              name: property.name,
              comments: property.comments,
              spans: [property.spans.single.copyWith(endMs: 420)],
            ),
          ],
        ),
      ];

      var before = file.source.split('\n');
      var after = file.rewrite(edited).split('\n');
      var changed = [
        for (var i = 0; i < before.length; i++)
          if (before[i] != after[i]) i,
      ];
      expect(changed, hasLength(1));
      expect(after[changed.single].trim(), 'end: Duration(milliseconds: 420),');
    });
  });

  group('where the numbers live', () {
    test('beside the screen, whatever the screen is called', () {
      expect(motionValuesPath('lib/home.dart'), 'lib/home.motion.dart');
      expect(
        motionValuesPath('lib/screens/on.boarding.dart'),
        'lib/screens/on.boarding.motion.dart',
      );
      expect(motionValuesPath('home.dart'), 'home.motion.dart');
      // A directory with a dot in it must not be mistaken for an extension.
      expect(motionValuesPath('lib/v1.2/home'), 'lib/v1.2/home.motion.dart');
    });
  });

  group('against the repo own values files', () {
    // The emitter matches `dart_style` by construction rather than by running
    // it — CI checks `tool/prepare_submit.dart`, and an emitter that formatted
    // independently would disagree with CI on somebody else's machine. These
    // files were formatted by the sanctioned formatter, so a byte-identical
    // round trip is the proof.
    test('round-trip byte for byte, comments included', () {
      var demos = _findDemos();
      if (demos == null) return;
      var files = Directory(demos)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.motion.dart'))
          .toList();
      expect(files, isNotEmpty, reason: 'no values files to check against');

      for (var file in files) {
        var source = file.readAsStringSync();
        var result = readMotionValues(source);
        expect(
          result.problems,
          isEmpty,
          reason: '${p.basename(file.path)}: ${result.problems}',
        );
        expect(
          result.file!.rewrite(result.file!.targets),
          source,
          reason: '${p.basename(file.path)} does not survive a round trip',
        );
      }
    });
  });
}

String? _findDemos() {
  const relative = 'tool/catalog/demos';
  for (var dir = Directory.current; ; dir = dir.parent) {
    for (var root in [dir.path, p.join(dir.path, 'app')]) {
      if (Directory(p.join(root, relative)).existsSync()) {
        return p.join(root, relative);
      }
    }
    if (dir.parent.path == dir.path) return null;
  }
}
