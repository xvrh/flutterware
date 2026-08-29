import 'dart:io';

/// Where an exported page tells the browser it is mounted.
///
/// The default is **relative**: `./` resolves against the page's own URL, so
/// one compiled bundle serves a bucket root and
/// `…/comparisons/42/web/index.html` alike. The `/` that `flutter build web`
/// compiles in only ever resolved at a domain root — a page hosted under a
/// prefix with it asks for `main.dart.js`, the service worker and everything
/// under `assets/` and `canvaskit/` from the root, gets nothing, and renders
/// blank with nothing in the console saying why. That is the shape of every
/// per-pull-request CI artifact, so the hosted case is the common one and it
/// is the one that has to work unasked.
///
/// Only the bundle's own files go through this tag. A viewer's data —
/// `index.json`, `report.json`, every frame — is fetched against `Uri.base`,
/// which is the document URL and was always right; the page was blank purely
/// because its script 404'd. `./` is the same rule the data already followed,
/// which is why the two halves now agree about where the page lives.
///
/// `flutter build web --base-href` refuses a relative value, but the
/// exporters do not go through it: both rewrite the tag on a copy of a bundle
/// compiled once, so the only rule to hold here is the browser's.
///
/// The one place `./` is wrong is a page reached without its filename *and*
/// without a trailing slash — `…/web` rather than `…/web/` — where it
/// resolves a level up. A host serving a directory index redirects to add the
/// slash; one that does not wants an absolute mount stated.
const defaultBaseHref = './';

/// Why [value] cannot be a mount point, or null when it can.
String? baseHrefProblem(String value) {
  if (value == defaultBaseHref) return null;
  if (!value.startsWith('/') || !value.endsWith('/')) {
    return 'must be `./` for a page that resolves against its own URL, or '
        'an absolute mount that begins and ends with a slash, like '
        '`/pages/42/`';
  }
  return null;
}

/// The absolute mount a page was built for, or null when it carries none.
///
/// [defaultBaseHref] resolves against wherever the page is served from, so a
/// local server has nothing to mount it under and puts it at the root.
String? absoluteMount(String baseHref) =>
    baseHref.isEmpty || baseHref == defaultBaseHref ? null : baseHref;

/// Points a built page at where it will actually be mounted.
///
/// `flutter build web --base-href` only ever edits this one attribute, so
/// doing it after the build instead is what lets one compiled bundle serve
/// every mount point — and what lets the default be the relative `./` that
/// flag refuses.
void setBaseHrefIn(String indexHtml, String baseHref) {
  var file = File(indexHtml);
  if (!file.existsSync()) return;
  file.writeAsStringSync(
    file.readAsStringSync().replaceAll(
      RegExp(r'<base href="[^"]*">'),
      '<base href="$baseHref">',
    ),
  );
}
