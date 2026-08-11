import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'closure.dart';

/// The pixel inputs no compile ever names, for the package at [packagePath].
///
/// The Dart closure knows every import; it knows nothing about the bytes of
/// an asset, the resolution in a lockfile or an `.arb` bundle, and all three
/// decide pixels. Until these were passed, a worktree that changed only an
/// asset computed the same shot key as its base and the comparison served the
/// base's picture back as "same" — a regression reported as clean, which is
/// the outcome the cache's own doc calls worse than no comparison.
///
/// Returned as root-relative paths whose *content* is hashed per side; a path
/// absent on one side hashes as [SourceClosure.missing], so a deleted asset
/// reads as a change the same way an edited one does. Directory assets and
/// bundle directories are listed in **every** root and unioned, because a
/// file only one side has is by definition missing from the other side's
/// listing — a single-side listing would let an added or deleted file slip
/// through unhashed.
///
/// `package_config.json` is deliberately *not* here even though resolution
/// lives in it: pub stamps it with a generation time, so its bytes differ
/// between two checkouts whose resolution is identical, and hashing it would
/// turn every skip into a render. The lockfiles carry the same information
/// with stable bytes.
List<String> pixelInputsOf({
  required String packagePath,
  required List<String> roots,
}) {
  var paths = <String>{
    p.join(packagePath, 'pubspec.yaml'),
    p.join(packagePath, 'pubspec.lock'),
    p.join(packagePath, 'l10n.yaml'),
    // A workspace member resolves at the workspace root, so the lock that
    // records its resolution can be at the top rather than beside it.
    'pubspec.lock',
  };
  for (var root in roots) {
    paths.addAll(_declaredAssets(root, packagePath));
    paths.addAll(_l10nBundles(root, packagePath));
  }
  return paths.toList()..sort();
}

Iterable<String> _declaredAssets(String root, String packagePath) sync* {
  var flutter = _yamlMap(p.join(root, packagePath, 'pubspec.yaml'))?['flutter'];
  if (flutter is! Map) return;
  if (flutter['assets'] case List assets) {
    for (var entry in assets) {
      // An entry is a path, or since flavors a map carrying one.
      var asset = entry is Map ? entry['path'] : entry;
      if (asset is! String) continue;
      if (!asset.endsWith('/')) {
        yield p.join(packagePath, asset);
        continue;
      }
      // A directory asset bundles its direct files.
      yield* _filesIn(root, p.join(packagePath, asset), (_) => true);
    }
  }
  if (flutter['fonts'] case List families) {
    for (var family in families) {
      if (family is! Map) continue;
      if (family['fonts'] case List fonts) {
        for (var font in fonts) {
          if (font is Map && font['asset'] is String) {
            yield p.join(packagePath, font['asset'] as String);
          }
        }
      }
    }
  }
}

Iterable<String> _l10nBundles(String root, String packagePath) sync* {
  var arbDir = _yamlMap(p.join(root, packagePath, 'l10n.yaml'))?['arb-dir'];
  if (arbDir is! String) return;
  yield* _filesIn(
    root,
    p.join(packagePath, arbDir),
    (name) => name.endsWith('.arb'),
  );
}

/// The root-relative paths of [relativeDir]'s direct files, or nothing when
/// the directory is not there in this root.
Iterable<String> _filesIn(
  String root,
  String relativeDir,
  bool Function(String name) wanted,
) sync* {
  List<FileSystemEntity> entries;
  try {
    entries = Directory(p.join(root, relativeDir)).listSync();
  } on FileSystemException {
    return;
  }
  for (var entity in entries) {
    var name = p.basename(entity.path);
    if (entity is File && wanted(name)) {
      yield p.join(relativeDir, name);
    }
  }
}

Map<Object?, Object?>? _yamlMap(String path) {
  try {
    var doc = loadYaml(File(path).readAsStringSync());
    return doc is Map ? doc : null;
  } on Object {
    // Absent, unreadable, or not yaml — nothing to declare assets from.
    return null;
  }
}

/// Whether an entry has to be rendered at all.
///
/// The skip rule, and the reason a comparison of a 213-entry catalog takes
/// seconds: if nothing an entry reads differs between the two checkouts, the
/// entry cannot have changed, so neither side is rendered and the row is
/// reported `same`.
///
/// Its second-order effect is the one that shows: deciding this is *only*
/// hashing, so the verdict for every entry lands before the first render
/// starts. The screen knows its full shape immediately and the pictures fill
/// in behind it.
class SkipDecision {
  const SkipDecision({
    required this.skip,
    required this.changed,
    required this.reason,
  });

  final bool skip;

  /// The paths that differ, when any do — what the report shows under "why
  /// this entry was rendered".
  final List<String> changed;

  /// Why it could not be skipped, or null when it was.
  final String? reason;

  /// Decides for one entry, given the paths it was last compiled from.
  ///
  /// [extraPaths] are the inputs the compiler's own list does not name and
  /// that still decide pixels: `pubspec.lock`, the asset manifest and every
  /// asset it points at, the l10n bundles. **The bias is deliberate.** A path
  /// wrongly included costs one render; a path wrongly left out reports a
  /// regression as clean, and nothing downstream can detect it. When in
  /// doubt, include.
  static SkipDecision of({
    required String entryId,
    required ClosureMemo memo,
    required String baseRoot,
    required String headRoot,
    Iterable<String> extraPaths = const [],
  }) {
    var remembered = memo.recall(entryId);
    if (remembered == null) {
      // Nothing has compiled this entry here, so nothing knows what it reads.
      // The first comparison against a base pays full price and teaches the
      // memo; every later one is cheap.
      return const SkipDecision(
        skip: false,
        changed: [],
        reason:
            'nothing has compiled this entry yet, so what it reads is '
            'unknown',
      );
    }
    var paths = [...remembered, ...extraPaths];
    var base = SourceClosure.of(paths, root: baseRoot);
    var head = SourceClosure.of(paths, root: headRoot);
    if (base.fingerprint == head.fingerprint) {
      return const SkipDecision(skip: true, changed: [], reason: null);
    }
    var changed = head.changedAgainst(base);
    return SkipDecision(
      skip: false,
      changed: changed,
      reason: switch (changed.length) {
        1 => '${changed.single} differs',
        var n => '$n files differ, including ${changed.first}',
      },
    );
  }
}
