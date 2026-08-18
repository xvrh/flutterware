import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The `--flavor` a package builds with when nobody says otherwise, from its
/// pubspec's `flutter: default-flavor:`.
///
/// This is Flutter's own field, not ours — `FlutterManifest.defaultFlavor`,
/// applied by every flavour-taking command as `flavor = cliFlavor ??
/// defaultFlavor`. So a project that set it is a project where `flutter run`
/// with no `--flavor` already works, and a cockpit that offered an empty field
/// there was asking for something the project had written down two files away.
///
/// Read rather than inferred, and only this one key: the *list* of flavors a
/// project has lives in Gradle and in Xcode schemes, which is a different job
/// with two parsers in it. This is the one that costs a `loadYaml`.
String? defaultFlavorOf(String packageRoot) {
  try {
    var file = File(p.join(packageRoot, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    var yaml = loadYaml(file.readAsStringSync());
    if (yaml is! Map) return null;
    var flutter = yaml['flutter'];
    if (flutter is! Map) return null;
    var flavor = flutter['default-flavor'];
    return flavor is String && flavor.isNotEmpty ? flavor : null;
  } on Object {
    // A pubspec that will not parse is a problem the dependencies plugin
    // reports properly. Here it means one less field filled in.
    return null;
  }
}

/// Where the `--flavor` about to be built came from.
///
/// Carried rather than reduced to a string because the New run page shows the
/// flavor as a line of text instead of a field to fill, and a value with no
/// provenance is one nobody can tell from a guess.
enum FlavorSource {
  /// `Entrypoint(flavor: 'dev')` — the pairing that motivated the field.
  entrypoint,

  /// The package's `flutter: default-flavor:`.
  pubspec,

  /// Nothing declared one, and none will be passed.
  none,
}

/// The flavor to build [entrypointFlavor]'s entry point with, and why.
///
/// Deliberately not given the caller's per-launch override: an override is the
/// answer to a different question — what *this* run does — and folding it in
/// here would make the panel unable to say what the project declares once the
/// user had typed over it.
///
/// [byPlatform] is the entry point's per-platform pairing and wins where it
/// names the platform launched onto, described by [platformType] and
/// [category] — the two strings `flutter daemon` reports about a device, both
/// optional there, which is why this takes them rather than an enum a caller
/// would have to derive. A device that says nothing about itself resolves as
/// if the map were empty: falling back to the plain declaration is the safe
/// direction, and the platforms it could mis-serve are the desktop ones,
/// which always name themselves.
({String? flavor, FlavorSource source}) resolveFlavor({
  required String? entrypointFlavor,
  required String? packageDefault,
  Map<RunPlatform, String> byPlatform = const {},
  String? platformType,
  String? category,
}) {
  var paired = lookupByPlatform(
    byPlatform,
    platformType: platformType,
    category: category,
  );
  if (paired != null && paired.isNotEmpty) {
    return (flavor: paired, source: FlavorSource.entrypoint);
  }
  if (entrypointFlavor != null && entrypointFlavor.isNotEmpty) {
    return (flavor: entrypointFlavor, source: FlavorSource.entrypoint);
  }
  if (packageDefault != null && packageDefault.isNotEmpty) {
    return (flavor: packageDefault, source: FlavorSource.pubspec);
  }
  return (flavor: null, source: FlavorSource.none);
}

/// [map]'s entry for the platform a device describes, or null for a platform
/// it does not name.
///
/// A concrete key beats a shorthand — `ios:` wins over `mobile:` for an
/// iPhone — and the two shorthands cannot overlap each other, so this is the
/// whole precedence. A device reporting no `platformType` can still match a
/// shorthand key through its daemon `category`, which groups devices the same
/// way the shorthands do.
T? lookupByPlatform<T>(
  Map<RunPlatform, T> map, {
  String? platformType,
  String? category,
}) {
  if (map.isEmpty) return null;
  var platform = RunPlatform.byName(platformType ?? '');
  if (platform != null) {
    if (map[platform] case var direct?) return direct;
    for (var entry in map.entries) {
      if (entry.key.expanded.contains(platform) && entry.key != platform) {
        return entry.value;
      }
    }
    return null;
  }
  var shorthand = RunPlatform.byName(category ?? '');
  return shorthand != null ? map[shorthand] : null;
}
