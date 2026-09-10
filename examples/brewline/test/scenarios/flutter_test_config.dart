import 'dart:async';

import 'package:brewline/shop/mini_markdown.dart';
import 'package:brewline/shop/shop_strings.dart';
import 'package:flutterware/flutter_test.dart';

/// The hook `flutter test` already looks for, found by walking up from each
/// test file. One function decides what every scenario in this folder runs on.
///
/// `flutter test` runs them on the head of each list — an iPhone 16 in English
/// — the studio offers the whole pool, and CI passes a list of its own:
///
/// ```sh
/// flutter test test/scenarios \
///   --dart-define=fw.devices=iphone-16,android-tall \
///   --dart-define=fw.languages=en,fr
/// ```
Future<void> testExecutable(FutureOr<void> Function() testMain) {
  // **The translation seam.** Every value the catalog hands out arrives as a
  // distinct string object per key, so a capture can say which key put which
  // words on which screen — nothing inserted into the text, no pixel moved.
  // These hooks are null in production and cost nothing there.
  ShopStrings.wrapValue = indexTranslations('shop');
  ShopStrings.wrapExpanded = indexExpansions('shop');
  indexTranslationsIn<MiniMarkdown>((widget) => widget.data);
  return runScenarios(
    testMain,
    profile: const ScenarioProfile(
      'phones',
      devices: [Devices.iphone16, Devices.androidTall],
      languages: ['en', 'fr'],
    ),
  );
}
