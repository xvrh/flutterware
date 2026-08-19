import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '../devices.dart';
import '../translations/index.dart';
import 'fonts.dart';

/// What a folder of scenarios is *for* — the devices and languages worth
/// offering them in.
///
/// Declared once, centrally, and named by a folder's `flutter_test_config.dart`
/// (which `flutter test` discovers by walking up from each test file, so a
/// mobile folder and a desktop folder can say different things without either
/// knowing about the other).
///
/// **The list is the offered set, and its head is the default.** The GUI shows
/// all of it; a bare `flutter test` takes the first. That is one list doing
/// both jobs, and it is why "show every phone in the picker but run two in CI"
/// is not a contradiction — CI brings its own list, and a profile never
/// declares one.
///
/// ```dart
/// // test/scenarios/mobile/flutter_test_config.dart
/// const phones = ScenarioProfile(
///   'phones',
///   devices: [Devices.iphone16, Devices.iphoneSe, Devices.androidTall],
///   languages: ['en', 'fr'],
/// );
///
/// Future<void> testExecutable(FutureOr<void> Function() testMain) =>
///     runScenarios(testMain, profile: phones);
/// ```
class ScenarioProfile {
  const ScenarioProfile(
    this.name, {
    this.devices = const [],
    this.languages = const [],
    this.orientations = const [],
  });

  /// What the profile is called — in the panel, and in a `--profile=` on the
  /// command line.
  final String name;

  /// The devices this folder's scenarios are worth looking at on. The first is
  /// what a run picks when nobody chose.
  final List<Device> devices;

  /// The locale tags, first one likewise. Empty means the platform default,
  /// which is what a project with one language wants and should not have to
  /// say.
  final List<String> languages;

  /// The orientations worth crossing the devices with, first one likewise.
  /// Empty means portrait, which is what almost every folder wants and should
  /// not have to say.
  ///
  /// Crossed rather than listed alongside the devices: a tablet in landscape is
  /// the same tablet, so `devices × orientations` is two short lists instead of
  /// one long one with the rotatable entries written twice.
  final List<ScreenOrientation> orientations;
}

/// One point of a matrix: the device, orientation and language a scenario is
/// running as.
class ScenarioAssignment {
  const ScenarioAssignment({this.device, this.orientation, this.language});

  final Device? device;
  final String? language;

  /// Null and [ScreenOrientation.portrait] mean the same thing here, and both
  /// leave every name below untouched — see [_landscape].
  final ScreenOrientation? orientation;

  /// The device this assignment actually renders as: the rotation is resolved
  /// once, here, and everything downstream reads plain geometry off it.
  Device? get orientedDevice => device?.oriented(orientation);

  /// Whether this point departs from portrait — the only case that earns a
  /// segment in a name.
  ///
  /// **Portrait writes nothing.** A name that grew a `-portrait` would move
  /// every artifact path that exists today, in every project, to record the
  /// default. Landscape is the departure, so landscape is what gets said.
  bool get _landscape =>
      orientation == ScreenOrientation.landscape &&
      (device?.canRotate ?? false);

  /// What names this assignment in a test's description and in an artifact
  /// path — `iphone-16-fr`, `ipad-landscape-fr`, or the empty string when
  /// nothing was assigned.
  String get slug =>
      [?device?.id, if (_landscape) 'landscape', ?language].join('-');

  /// How it reads in a test name: `[iPhone 16 · fr]`, `[iPad · landscape · fr]`.
  String get label =>
      [?device?.label, if (_landscape) 'landscape', ?language].join(' · ');

  bool get isEmpty => device == null && language == null && !_landscape;
}

/// The assignment the scenarios being declared right now belong to.
///
/// Set by [runScenarios] around each pass and read by `scenario()` **as it
/// declares**, so every test carries its own axes rather than reading a mutable
/// global when it runs. Null under the flutterware runner, which supplies the
/// assignment per request instead.
ScenarioAssignment? scenarioAmbientAssignment;

