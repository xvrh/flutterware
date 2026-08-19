/// A strict superset of `package:flutter_test` — everything re-exported 1:1,
/// nothing hidden, plus the scenario API. An existing test file compiles with
/// only its import changed.
library;

export 'package:flutter_test/flutter_test.dart';

export 'src/canvases.dart';
export 'src/devices.dart';
export 'src/motion/testing.dart';
export 'src/previews/harness.dart' show PreviewEntry, runPreviewHarness;
export 'src/scenarios/asset_bundle.dart' show ScenarioAssetBundle;
export 'src/scenarios/fonts.dart' show loadScenarioFonts, loadedScenarioFonts;
export 'src/scenarios/events.dart'
    show ScenarioChannel, ScenarioEvent, recordScenarioEvent;
export 'src/scenarios/notification.dart' show ScenarioNotification;
export 'src/scenarios/profile.dart'
    show ScenarioAssignment, ScenarioProfile, runScenarios;
export 'src/scenarios/scenario.dart';
export 'src/scenarios/settle.dart';
export 'src/scenarios/staging.dart' show DeviceStaging;
export 'src/scenarios/target.dart' show Target, describeTarget, finderForTarget;
export 'src/translations/index.dart'
    show
        TranslationIndex,
        TranslationKey,
        indexExpansions,
        indexTranslations,
        indexTranslationsIn;
