import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/translations/survey.dart';

LoadedCatalog app({
  Map<String, String> en = const {'save': 'Save', 'greeting': 'Hello'},
  Map<String, String> nl = const {},
}) =>
    LoadedCatalog(name: 'app', template: 'en', byLocale: {'en': en, 'nl': nl});

KeySighting sighting({
  String key = 'save',
  String scenario = 'home_test/Home',
  String step = 'Home',
  int stepIndex = 1,
  String? locale,
  bool offstage = false,
  bool overflowed = false,
  bool stepFailed = false,
  int textsOnScreen = 10,
  int area = 5000,
}) => KeySighting(
  catalog: 'app',
  key: key,
  scenario: scenario,
  step: step,
  stepIndex: stepIndex,
  image: '$step.png',
  locale: locale,
  offstage: offstage,
  overflowed: overflowed,
  stepFailed: stepFailed,
  textsOnScreen: textsOnScreen,
  area: area,
);

TranslationSurvey survey({
  List<KeySighting> sightings = const [],
  Map<String, Map<String, Map<String, String>>> read = const {},
  LoadedCatalog? catalog,
  List<UnkeyedSighting> unkeyed = const [],
}) => TranslationSurvey(
  catalogs: {'app': catalog ?? app()},
  sightings: sightings,
  unkeyed: unkeyed,
  read: read,
);

void main() {
  group('the index', () {
    test('groups sightings by key, most-seen first', () {
      var it = survey(
        sightings: [
          sighting(key: 'save', step: 'a'),
          sighting(key: 'save', step: 'b'),
          sighting(key: 'greeting', step: 'c'),
        ],
      );

      expect(it.keysSeen, ['app/save', 'app/greeting']);
      expect(it.occurrencesOf('app', 'save'), hasLength(2));
      expect(it.occurrencesOf('app', 'nothing'), isEmpty);
    });
  });

  group('the catalog join', () {
    test('a key the run never asked for is not reached', () {
      var it = survey(
        read: {
          'en': {
            'app': {'save': 'Save'},
          },
        },
      );

      expect(it.keysNotReached(), [(catalog: 'app', key: 'greeting')]);
    });

    test('a key read but absent from the catalog is reported', () {
      var it = survey(
        read: {
          'en': {
            'app': {'save': 'Save', 'stale_key': 'Whatever'},
          },
        },
      );

      expect(it.keysAbsentFromCatalog(), [(catalog: 'app', key: 'stale_key')]);
    });

    test('a key read from an undeclared catalog is reported too', () {
      var it = survey(
        read: {
          'en': {
            'other': {'x': 'y'},
          },
        },
      );

      expect(it.keysAbsentFromCatalog(), [(catalog: 'other', key: 'x')]);
    });
  });

  group('what a locale actually rendered', () {
    test('the source language showing in a target locale is caught', () {
      // **No read set at all.** Falling back is a fact about the files, so an
      // export that ran one language still reports it in full — which is what
      // lets the default run be the source language alone.
      var it = survey();

      var findings = it.localeFindings();
      expect(findings.map((f) => f.key), ['greeting', 'save']);
      expect(
        findings.every((f) => f.verdict == LocaleVerdict.fallingBack),
        isTrue,
      );
      expect(findings.first.locale, 'nl');
      expect(
        findings.singleWhere((f) => f.key == 'save').rendered,
        'Save',
        reason: 'what a reader of nl actually sees',
      );
    });

    test('a translated key in its own locale is not a finding', () {
      var it = survey(catalog: app(nl: {'save': 'Opslaan'}));

      expect(it.localeFindings().map((f) => f.key), ['greeting']);
    });

    test('the files disagreeing with what ran is its own verdict', () {
      // This half *does* need the run: only the index knows what reached the
      // screen, and only the files know what should have.
      var it = survey(
        catalog: app(nl: {'save': 'Opslaan', 'greeting': 'Hallo'}),
        read: {
          'nl': {
            'app': {'save': 'Bewaren'},
          },
        },
      );

      expect(it.localeFindings().single.verdict, LocaleVerdict.disagrees);
      expect(it.localeFindings().single.expected, 'Opslaan');
    });

    test('the template locale is never a finding against itself', () {
      var it = survey(
        catalog: LoadedCatalog(
          name: 'app',
          template: 'en',
          byLocale: const {
            'en': {'save': 'Save'},
          },
        ),
        read: {
          'en': {
            'app': {'save': 'Save'},
          },
        },
      );

      expect(it.localeFindings(), isEmpty);
    });

    test('a key with no source text is not falling back to anything', () {
      // Nothing to fall back *to*: the key either does not draw, or it is a
      // stale entry that only a target locale still carries.
      var it = survey(
        catalog: app(en: {'save': ''}, nl: {}),
      );

      expect(it.localeFindings(), isEmpty);
    });

    test('a key no catalog defines is not called a fallback', () {
      var it = survey(
        catalog: app(en: {'save': 'Save'}, nl: {'save': 'Opslaan'}),
        read: {
          'nl': {
            'app': {'stale_key': 'Whatever'},
          },
        },
      );

      // It is unknown, not untranslated, and [keysAbsentFromCatalog] says so.
      expect(it.keysAbsentFromCatalog(), hasLength(1));
      expect(it.localeFindings(), isEmpty);
    });
  });

  group('the representative shot', () {
    test('a key never seen has none', () {
      expect(survey().representative('app', 'save'), isNull);
    });

    test('on screen beats offstage', () {
      var it = survey(
        sightings: [
          sighting(step: 'hidden', offstage: true, area: 90000),
          sighting(step: 'shown'),
        ],
      );

      expect(it.representative('app', 'save')?.step, 'shown');
    });

    test('unclipped beats clipped, whatever the size', () {
      var it = survey(
        sightings: [
          sighting(step: 'clipped', overflowed: true, area: 90000),
          sighting(step: 'whole', area: 1000),
        ],
      );

      expect(it.representative('app', 'save')?.step, 'whole');
    });

    test('a screen with context beats a bare one', () {
      var it = survey(
        sightings: [
          sighting(step: 'spinner', textsOnScreen: 1),
          sighting(step: 'in context', textsOnScreen: 20),
        ],
      );

      expect(it.representative('app', 'save')?.step, 'in context');
    });

    test('a step that failed is a last resort', () {
      var it = survey(
        sightings: [
          sighting(step: 'failed', stepFailed: true, textsOnScreen: 40),
          sighting(step: 'passed', textsOnScreen: 20),
        ],
      );

      expect(it.representative('app', 'save')?.step, 'passed');
    });

    test('the choice does not move when an unrelated shot is added', () {
      var first = [sighting(step: 'a'), sighting(step: 'b')];
      var second = [
        sighting(step: 'b'),
        sighting(step: 'a'),
        sighting(key: 'greeting', step: 'c'),
      ];

      expect(
        survey(sightings: first).representative('app', 'save')?.step,
        survey(sightings: second).representative('app', 'save')?.step,
      );
    });
  });

  test('overflowing sightings are the localisation bug list', () {
    var it = survey(
      sightings: [
        sighting(step: 'fine'),
        sighting(key: 'greeting', step: 'clipped', overflowed: true),
      ],
    );

    expect(it.overflowing().map((s) => s.key), ['greeting']);
  });
}