/// The `testExecutable` a scenario folder's `flutter_test_config.dart` hands to
/// `flutter test`.
///
/// Runs [testMain] once per assignment. With nothing configured that is a
/// single pass at the head of each axis — the fast inner loop, and the reason
/// `flutter test` on a scenario folder stays as quick as it was. CI asks for
/// more:
///
/// ```sh
/// flutter test --dart-define=fw.devices=iphone-se,iphone-16 \
///              --dart-define=fw.languages=en,fr,de \
///              --dart-define=fw.orientations=portrait,landscape
/// FW_DEVICES=iphone-se,iphone-16 FW_LANGUAGES=en,fr flutter test
/// ```
///
/// Both are read, the define wins, and the same pair of sources already serves
/// `screenshots-destination` — one convention for "the host tells the test
/// process something", not two. The loop lives here rather than outside, so a
/// matrix is one invocation and one compile.
///
/// Also loads the project's fonts, once, before anything is declared — the
/// step `flutter test` otherwise leaves to each project's own
/// `flutter_test_config.dart`. Without it this lane measures text in the
/// fallback font while the flutterware harness measures it in the real one,
/// and the disagreement surfaces as overflows on screens that do not overflow.
Future<void> runScenarios(
  FutureOr<void> Function() testMain, {
  ScenarioProfile? profile,
}) async {
  // Under the flutterware runner this is called to *ask* what the folder is
  // for, not to declare anything: the harness reads the profile here and
  // declares the files itself, one pass, with the axes the request named.
  // Whatever setup the config does around `testMain` still runs — which is the
  // point of coming through this door rather than parsing the file.
  // Armed before the probe returns, not after: under the harness this function
  // is called only to *ask* what the folder is for, so anything below the
  // early return never runs in the runner's lane. The harness arms it too, for
  // the folder that declares no config at all.
  TranslationIndex.recording = true;

  if (scenarioProbing) {
    scenarioProbedProfile = profile;
    return;
  }

  // Before the first declaration and after the probe returns: the harness
  // loads its own, and a scenario laid out in the fallback font reports itself
  // as `RenderFlex overflowed by 3.5 pixels` rather than as a font problem.
  //
  // The defaults too, and only here: this line runs under bare `flutter test`
  // alone — the harness probes and returns above — which is exactly the lane
  // whose `--use-test-fonts` boxes every family nobody loads bytes for. See
  // [loadDefaultScenarioFonts] for why the harness must not do this.
  await loadScenarioFonts();
  await loadDefaultScenarioFonts();

  var assignments = scenarioAssignments(profile);
  try {
    for (var assignment in assignments) {
      scenarioAmbientAssignment = assignment;
      // More than one pass means the same scenario is declared more than once,
      // so its name has to say which is which. One pass leaves names alone —
      // nobody wants `Counter [iPhone 16 · en]` in a suite that runs one way.
      scenarioAmbientIsMatrix = assignments.length > 1;
      await testMain();
    }
  } finally {
    scenarioAmbientAssignment = null;
    scenarioAmbientIsMatrix = false;
  }
}

/// Whether more than one assignment is being declared — the switch that puts
/// the axis in a scenario's name.
bool scenarioAmbientIsMatrix = false;

/// Set by the harness while it asks a folder's `flutter_test_config.dart` what
/// its profile is. [runScenarios] answers and declares nothing.
///
/// The seam exists because declaration must stay **synchronous** — `test_api`
/// builds the group the moment the declaring closure returns, so a config that
/// awaits anything before calling `testMain` would declare into a group that
/// had already been built. Asking first, declaring after, keeps both honest.
bool scenarioProbing = false;

/// What the last probed config declared.
ScenarioProfile? scenarioProbedProfile;

/// The assignments one `flutter test` invocation should declare: the request's
/// lists when it made any, and the profile's own heads when it did not.
///
/// A device a run names but the table does not know is refused rather than
/// approximated — running at the wrong screen produces a picture that is wrong
/// without looking wrong.
@visibleForTesting
List<ScenarioAssignment> scenarioAssignments(
  ScenarioProfile? profile, {
  String? devicesOverride,
  String? languagesOverride,
  String? orientationsOverride,
}) {
  var deviceIdList = _list(
    devicesOverride ?? _setting('devices', 'FW_DEVICES'),
  );
  var languageList = _list(
    languagesOverride ?? _setting('languages', 'FW_LANGUAGES'),
  );
  var orientationList = _list(
    orientationsOverride ?? _setting('orientations', 'FW_ORIENTATIONS'),
  );

  var devices = <Device?>[];
  if (deviceIdList.isNotEmpty) {
    for (var id in deviceIdList) {
      if (id == fitDeviceId) {
        devices.add(null);
        continue;
      }
      var device = deviceById(id);
      if (device == null) {
        throw ArgumentError.value(
          id,
          'fw.devices',
          'no such device. Accepted: ${deviceIds.join(', ')}',
        );
      }
      devices.add(device);
    }
  } else {
    devices.add(profile?.devices.firstOrNull);
  }

  var languages = <String?>[];
  if (languageList.isNotEmpty) {
    languages.addAll(languageList);
  } else {
    languages.add(profile?.languages.firstOrNull);
  }

  var orientations = <ScreenOrientation?>[];
  if (orientationList.isNotEmpty) {
    for (var name in orientationList) {
      var orientation = orientationById(name);
      if (orientation == null) {
        throw ArgumentError.value(
          name,
          'fw.orientations',
          'no such orientation. Accepted: ${orientationIds.join(', ')}',
        );
      }
      orientations.add(orientation);
    }
  } else {
    orientations.add(profile?.orientations.firstOrNull);
  }

  return [
    for (var device in devices)
      // **A device that cannot turn contributes one point, not two.** Crossing
      // a desktop with both orientations would run it twice for byte-identical
      // pixels, which is a doubled CI bill for a picture nobody asked for
      // twice. The bare surface collapses for the same reason.
      for (var orientation
          in (device?.canRotate ?? false)
              ? orientations
              : const <ScreenOrientation?>[null])
        for (var language in languages)
          ScenarioAssignment(
            device: device,
            orientation: orientation,
            language: language,
          ),
  ];
}

/// A dart-define, then an environment variable — the pair
/// `screenshots-destination` already reads, for the same reason.
String? _setting(String define, String variable) {
  var defined = switch (define) {
    'devices' => const String.fromEnvironment('fw.devices'),
    'languages' => const String.fromEnvironment('fw.languages'),
    'orientations' => const String.fromEnvironment('fw.orientations'),
    _ => '',
  };
  if (defined.isNotEmpty) return defined;
  var value = Platform.environment[variable];
  return (value == null || value.isEmpty) ? null : value;
}

List<String> _list(String? raw) => [
  if (raw != null)
    for (var part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
];
