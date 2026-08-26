/// The listing's headlines — marketing copy, in a catalog of its own.
///
/// Decision 9. Not in `assets/i18n/`, where the app's own strings live: a
/// headline is never shown *in* the app, and mixing it in beside `Add to cart`
/// would send it to a translator as though it were UI. Its own directory, its
/// own catalog, declared separately in `tool/flutterware.dart` — which also
/// gives the Translations panel a second catalog to show.
///
/// This file is one project's answer, not an API. Decision 6 says flutterware
/// hands a frame `shot.slug` and `shot.locale` and has no opinion about where
/// the words live; this is what taking it up looks like.
///
/// **Read off disk, synchronously.** A frame's `build` cannot await, and a
/// composition that resolved its words a frame late would be captured before
/// they arrived. `rootBundle` is the usual answer and it is asynchronous, so
/// it is the wrong one here — the frame harness is a `flutter_tester` running
/// in the package root, and the catalog is a file. Read once, on the first
/// headline asked for, and the same JSON the Translations panel reads is the
/// only copy of these words that exists.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

/// The headline for a shot, or null where the listing has nothing to say about
/// that screen.
///
/// A set is usually longer than the copy written for it — the demo suite has
/// fifteen shots and five headlines — and a frame that drew an empty band for
/// the rest would look worse than one that drew none.
String? storeHeadline(String slug, Locale locale) =>
    _catalog(locale.languageCode)[slug] ?? _catalog('en')[slug];

Map<String, String> _catalog(String locale) => _loaded.putIfAbsent(locale, () {
  var file = _find('assets/store/$locale.json');
  if (file == null) return const {};
  return {
    for (var entry in (jsonDecode(file.readAsStringSync()) as Map).entries)
      '${entry.key}': '${entry.value}',
  };
});

/// The catalog, from wherever the harness happens to have been started.
///
/// The frame harness runs in this package's root, so the plain relative path
/// is the answer there. A `previews` harness rendering the same frame may not
/// — and a headline silently missing from a preview is exactly the thing the
/// preview exists to check. Walking up a few levels costs three `stat`s and
/// removes the difference.
File? _find(String path) {
  var directory = Directory.current;
  for (var up = 0; up < 4; up++) {
    for (var candidate in [
      File('${directory.path}/$path'),
      File('${directory.path}/examples/example/$path'),
    ]) {
      if (candidate.existsSync()) return candidate;
    }
    directory = directory.parent;
  }
  return null;
}

final _loaded = <String, Map<String, String>>{};
