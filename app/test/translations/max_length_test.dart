import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/translations.dart';
import 'package:flutterware_app/src/translations/max_length.dart';
import 'package:flutterware_app/src/translations/survey.dart';

KeySighting sighting({
  String key = 'save',
  String scenario = 'home_test/Home',
  String step = 'Home',
  int stepIndex = 1,
  String? position,
  String? device,
  bool offstage = false,
  bool overflowed = false,
  int? charStart,
}) => KeySighting(
  catalog: 'app',
  key: key,
  scenario: scenario,
  step: step,
  stepIndex: stepIndex,
  position: position ?? '#$stepIndex',
  image: '$step.png',
  device: device,
  offstage: offstage,
  overflowed: overflowed,
  charStart: charStart,
);

TranslationSurvey survey({
  List<KeySighting> sightings = const [],
  List<ScreenOverflow> screenOverflows = const [],
}) => TranslationSurvey(
  catalogs: const {},
  sightings: sightings,
  unkeyed: const [],
  read: const {},
  screenOverflows: screenOverflows,
);

/// What the probe would have rendered for `app/[key]` at [level] — the same
/// deterministic padding the guest applies.
String rendered(String key, String value, int level) =>
    value +
    TranslationIndex.expansionPadding(
      'app',
      key,
      TranslationIndex.expansionLength(value.length, level),
    );

String? values(String catalog, String key) =>
    {'save': 'Save the draft', 'title': 'Home'}[key];

TranslationMaxLengths measure({
  List<KeySighting> baseline = const [],
  List<ProbePass> passes = const [],
  List<({int level, TranslationSurvey survey})> evidence = const [],
}) => computeMaxLengths(
  baseline: ProbeBaseline(survey(sightings: baseline)),
  passes: passes,
  values: values,
  evidence: evidence,
);

