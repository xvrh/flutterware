import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/knob.dart';
import 'package:flutterware_app/src/catalog/headless_catalog.dart';
import 'package:flutterware_app/src/plugins/native/ui_catalog_core.dart';

/// How a knob value gets from a command line or an agent to a demo.
///
/// Both halves are pure and both are where the mistakes are: one decides how
/// the value is *spelled*, the other what *kind* it becomes. The pipeline they
/// feed needs an SDK, a compile and a guest; these do not.
void main() {
  group('parseKnobs', () {
    test('reads name=value pairs, which is what a shell can pass', () {
      expect(UiCatalogCore.parseKnobs('label=Hi,count=7,dense=true'), {
        'label': 'Hi',
        'count': '7',
        'dense': 'true',
      });
    });

    test('keeps everything after the first = ', () {
      // A value may contain one; the name may not.
      expect(UiCatalogCore.parseKnobs('title=a=b'), {'title': 'a=b'});
    });

    test('trims the name but never the value', () {
      // Leading space in a string knob is a legitimate thing to want to see.
      expect(UiCatalogCore.parseKnobs('label = x '), {'label': ' x '});
    });

    test('reads a JSON object, which is what an agent writes', () {
      expect(UiCatalogCore.parseKnobs('{"count": 7, "dense": true}'), {
        'count': '7',
        'dense': 'true',
      });
    });

    test('takes a map straight through, which is how MCP sends one', () {
      expect(UiCatalogCore.parseKnobs({'count': 7, 'dense': true}), {
        'count': '7',
        'dense': 'true',
      });
    });

    test('nothing asked for is no knobs, not an error', () {
      expect(UiCatalogCore.parseKnobs(null), isEmpty);
    });

    test('refuses a pair with no value rather than guessing one', () {
      expect(() => UiCatalogCore.parseKnobs('dense'), throwsArgumentError);
      expect(() => UiCatalogCore.parseKnobs('=x'), throwsArgumentError);
      expect(() => UiCatalogCore.parseKnobs(''), throwsArgumentError);
      expect(() => UiCatalogCore.parseKnobs('{"a": 1'), throwsFormatException);
    });
  });

  group('coerceKnob', () {
    KnobDescriptor knob(KnobKind kind, {List<String> options = const []}) =>
        KnobDescriptor(
          name: 'k',
          kind: kind,
          value: null,
          defaultValue: null,
          options: options,
        );

    test('follows the kind the demo declared, not the characters', () {
      // The same text, three demos, three types.
      expect(coerceKnob(knob(KnobKind.string), '7'), '7');
      expect(coerceKnob(knob(KnobKind.integer), '7'), 7);
      expect(coerceKnob(knob(KnobKind.number), '7'), 7);
    });

    test('reads the booleans a person actually types', () {
      for (var yes in ['true', 'TRUE', 'yes', '1']) {
        expect(coerceKnob(knob(KnobKind.boolean), yes), isTrue);
      }
      for (var no in ['false', 'False', 'no', '0']) {
        expect(coerceKnob(knob(KnobKind.boolean), no), isFalse);
      }
    });

    test('a number keeps its fraction', () {
      expect(coerceKnob(knob(KnobKind.number), '1.5'), 1.5);
    });

    test('a picker only accepts a label it declared', () {
      var picker = knob(KnobKind.picker, options: ['small', 'large']);
      expect(coerceKnob(picker, 'small'), 'small');
      expect(
        () => coerceKnob(picker, 'huge'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('small, large'),
          ),
        ),
      );
    });

    test(
      'refuses a value of the wrong shape rather than silently defaulting',
      () {
        // The failure that matters: a knob quietly ignored renders a picture
        // that looks right and is not.
        expect(
          () => coerceKnob(knob(KnobKind.integer), 'seven'),
          throwsArgumentError,
        );
        expect(
          () => coerceKnob(knob(KnobKind.number), 'lots'),
          throwsArgumentError,
        );
        expect(
          () => coerceKnob(knob(KnobKind.boolean), 'maybe'),
          throwsArgumentError,
        );
      },
    );
  });
}
