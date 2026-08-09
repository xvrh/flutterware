/// Where an edit to a value you are *looking at* should be written.
///
/// The rule, and it is the one thing in this file worth arguing about:
/// **the default target is the key that won the cascade**, not the most specific
/// key for the cell you happen to be on.
///
/// If a tile says `#101418 · from color_dark` and you change the colour, you
/// mean `color_dark`. The caption already told you where the value lives, so
/// writing there is the answer with no surprise in it. Getting this backwards —
/// writing `color_dark_android` because you were looking at the Android tile —
/// produces a config that grows a platform override every time somebody nudges a
/// colour, and after a month nobody can say what the base value is for.
///
/// The narrower key is still offered, second, because "only on Android" is a
/// real thing to want. It is a choice, not a default.
library;

import 'surface.dart';
import 'validation.dart';

/// One key an edit could go to.
class SplashEditTarget {
  const SplashEditTarget(this.key, this.label);

  /// Dotted for the section — `android_12.color`.
  final String key;

  /// Why you would pick it — 'where it is set now', 'only for Android 12+'.
  final String label;

  @override
  String toString() => '$key ($label)';
}

/// The keys an edit to [key], seen on [surface], could be written to.
///
/// Always at least one, always with the key that won first.
List<SplashEditTarget> splashEditTargets({
  required String key,
  required SplashSurface surface,
}) {
  var targets = [SplashEditTarget(key, 'where it is set now')];

  var narrower = _narrowerKey(key, surface);
  if (narrower != null && narrower != key && _isKnown(narrower)) {
    targets.add(SplashEditTarget(narrower, 'only for ${surface.label}'));
  }
  return targets;
}

/// The key that would set this value for [surface] alone.
///
/// Android 12 is not "the Android suffix" — it is the `android_12:` section, and
/// it reads the **top-level** `color`, never `color_android`. So narrowing a
/// value onto that surface means moving it into the section, not adding a
/// suffix, and a suffix already on the key has to come off on the way.
String? _narrowerKey(String key, SplashSurface surface) {
  if (key.startsWith('android_12.')) return null;

  var base = key;
  for (var suffix in ['android', 'ios', 'web']) {
    if (base.endsWith('_$suffix')) {
      base = base.substring(0, base.length - suffix.length - 1);
      // Already as narrow as it goes for its own platform.
      if (surface != SplashSurface.android12) return null;
    }
  }

  if (surface == SplashSurface.android12) return 'android_12.$base';
  return '${base}_${surface.keySuffix}';
}

/// Whether the generator would accept this key at all.
///
/// A narrower key that does not exist — there is no `branding_bottom_padding_web`
/// — must not be offered, because writing it is the one thing that stops `create`
/// from running.
bool _isKnown(String key) {
  if (key.startsWith('android_12.')) {
    return splashAndroid12Keys.contains(key.substring('android_12.'.length));
  }
  return splashKnownKeys.contains(key);
}
