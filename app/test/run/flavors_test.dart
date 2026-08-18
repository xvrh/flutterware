import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/run/entrypoints.dart';
import 'package:flutterware_app/src/run/flavors.dart';
import 'package:flutterware_app/src/run/refusal.dart';

void main() {
  group('lookupByPlatform', () {
    const paired = {
      RunPlatform.ios: 'appleLocal',
      RunPlatform.mobile: 'patientLocal',
    };

    test('a concrete key beats the shorthand that contains it', () {
      expect(lookupByPlatform(paired, platformType: 'ios'), 'appleLocal');
      expect(lookupByPlatform(paired, platformType: 'android'), 'patientLocal');
    });

    test('a platform in no key is nobody’s business', () {
      expect(lookupByPlatform(paired, platformType: 'macos'), isNull);
      expect(lookupByPlatform(paired, platformType: 'linux'), isNull);
    });

    test('a device with no platform can still match through its category', () {
      // The daemon groups devices the way the shorthands do, so `mobile:`
      // answers for a phone that named no platform — but a *concrete* key
      // cannot, because the category does not say which member it is.
      expect(
        lookupByPlatform(paired, platformType: null, category: 'mobile'),
        'patientLocal',
      );
      expect(
        lookupByPlatform(const {
          RunPlatform.ios: 'appleLocal',
        }, category: 'mobile'),
        isNull,
      );
    });

    test('a device that says nothing about itself matches nothing', () {
      expect(lookupByPlatform(paired), isNull);
    });
  });

  group('resolveFlavor with a pairing', () {
    test('the pairing beats the plain declaration where it applies', () {
      var resolved = resolveFlavor(
        entrypointFlavor: 'local',
        packageDefault: 'dev',
        byPlatform: const {RunPlatform.mobile: 'patientLocal'},
        platformType: 'android',
      );
      expect(resolved.flavor, 'patientLocal');
      // Still the entry point's word — the map is part of its declaration.
      expect(resolved.source, FlavorSource.entrypoint);
    });

    test('and falls through the whole chain where it does not', () {
      const paired = {RunPlatform.mobile: 'patientLocal'};
      expect(
        resolveFlavor(
          entrypointFlavor: 'local',
          packageDefault: 'dev',
          byPlatform: paired,
          platformType: 'macos',
        ).flavor,
        'local',
      );
      expect(
        resolveFlavor(
          entrypointFlavor: null,
          packageDefault: 'dev',
          byPlatform: paired,
          platformType: 'macos',
        ),
        (flavor: 'dev', source: FlavorSource.pubspec),
      );
      expect(
        resolveFlavor(
          entrypointFlavor: null,
          packageDefault: null,
          byPlatform: paired,
          platformType: 'macos',
        ),
        (flavor: null, source: FlavorSource.none),
      );
    });
  });

  group('the declaration round-trips', () {
    test('what Entrypoint writes is what the decoder reads', () {
      var declared = const Entrypoint(
        'lib/main_patient.dart',
        name: 'Patient',
        flavor: 'local',
        flavorByPlatform: {RunPlatform.mobile: 'patientLocal'},
      ).toJson();

      var read = declaredEntrypoints({
        'entrypoints': [declared],
      }).single;
      expect(read.flavor, 'local');
      // As written: the shorthand key survives the wire unexpanded.
      expect(read.flavorByPlatform, {RunPlatform.mobile: 'patientLocal'});
    });

    test('an empty pairing writes no key at all', () {
      expect(
        const Entrypoint('lib/main.dart').toJson(),
        isNot(contains('flavorByPlatform')),
      );
    });

    test('what RunPackage writes is what the decoder reads', () {
      var declared = const RunPackage(
        Pkg('app'),
        flavors: {
          RunPlatform.mobile: ['local', 'patientLocal'],
          RunPlatform.linux: [],
        },
      ).toJson();

      expect(declaredFlavors(declared['flavors']), {
        RunPlatform.mobile: ['local', 'patientLocal'],
        // The empty list survives the wire: it is a declaration, not a gap.
        RunPlatform.linux: <String>[],
      });
      expect(const RunPackage(Pkg('app')).toJson(), isNot(contains('flavors')));
    });

    test('a vocabulary key this build cannot name is dropped', () {
      expect(
        declaredFlavors({
          'mobile': ['local'],
          'fuchsia': ['next'],
          'macos': 'oops',
        }),
        {
          RunPlatform.mobile: ['local'],
        },
      );
    });
  });

  group('applyFlavorVocabulary', () {
    test('no vocabulary checks nothing', () {
      expect(
        applyFlavorVocabulary(
          flavor: 'anything',
          vocabulary: null,
          package: 'app',
          platformLabel: 'linux',
        ),
        'anything',
      );
    });

    test('a flavorless platform drops the flag the way web does', () {
      expect(
        applyFlavorVocabulary(
          flavor: 'local',
          vocabulary: const [],
          package: 'app',
          platformLabel: 'macos',
        ),
        isNull,
      );
    });

    test('a listed flavor passes, an unlisted one refuses with the list', () {
      expect(
        applyFlavorVocabulary(
          flavor: 'staging',
          vocabulary: const ['local', 'staging'],
          package: 'app',
          platformLabel: 'ios',
        ),
        'staging',
      );
      expect(
        () => applyFlavorVocabulary(
          flavor: 'stagign',
          vocabulary: const ['local', 'staging'],
          package: 'app',
          platformLabel: 'ios',
        ),
        throwsA(
          isA<RunRefusal>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('stagign'),
              contains('local, staging'),
              contains('tool/flutterware.dart'),
            ),
          ),
        ),
      );
    });

    test('no flavor at all is nobody’s problem', () {
      expect(
        applyFlavorVocabulary(
          flavor: null,
          vocabulary: const ['local'],
          package: 'app',
          platformLabel: 'ios',
        ),
        isNull,
      );
    });
  });
}
