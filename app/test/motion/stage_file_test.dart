import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/motion/stage_file.dart';

const _sample = '''
import 'package:flutter/material.dart' show Color;
import 'package:flutterware/motion.dart';

const signInStage = MotionStage(
  width: 340,
  height: 380,
  elements: [
    StageElement(
      target: 'title',
      kind: StageKind.text,
      label: 'Welcome back',
      x: 28,
      y: 44,
      width: 220,
      height: 26,
    ),
    StageElement(
      target: 'cta',
      x: 28,
      y: 240,
      width: 284,
      height: 46,
      tint: Color(0xFF2563EB),
    ),
  ],
);
''';

void main() {
  test('reads a stage', () {
    var parsed = parseStageFile(_sample);
    expect(parsed, isA<StageFile>());
    var stage = parsed as StageFile;
    expect(stage.name, 'signInStage');
    expect(stage.width, 340);
    expect(stage.elements, hasLength(2));
    expect(stage.elements.first.kind, 'text');
    expect(stage.elements.first.label, 'Welcome back');
    expect(stage.elements.last.tint, 'Color(0xFF2563EB)');
  });

  // The invariant the whole format rests on. Emit is idempotent, so a file the
  // tool has written once is byte-identical the next time it writes it — which
  // is what keeps `add-element` from producing a diff on lines it did not
  // touch.
  test('emit(parse(emit(x))) == emit(x)', () {
    var once = emitStageFile(parseStageFile(_sample) as StageFile);
    var twice = emitStageFile(parseStageFile(once) as StageFile);
    expect(twice, once);
  });

  test('adding an element leaves the others alone', () {
    var stage = parseStageFile(_sample) as StageFile;
    var grown = stage.withElement(
      const StageElementModel(
        target: 'email',
        x: 28,
        y: 108,
        width: 284,
        height: 48,
      ),
    );
    var emitted = emitStageFile(grown);
    var reparsed = parseStageFile(emitted) as StageFile;
    expect(reparsed.elements.map((e) => e.target), ['title', 'cta', 'email']);
    expect(emitted, startsWith(emitStageFile(stage).split('  ],').first));
  });

  test('imports Color only when a colour is written', () {
    var plain = emitStageFile(
      const StageFile(
        name: 'aStage',
        width: 100,
        height: 100,
        background: null,
        elements: [
          StageElementModel(target: 'a', x: 0, y: 0, width: 10, height: 10),
        ],
      ),
    );
    expect(plain, isNot(contains('material.dart')));
    expect(
      emitStageFile(parseStageFile(_sample) as StageFile),
      contains('material.dart'),
    );
  });

  group('refuses rather than approximates', () {
    test('a computed position', () {
      var result = parseStageFile(
        _sample.replaceFirst(
          'x: 28,\n      y: 240,',
          'x: 28 + 4,\n      y: 240,',
        ),
      );
      expect(result, isA<StageParseFailure>());
    });

    test('a spread in the element list', () {
      var result = parseStageFile(
        _sample.replaceFirst('  elements: [', '  elements: [...more,'),
      );
      expect(result, isA<StageParseFailure>());
      expect((result as StageParseFailure).message, contains('StageElement'));
    });

    test('a file with no stage in it', () {
      expect(parseStageFile('const x = 1;'), isA<StageParseFailure>());
    });
  });

  test('wraps where the formatter wraps', () {
    var short = emitStageFile(
      const StageFile(
        name: 'aStage',
        width: 360,
        height: 560,
        background: null,
        elements: [
          StageElementModel(
            target: 'cta',
            x: 24,
            y: 80,
            width: 312,
            height: 48,
          ),
        ],
      ),
    );
    // One line, because that is what `dart format` would leave — an emitter
    // that split it would churn the file on the next commit.
    expect(
      short,
      contains(
        "    StageElement(target: 'cta', x: 24, y: 80, width: 312, height: 48),",
      ),
    );

    var long = emitStageFile(
      const StageFile(
        name: 'aStage',
        width: 360,
        height: 560,
        background: null,
        elements: [
          StageElementModel(
            target: 'aRatherLongTargetName',
            kind: 'text',
            label: 'Total  £248.00',
            x: 24,
            y: 80,
            width: 312,
            height: 48,
          ),
        ],
      ),
    );
    expect(long, contains('    StageElement(\n'));
    expect(long, contains("      target: 'aRatherLongTargetName',\n"));
    for (var line in long.split('\n')) {
      expect(line.length, lessThanOrEqualTo(80), reason: line);
    }
  });
}
