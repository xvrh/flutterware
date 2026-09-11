/// Where a store banner's words and pixels come from — the join that turns
/// `StoreHero`'s parameters into one locale's banner.
///
/// The scene (`demo/store_hero.scene.dart`) is a *layout*: it knows there is a
/// headline, a subtitle, a call to action and two screenshots, and it knows
/// nothing about English, French or where an export tree is. This file is the
/// other half — the one a person changes when the copy moves or the export
/// moves — and it is deliberately small, because everything interesting is
/// already in the scene or already in the catalog.
///
/// Both halves of the injection are things the project already has:
///
///   * the **words** are the `store` translation catalog the Translations
///     panel shows (`assets/store/*.json`), read the same way the listing's
///     frame reads its headlines;
///   * the **pixels** are what `store export` already wrote — the app's own
///     screenshots, kept beside the listing under `unframed/` precisely so
///     something else can compose them.
///
/// Nothing here is flutterware API. It is one project's answer to "where do my
/// words and my screenshots live", and a different project would answer
/// differently without any of the machinery changing.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

/// The store locale a scenario's app locale maps to — the same pairing
/// `tool/flutterware.dart` declares for the listing, and the name the export
/// tree's directories carry.
const storeLocales = {'en': 'en-US', 'fr': 'fr-FR'};

/// One locale's banner copy, by key, from the `store` catalog.
///
/// Read off disk synchronously: a scene's `build` cannot await, and copy that
/// arrived a frame late would be photographed as an empty band.
String storeCopy(String key, String locale) =>
    _catalog(locale)[key] ?? _catalog('en')[key] ?? '';

/// Where an exported, unframed screenshot is — the app's own pixels, before
/// any listing composition touched them.
///
/// [shot] is the numbered slug `store export` writes, `01-welcome`. Returns an
/// empty string when nothing has been exported yet, which is what
/// [ShotImage] draws its "no screenshot" plate for: the banner still composes,
/// and the hole is visible rather than silent.
String storeShotPath(
  String shot, {
  required String locale,
  String store = 'app-store',
  String deviceClass = 'iphone-6-9',
}) {
  var root = _find(
    'build/flutterware/store/flutterware_probes/unframed/'
    '$store/$deviceClass/${storeLocales[locale] ?? locale}/$shot.png',
  );
  return root?.path ?? '';
}

Map<String, String> _catalog(String locale) => _loaded.putIfAbsent(locale, () {
  var file = _find('assets/store/$locale.json');
  if (file == null) return const {};
  return {
    for (var entry in (jsonDecode(file.readAsStringSync()) as Map).entries)
      '${entry.key}': '${entry.value}',
  };
});

/// Resolves a package-relative path from wherever the renderer happened to be
/// started — the harness runs in the package root, a preview host may not, and
/// a missing headline is exactly what a preview exists to catch.
///
/// Public because [ShotImage] needs the same walk: a scene's mockup default is
/// a relative path so it can be committed, and the guest that draws the canvas
/// is started somewhere else again.
File? findPackageFile(String path) => _find(path);

File? _find(String path) {
  var directory = Directory.current;
  for (var up = 0; up < 4; up++) {
    for (var candidate in [
      File('${directory.path}/$path'),
      File('${directory.path}/fixtures/probe_app/$path'),
    ]) {
      if (candidate.existsSync()) return candidate;
    }
    directory = directory.parent;
  }
  return null;
}

final _loaded = <String, Map<String, String>>{};

/// Every argument one locale's banner needs, as plain values.
///
/// A record rather than a class: this exists to be spread into
/// `StoreHero(...)`, and naming it once here is what keeps the preview, the
/// render point and the video from each spelling the join differently.
({String headline, String subtitle, String cta, String front, String back})
storeHeroFor(
  String locale, {
  String front = '01-welcome',
  String back = '02-menu',
}) => (
  headline: storeCopy('banner-headline', locale),
  subtitle: storeCopy('banner-subtitle', locale),
  cta: storeCopy('banner-cta', locale),
  front: storeShotPath(front, locale: locale),
  back: storeShotPath(back, locale: locale),
);

/// The locale a scene should be *drawn* under, for the day the banner holds a
/// widget of the app's rather than only text the catalog answered.
Locale localeOf(String tag) => Locale(tag);
