// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/knob.dart';
import 'package:flutterware_app/src/catalog/catalog_params.dart';
import 'package:test/test.dart';

const _theme = KnobDescriptor(
  name: 'Theme',
  kind: KnobKind.picker,
  value: 'Light',
  defaultValue: 'Light',
  options: ['Light', 'Dark mode'],
);

const _compact = KnobDescriptor(
  name: 'Compact',
  kind: KnobKind.boolean,
  value: false,
  defaultValue: false,
);

/// An axis is the project's own vocabulary — the shell names it and the shell
/// decides what it means — so nothing here validates against a fixed list or
/// appears in the docs. All that is left is the translation between display
/// strings and something an address can carry.
void main() {
  group('slugs', () {
    test('a label becomes something you could type', () {
      expect(paramSlug('Dark mode'), 'dark-mode');
      expect(paramSlug('Theme'), 'theme');
      expect(paramSlug('Français'), 'fran-ais');
      expect(paramSlug('  A/B  '), 'a-b');
    });

    test('and a label with nothing sluggable keeps something', () {
      // Better a key that reads oddly than one that is empty and collides with
      // every other unsluggable label.
      expect(paramSlug('日本語'), isNotEmpty);
    });

    test('an axis is keyed by its name', () {
      expect(paramKeyFor(_theme), 'theme');
    });
  });

  group('what an address says', () {
    test('names only what somebody chose', () {
      // The default is written as nothing at all, so an address carries the
      // difference between "I picked Light" and "nobody touched it" — and a
      // shell that changes its own default does not silently reinterpret an
      // old link.
      expect(paramValueSlug(_theme, 'Light'), isNull);
      expect(paramValueSlug(_theme, null), isNull);
      expect(paramValueSlug(_theme, 'Dark mode'), 'dark-mode');
    });

    test('and a flag reads as a flag', () {
      expect(paramValueSlug(_compact, true), 'true');
      expect(paramValueSlug(_compact, false), isNull, reason: 'the default');
    });

    test('a slug resolves back to the label the guest declared', () {
      expect(paramOptionFor(_theme, 'dark-mode'), 'Dark mode');
      expect(paramOptionFor(_compact, 'true'), true);
      expect(paramOptionFor(_compact, 'false'), false);
    });

    test('and one that matches nothing is not an error', () {
      // A parameter for an axis this shell does not declare — a shell that has
      // not built yet, or one whose options changed under an edit. It stays in
      // the address and is ignored, the same as any other value that is the
      // project's to define.
      expect(paramOptionFor(_theme, 'sepia'), isNull);
      expect(paramOptionFor(_compact, 'maybe'), isNull);
    });
  });

  group('what is drawn', () {
    test('follows the address before the guest has answered', () {
      // The whole of the optimistic update, and it mutates nothing: the report
      // stays exactly what the guest said, and the control still moves under
      // the pointer.
      expect(
        paramDisplayValue(_theme, const {'theme': 'dark-mode'}),
        'Dark mode',
      );
      expect(paramDisplayValue(_compact, const {'compact': 'true'}), true);
    });

    test('silence means the default, not what the guest last confirmed', () {
      // The bug this pins: silence is *how* a default is written, so falling
      // back to the confirmed value meant choosing the default put the control
      // straight back where it had been. Picking Light after Dark did nothing
      // and the top bar looked frozen.
      const confirmedDark = KnobDescriptor(
        name: 'Theme',
        kind: KnobKind.picker,
        value: 'Dark mode',
        defaultValue: 'Light',
        options: ['Light', 'Dark mode'],
      );

      expect(paramDisplayValue(confirmedDark, const {}), 'Light');
    });

    test('and so does a value that resolves to nothing', () {
      expect(paramDisplayValue(_theme, const {'theme': 'sepia'}), 'Light');
    });

    test('a flag returns to its default the same way', () {
      const confirmedOn = KnobDescriptor(
        name: 'Compact',
        kind: KnobKind.boolean,
        value: true,
        defaultValue: false,
      );

      expect(paramDisplayValue(confirmedOn, const {}), false);
    });
  });

  group('what the guest is sent', () {
    test('the declared names, with the declared labels', () {
      // Slugs are ours; the guest only ever knew its own strings.
      expect(
        paramPayloadFor(
          const [_theme, _compact],
          const {'theme': 'dark-mode', 'compact': 'true'},
        ),
        {'Theme': 'Dark mode', 'Compact': true},
      );
    });

    test('and null for one nobody chose, which means its own default', () {
      // Present rather than left out. Leaving it out is what made the top bar
      // look stuck: the address writes a default as nothing at all, so a
      // payload of only-what-changed could never say "forget this one".
      expect(paramPayloadFor(const [_theme], const {}), {'Theme': null});
    });

    test('and nothing at all about what this build does not declare', () {
      expect(
        paramPayloadFor(const [_theme], const {'flavor': 'pro'}),
        {'Theme': null},
        reason: 'the stale one stays in the address, unmentioned here',
      );
    });
  });

  group('every kind a knob can be', () {
    const count = KnobDescriptor(
      name: 'Count',
      kind: KnobKind.integer,
      value: 3,
      defaultValue: 1,
      min: 0,
      max: 10,
    );
    const ratio = KnobDescriptor(
      name: 'Ratio',
      kind: KnobKind.number,
      value: 0.5,
      defaultValue: 1,
    );
    const title = KnobDescriptor(
      name: 'Title',
      kind: KnobKind.string,
      value: 'Hi',
      defaultValue: '',
    );

    test('a number round-trips as a number', () {
      expect(paramValueSlug(count, 7), '7');
      expect(paramOptionFor(count, '7'), 7);
      expect(paramValueSlug(ratio, 0.25), '0.25');
      expect(paramOptionFor(ratio, '0.25'), 0.25);
    });

    test('an integer is written whole, however it arrived', () {
      // A slider hands back a double even on a divided track.
      expect(paramValueSlug(count, 7.0), '7');
    });

    test('a string is carried verbatim, never slugged', () {
      // Slugging would destroy the very thing being set. The address does its
      // own percent-encoding, so nothing here has to.
      expect(paramValueSlug(title, 'Hello World / 2'), 'Hello World / 2');
      expect(paramOptionFor(title, 'Hello World / 2'), 'Hello World / 2');
    });

    test('and the default is still written as silence', () {
      expect(paramValueSlug(count, 1), isNull);
      expect(paramValueSlug(title, ''), isNull);
      expect(paramDisplayValue(count, const {}), 1);
    });

    test('a value that will not parse falls back to the default', () {
      expect(paramOptionFor(count, 'lots'), isNull);
      expect(paramDisplayValue(count, const {'count': 'lots'}), 1);
    });

    test("the payload carries the demo's own types", () {
      expect(
        paramPayloadFor(
          const [count, ratio, title],
          const {'count': '7', 'title': 'Hi'},
        ),
        {'Count': 7, 'Ratio': null, 'Title': 'Hi'},
      );
    });
  });
}
