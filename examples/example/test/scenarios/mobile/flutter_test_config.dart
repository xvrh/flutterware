import 'dart:async';

import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_example/shop/mini_markdown.dart';
import 'package:flutterware_example/shop/shop_strings.dart';

import '../profiles.dart';

/// The hook `flutter test` already looks for, found by walking up from each
/// test file — so this folder says what it is for, and the folder next to it
/// says something else, without either knowing the other exists.
///
/// One line does three jobs: `flutter test` runs these scenarios on an iPhone
/// 16 in English (the head of each list), the GUI offers the whole pool, and
/// CI overrides it with a list of its own:
///
/// ```sh
/// flutter test test/scenarios/mobile \
///   --dart-define=fw.devices=iphone-se,android-tall \
///   --dart-define=fw.languages=en,fr
/// ```
Future<void> testExecutable(FutureOr<void> Function() testMain) {
  // **The translation seam, wired in three lines.**
  //
  // Every value the shop's catalogue hands out now arrives as a distinct
  // string object per key, so the capture can say which key put which words on
  // which screen — with nothing inserted into the text and no pixel moved.
  // Test-only: these hooks are null in production and cost nothing there.
  // Design: `docs/superpowers/specs/2026-08-18-translation-index-design.md`.
  ShopStrings.wrapValue = indexTranslations('shop');
  // Two things identity alone cannot follow, each closed by routing the key
  // rather than guessing it back out of the words. A substitution builds a new
  // string, so the catalogue names the key at the one place that still knows
  // it; and `MiniMarkdown` reparses its source into spans of its own, so the
  // walk reads the original off the widget instead of below it.
  ShopStrings.wrapExpanded = indexExpansions('shop');
  indexTranslationsIn<MiniMarkdown>((widget) => widget.data);
  return runScenarios(testMain, profile: phones);
}