void main() {
  group('a max length', () {
    test('is the proven bracket, reconstructed as the tested strings', () {
      var it = measure(
        baseline: [sighting(device: 'pixel-4a')],
        passes: [
          ProbePass(level: 10, survey: survey(sightings: [sighting()])),
          ProbePass(
            level: 20,
            survey: survey(sightings: [sighting(overflowed: true)]),
          ),
        ],
      );

      var limit = it.byKey['app/save']!;
      expect(limit.bounded, isTrue);
      expect(limit.fitsText, rendered('save', 'Save the draft', 10));
      expect(limit.chars, limit.fitsText!.length);
      expect(limit.clipsText, rendered('save', 'Save the draft', 20));
      expect(limit.clipsChars, limit.clipsText!.length);
      expect(limit.screen?.device, 'pixel-4a');
      expect(it.bounded, 1);
      expect(it.devices, ['pixel-4a']);
    });

    test('clipping at the first rung is bounded by the value itself', () {
      // The cell was clean unpadded, so the source's own length is the
      // proven fit — the tightest honest answer available.
      var it = measure(
        baseline: [sighting()],
        passes: [
          ProbePass(
            level: 10,
            survey: survey(sightings: [sighting(overflowed: true)]),
          ),
        ],
      );

      var limit = it.byKey['app/save']!;
      expect(limit.fitsText, 'Save the draft');
      expect(limit.chars, 'Save the draft'.length);
      expect(limit.clipsText, rendered('save', 'Save the draft', 10));
    });

    test(
      'never clipping is an open bound at the highest rung, not a limit',
      () {
        var it = measure(
          baseline: [sighting()],
          passes: [
            ProbePass(level: 10, survey: survey(sightings: [sighting()])),
            ProbePass(level: 100, survey: survey(sightings: [sighting()])),
          ],
        );

        var limit = it.byKey['app/save']!;
        expect(limit.bounded, isFalse);
        expect(limit.fitsText, rendered('save', 'Save the draft', 100));
        expect(limit.chars, limit.fitsText!.length);
        expect(it.bounded, 0);
      },
    );

    test('a sighting clipped at the probe baseline is excluded', () {
      // It ellipsizes today by someone's choice; the probe showing it clipped
      // again says nothing about room.
      var it = measure(
        baseline: [sighting(overflowed: true)],
        passes: [
          ProbePass(
            level: 10,
            survey: survey(sightings: [sighting(overflowed: true)]),
          ),
        ],
      );

      expect(it.byKey, isEmpty);
    });

    test('an offstage sighting attributes nothing', () {
      var it = measure(
        baseline: [sighting(offstage: true)],
        passes: [
          ProbePass(
            level: 10,
            survey: survey(sightings: [sighting(overflowed: true)]),
          ),
        ],
      );

      expect(it.byKey, isEmpty);
    });

    test('a key the ladder never reached gets no number at all', () {
      // A diverged scenario pairs with nothing — fail closed, not "fits".
      var it = measure(
        baseline: [sighting()],
        passes: [ProbePass(level: 10, survey: survey())],
      );

      expect(it.byKey, isEmpty);
    });

    test('two keys on one step are measured apart', () {
      var it = measure(
        baseline: [
          sighting(key: 'save'),
          sighting(key: 'title'),
        ],
        passes: [
          ProbePass(
            level: 10,
            survey: survey(
              sightings: [
                sighting(key: 'save', overflowed: true),
                sighting(key: 'title'),
              ],
            ),
          ),
        ],
      );

      expect(it.byKey['app/save']?.bounded, isTrue);
      expect(it.byKey['app/title']?.bounded, isFalse);
    });

    test(
      'a step already clipping once at baseline still flips on a second',
      () {
        // One instance ellipsizes by design, its sibling was clean — the
        // probe showing two clipped is the clean one flipping.
        var it = measure(
          baseline: [
            sighting(charStart: 0, overflowed: true),
            sighting(charStart: 9),
          ],
          passes: [
            ProbePass(
              level: 10,
              survey: survey(
                sightings: [
                  sighting(charStart: 0, overflowed: true),
                  sighting(charStart: 9, overflowed: true),
                ],
              ),
            ),
          ],
        );

        expect(it.byKey['app/save']?.bounded, isTrue);
      },
    );

    test('the constraining pick does not depend on arrival order', () {
      var early = sighting(charStart: 0);
      var late = sighting(charStart: 9);
      var flipped = [sighting(charStart: 0, overflowed: true)];

      for (var baseline in [
        [early, late],
        [late, early],
      ]) {
        var it = measure(
          baseline: baseline,
          passes: [ProbePass(level: 10, survey: survey(sightings: flipped))],
        );

        expect(it.byKey['app/save']?.screen?.charStart, 0);
      }
    });

    test('the clip photograph pairs by cell at the clipping level', () {
      var clippedShot = sighting(overflowed: true, device: 'pixel-4a');
      var it = measure(
        baseline: [sighting()],
        passes: [
          ProbePass(
            level: 10,
            survey: survey(sightings: [sighting(overflowed: true)]),
          ),
        ],
        evidence: [
          // The wrong level must not supply the picture.
          (level: 20, survey: survey(sightings: [clippedShot])),
          (level: 10, survey: survey(sightings: [clippedShot])),
        ],
      );

      expect(it.byKey['app/save']?.clipped, same(clippedShot));
    });
  });

  group('a screen break', () {
    test('reports the lowest level a step overflowed at', () {
      ScreenOverflow overflow(int count) => (
        scenario: 'home_test/Home',
        step: 'Home',
        stepIndex: 1,
        position: '#1',
        locale: null,
        count: count,
      );
      var it = measure(
        passes: [
          ProbePass(level: 10, survey: survey()),
          ProbePass(level: 20, survey: survey(screenOverflows: [overflow(1)])),
          ProbePass(level: 30, survey: survey(screenOverflows: [overflow(4)])),
        ],
      );

      var broke = it.breaks.single;
      expect(broke.level, 20);
      expect(broke.overflows, 1);
      expect(broke.stepIndex, 1);
    });

    test('a scenario red under expansion is a break with its failure', () {
      var it = measure(
        passes: [
          ProbePass(
            level: 30,
            survey: survey(),
            failures: [
              (scenario: 'cart_test/Cart', failure: 'tap found nothing'),
            ],
          ),
        ],
      );

      var broke = it.breaks.single;
      expect(broke.scenario, 'cart_test/Cart');
      expect(broke.level, 30);
      expect(broke.failure, 'tap found nothing');
      expect(broke.stepIndex, isNull);
    });
  });
}
