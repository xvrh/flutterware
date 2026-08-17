import 'package:path/path.dart' as p;

/// Where the generated guest wrapper sits, relative to the package root.
///
/// Inside the package so its imports resolve, outside `lib/` so no analyzer or
/// tool of the project's ever meets it. Named here because two files have to
/// agree about it: the generator writing the wrapper and the scan rewriting the
/// entry point's own imports into it.
const wrapperDirectory = '.dart_tool/flutterware/run';

/// How the wrapper must spell an import of [target] — package-relative,
/// `/`-separated — or null when there is no spelling it can honestly write.
///
/// **A `lib/` file is named by its `package:` URI, and only that.** The wrapper
/// could reach it by path just as well, and must not: the app's own code names
/// it `package:$package/...`, and a library reached under two URIs is two
/// libraries, so a type crossing between them stops being the same type. Null
/// when [package] is unknown, because then there is no `package:` spelling to
/// write and the path is not allowed to stand in for it.
///
/// **Anything else inside the package is named by a path, and only that.** A
/// file outside `lib/` has no `package:` URI at all, so nothing else can name
/// it either and the double-identity hazard cannot arise. This is what lets an
/// entry point live in `demo/` — the constraint was always about `lib/` being
/// the half of a package that has two spellings, never about the wrapper
/// needing a `package:` URI specifically.
///
/// **Anything outside the package is dropped.** A path would spell it, but a
/// file in a sibling package is reached by `package:` URI from everywhere else
/// in the checkout, which is the hazard above with the packages swapped. An
/// absolute path is outside by the same test, which is why there is no separate
/// check for one.
String? wrapperImportOf(String target, {String? package}) {
  if (!p.posix.isWithin('.', target)) return null;
  if (p.posix.isWithin('lib', target)) {
    if (package == null) return null;
    return 'package:$package/${p.posix.relative(target, from: 'lib')}';
  }
  return p.posix.relative(target, from: wrapperDirectory);
}
