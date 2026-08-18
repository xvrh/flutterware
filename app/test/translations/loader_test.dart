import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_results.dart';
import 'package:flutterware_app/src/translations/loader.dart';
import 'package:flutterware_app/src/translations/survey.dart';
import 'package:path/path.dart' as p;

ScenarioRunStep step({
  int index = 1,
  String? name = 'Home',
  String? keys = 'step.keys.json',
  List<String> texts = const ['a', 'b'],
  String? failure,
}) => ScenarioRunStep(
  index: index,
  position: 'root#$index',
  auto: false,
  image: 'step.png',
  format: 'png',
  width: 390,
  height: 844,
  tree: 'step.tree.json',
  keys: keys,
  texts: texts,
  address: 'fw:///x',
  name: name,
  failure: failure,
);

ScenarioRunResult run({
  List<ScenarioRunStep> steps = const [],
  Map<String, String>? axes,
  Map<String, Map<String, String>>? translations,
}) => ScenarioRunResult(
  packages: [
    ScenarioRunPackage(
      path: '.',
      output: '/out',
      axes: axes,
      ms: 1,
      scenarios: [
        ScenarioRunOutcome(
          file: 'home_test.dart',
          name: 'Home',
          ok: true,
          device: 'iphone-13',
          steps: steps,
          translations: translations,
        ),
      ],
    ),
  ],
);

String keysArtifact({
  List<Map<String, Object?>> keys = const [],
  List<Map<String, Object?>> unkeyed = const [],
}) => jsonEncode({'keys': keys, 'unkeyed': unkeyed});

void main() {
  group('building a survey from a run', () {
    test(
      "a step's keys become sightings carrying where they were seen",
      () async {
        var survey = await buildSurvey(
          run: run(steps: [step()], axes: {'language': 'nl'}),
          catalogs: const {},
          readArtifact: (path) async => keysArtifact(
            keys: [
              {
                'catalog': 'app',
                'key': 'save',
                'start': 0,
                'end': 4,
                'rect': '10,20 100×40',
              },
            ],
          ),
        );

        var sighting = survey.occurrencesOf('app', 'save').single;
        expect(sighting.scenario, 'home_test.dart/Home');
        expect(sighting.step, 'Home');
        expect(sighting.locale, 'nl');
        expect(sighting.device, 'iphone-13');
        expect(sighting.image, 'step.png');
        expect(sighting.area, 4000, reason: '100×40, for the ranking');
        expect(sighting.textsOnScreen, 2);
      },
    );

    test('a step with no keys artifact is skipped, not an error', () async {
      var survey = await buildSurvey(
        run: run(steps: [step(keys: null), step(index: 2)]),
        catalogs: const {},
        readArtifact: (path) async => null,
      );

      expect(survey.sightings, isEmpty);
    });

    test('a failed step marks its sightings', () async {
      var survey = await buildSurvey(
        run: run(steps: [step(failure: 'boom')]),
        catalogs: const {},
        readArtifact: (path) async => keysArtifact(
          keys: [
            {'catalog': 'app', 'key': 'save'},
          ],
        ),
      );

      expect(survey.sightings.single.stepFailed, isTrue);
    });

    test('unkeyed words carry where they were built', () async {
      var survey = await buildSurvey(
        run: run(steps: [step()]),
        catalogs: const {},
        readArtifact: (path) async => keysArtifact(
          unkeyed: [
            {
              'text': 'Fri, Dec 15',
              'node': '0/1',
              'source': {
                'file': 'file:///project/lib/home.dart',
                'line': 42,
                'column': 7,
              },
            },
          ],
        ),
      );

      expect(survey.unkeyed.single.text, 'Fri, Dec 15');
      expect(survey.unkeyed.single.source, 'home.dart:42:7');
    });

    test("the read set is filed under the point's locale", () async {
      var survey = await buildSurvey(
        run: run(
          axes: {'language': 'nl'},
          translations: {
            'app': {'save': 'Save'},
          },
        ),
        catalogs: {
          'app': const LoadedCatalog(
            name: 'app',
            template: 'en',
            byLocale: {
              'en': {'save': 'Save'},
              'nl': {},
            },
          ),
        },
        readArtifact: (path) async => null,
      );

      // The whole point of filing it by locale: this is only a finding
      // because the run was `nl` and `nl` has no text for the key.
      expect(survey.localeFindings().single.verdict, LocaleVerdict.fallingBack);
    });
  });

  group('loading catalogs', () {
    test('a file per locale becomes a locale per catalog', () async {
      var loaded = await loadCatalogs(
        [(name: 'app', files: 'l10n/*.json', template: 'en')],
        read: (glob) async => {
          'l10n/en.json': '{"save":"Save"}',
          'l10n/nl.json': '{"save":"Opslaan"}',
        },
      );

      expect(loaded['app']!.byLocale.keys, containsAll(['en', 'nl']));
      expect(loaded['app']!.valueOf('nl', 'save'), 'Opslaan');
      expect(loaded['app']!.keys, {'save'});
    });

    test('a file that is not a locale is skipped, not loaded as one', () async {
      var loaded = await loadCatalogs(
        [(name: 'app', files: 'l10n/*.json', template: 'en')],
        read: (glob) async => {
          'l10n/en.json': '{"save":"Save"}',
          'l10n/schema.json': '{"anything":"here"}',
        },
      );

      expect(loaded['app']!.byLocale.keys, ['en']);
    });

    test('a glob matching nothing keeps the catalog, empty', () async {
      var loaded = await loadCatalogs([
        (name: 'app', files: 'nowhere/*.json', template: 'en'),
      ], read: (glob) async => {});

      // Kept rather than dropped: an empty catalog names the problem, a
      // missing one silently unattributes every key that belonged to it.
      expect(loaded, contains('app'));
      expect(loaded['app']!.keys, isEmpty);
    });

    test('a non-string value is left out rather than stringified', () async {
      var loaded = await loadCatalogs(
        [(name: 'app', files: 'l10n/*.json', template: 'en')],
        read: (glob) async => {
          'l10n/en.json': '{"save":"Save","meta":{"note":"x"}}',
        },
      );

      expect(loaded['app']!.keys, {'save'});
    });
  });

  group('reading a package off disk', () {
    late Directory package;

    setUp(() {
      package = Directory.systemTemp.createTempSync('fw-package');
      File(p.join(package.path, 'assets', 'i18n', 'en.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"save":"Save"}');
    });
    tearDown(() => package.deleteSync(recursive: true));

    test('finds the catalog beside the package', () async {
      var files = await catalogFilesUnder(package.path)('assets/i18n/*.json');

      expect(files.keys, [p.join('assets', 'i18n', 'en.json')]);
    });

    test('does not descend into build or hidden directories', () async {
      // Not a tidiness rule — this is what made the panel hang. A Flutter
      // package's `build/` is enormous and `.dart_tool` holds links back into
      // the pub cache, so a plain recursive listing of the package root does
      // not finish.
      var decoy = File(p.join(package.path, 'build', 'i18n', 'en.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"stale":"Stale"}');
      File(p.join(package.path, '.dart_tool', 'i18n', 'en.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"stale":"Stale"}');

      var files = await catalogFilesUnder(package.path)('**/i18n/*.json');

      expect(
        files.keys,
        isNot(contains(p.relative(decoy.path, from: package.path))),
      );
      expect(files.keys, [p.join('assets', 'i18n', 'en.json')]);
    });

    test('a glob pointing nowhere reads as no files, not as a crawl', () async {
      var files = await catalogFilesUnder(package.path)('nowhere/*.json');

      expect(files, isEmpty);
    });
  });
}
