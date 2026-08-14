import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads every font the asset bundle's `FontManifest.json` declares — the
/// project's own families plus `MaterialIcons`.
///
/// **Both scenario lanes come through here**, because a scenario that measures
/// text in the fallback font is wrong in the one way nothing catches: it still
/// renders, still passes most assertions, and reports the few that do not as
/// `RenderFlex overflowed by 3.5 pixels` — a layout regression that never
/// happened. The harness loads them at startup; `flutter test` used to have
/// nobody to do it, so the same suite disagreed with itself across the two.
///
/// Cached, so the second caller awaits the first one's work rather than
/// repeating it. `FontLoader` registers into a process-wide collection, so
/// loading twice is waste and nothing else.
Future<List<String>> loadScenarioFonts() => _loading ??= _load();

Future<List<String>>? _loading;

/// The families [loadScenarioFonts] has loaded, or null while nobody has
/// loaded any — which is the difference a lane's own test asserts on, an empty
/// manifest and an unloaded one being otherwise indistinguishable.
List<String>? get loadedScenarioFonts => _loaded;
List<String>? _loaded;

@visibleForTesting
void resetScenarioFontsForTest() {
  _loading = null;
  _loaded = null;
}

Future<List<String>> _load() async {
  // The binding owns both the messenger `rootBundle` loads through and the
  // font collection `FontLoader` registers into, so it has to exist first.
  // Under the harness it already does; under `flutter test` this is the
  // earliest anything has needed it.
  TestWidgetsFlutterBinding.ensureInitialized();

  var manifest = await _manifest();
  var families = <String>[];
  for (var entry in manifest.cast<Map<String, dynamic>>()) {
    var family = entry['family']! as String;
    var loader = FontLoader(family);
    for (var font in (entry['fonts']! as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    // Deliberately unguarded: a family the manifest declares and the bundle
    // cannot supply is a broken build, and swallowing it would put the suite
    // straight back on fallback metrics with nothing said.
    await loader.load();
    families.add(family);
  }
  return _loaded = families;
}

/// The manifest's entries, or none when the bundle carries no manifest at all.
///
/// A bundle without one is a project with no fonts, and that may not start
/// failing suites that pass today. A manifest that *is* there and cannot be
/// read is the opposite case and is left to throw: swallowing it would put the
/// suite back on fallback metrics with nothing said, which is the bug this
/// file exists to close.
Future<List<dynamic>> _manifest() async {
  String source;
  try {
    source = await rootBundle.loadString('FontManifest.json');
  } on FlutterError {
    return const [];
  }
  return jsonDecode(source) as List<dynamic>;
}
