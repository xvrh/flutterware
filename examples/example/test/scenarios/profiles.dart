/// What this project's scenario folders are for.
///
/// Declared once, here, and named by each folder's `flutter_test_config.dart`
/// — which is why the runner *executes* those configs rather than reading
/// them: a profile that lives in another file works exactly as well as one
/// written in place.
///
/// **The list is the offered set, and its head is the default.** The GUI shows
/// all of it and CI brings its own list, so "show every phone in the picker,
/// run two on CI" is not a contradiction.
library;

import 'package:flutterware/flutter_test.dart';

const phones = ScenarioProfile(
  'phones',
  devices: [Devices.iphone16, Devices.iphoneSe, Devices.androidTall],
  languages: ['en', 'fr'],
);

/// Brewline on a wide window. Fewer languages on purpose — a profile carries
/// the languages that go with *its* pool, and a desktop build that ships
/// English only should not be told to screenshot French.
const desktop = ScenarioProfile(
  'desktop',
  devices: [Devices.wideWindow, Devices.windowsWindow],
  languages: ['en'],
);
