import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/flutter_sdk.dart';

/// Whether two checkouts would render with the same engine.
///
/// A comparison exists to say *you changed this*. Two checkouts pinned to
/// different Flutter versions change every pixel of every picture between them
/// — text metrics, shadow falloff, the shape of a rounded rect — for reasons
/// belonging to the SDK rather than the branch. There is no threshold that
/// separates that from a real change, so a comparison across a mismatch is
/// refused rather than annotated.
///
/// `fw` now manages an SDK cache of its own, so a future comparison could
/// install the base's pin instead of refusing; until then the gap is real,
/// and a loud one is better than a quiet one.
class SdkMatch {
  const SdkMatch({required this.base, required this.head, required this.same});

  /// What each side resolved to, or null where nothing did.
  final SdkIdentity? base;
  final SdkIdentity? head;

  /// True when both sides would render with the same engine.
  ///
  /// **An unresolved side is not a match.** A checkout whose SDK cannot be
  /// found is one whose engine is unknown, and "unknown equals unknown" is the
  /// answer that lets a wrong comparison through.
  final bool same;

  /// Why the two differ, in a sentence naming both — or null when they do not.
  String? get reason {
    if (same) return null;
    if (base == null || head == null) {
      var missing = base == null ? 'base' : 'head';
      return 'no Flutter SDK found for the $missing checkout, so there is '
          'nothing to compare its pictures against.';
    }
    return 'the two checkouts pin different Flutter SDKs — base is '
        '${base!.describe}, head is ${head!.describe}. Every picture would '
        'differ for reasons that are not yours.';
  }

  /// Resolves both checkouts' SDKs and compares them.
  ///
  /// Cheap in the case that matters: two worktrees of one repo usually resolve
  /// to the *same SDK root*, and identical roots are the same engine without
  /// reading a file.
  static Future<SdkMatch> of({
    required String baseRoot,
    required String headRoot,
  }) async {
    var base = await SdkIdentity.of(baseRoot);
    var head = await SdkIdentity.of(headRoot);
    return SdkMatch(
      base: base,
      head: head,
      same: base != null && head != null && base.rendersAs(head),
    );
  }
}

/// One checkout's Flutter SDK, identified by what determines its pixels.
class SdkIdentity {
  const SdkIdentity({
    required this.root,
    this.pinned,
    this.version,
    this.frameworkRevision,
    this.engineHash,
  });

  /// The version the checkout pins — `flutter_version` (the `fw` wrapper's
  /// pin) or, failing that, `.fvmrc` — when the checkout carries one.
  ///
  /// **Versioned, unlike everything else here.** `.fvm/flutter_sdk` is a
  /// symlink some tool created and `.gitignore` hides; the pin is a file the
  /// commit itself carries. So it is the checkout's own claim about which SDK
  /// it needs, and it outranks a link that a comparison may well have made
  /// itself — which is exactly what a base checkout's link is.
  final String? pinned;

  /// The resolved SDK directory.
  final String root;

  /// `3.47.0-0.1.pre`, when the SDK wrote one down.
  final String? version;

  final String? frameworkRevision;

  /// The engine's content hash — **the field that decides pixels**. Two
  /// framework revisions sharing an engine rasterize identically; two engines
  /// do not, whatever the framework says.
  final String? engineHash;

  String get describe => pinned ?? version ?? root;

  /// Whether [other] would put the same pixels on screen.
  ///
  /// The same directory is the same SDK, and that is the ordinary case: two
  /// worktrees of one repo pinned by one `.fvmrc` resolve to one cached SDK.
  /// Different directories are compared by what they wrote in
  /// `bin/cache/flutter.version.json` — two checkouts of the same version in
  /// two places are the same engine.
  ///
  /// Unreadable metadata on either side means **no**: a version file is
  /// written by the SDK itself, so its absence says the tool is looking at
  /// something it does not understand.
  bool rendersAs(SdkIdentity other) {
    // Before the root, because a base checkout is handed a link to the head's
    // SDK so that it can build at all. If the two commits pin different
    // versions, that link is the tool papering over the mismatch it exists to
    // report.
    if (pinned != null && other.pinned != null && pinned != other.pinned) {
      return false;
    }
    if (root == other.root) return true;
    if (engineHash != null && other.engineHash != null) {
      return engineHash == other.engineHash &&
          frameworkRevision == other.frameworkRevision;
    }
    return false;
  }

  /// The SDK [checkout] pins, or null when nothing on the machine can answer.
  ///
  /// **Asked with an empty environment, deliberately.** `findSdks` answers
  /// best-first from five sources, and three of them describe the *machine*
  /// rather than the checkout: the launcher's own dart, the SDK running this
  /// process, and `FLUTTER_HOME`. Consulting those would resolve both sides to
  /// whichever SDK happens to be running the comparison — and then two
  /// checkouts pinning different versions would report a match, which is the
  /// exact failure this class exists to catch.
  ///
  /// What is left is checkout-scoped and ordered: `.flutterware/sdk`, then
  /// `.fvm/flutter_sdk`, both walked up from [checkout]. The running
  /// executable stays as the last resort, and it is a safe one: it answers for
  /// a side that pins nothing, so two unpinned checkouts agree — which is
  /// true, since both really would build with it.
  static Future<SdkIdentity?> of(String checkout) async {
    var sdks = await FlutterSdkPath.findSdks(
      from: Directory(checkout),
      environment: const {},
    );
    var sdk = sdks.firstOrNull;
    if (sdk == null) return null;
    var meta = await _metadata(sdk.root);
    return SdkIdentity(
      root: sdk.root,
      pinned: _pinned(checkout),
      version: meta?.version,
      frameworkRevision: meta?.framework,
      engineHash: meta?.engine,
    );
  }

  /// The version the checkout's own commit pins, or null where nothing does.
  ///
  /// `flutter_version` first: a repo carrying both pins is one the `fw`
  /// wrapper runs, and the wrapper reads only its own.
  static String? _pinned(String checkout) {
    var fw = File(p.join(checkout, 'flutter_version'));
    if (fw.existsSync()) {
      try {
        var version = fw.readAsStringSync().trim();
        if (version.isNotEmpty) return version;
      } on FileSystemException {
        // Unreadable names nothing; .fvmrc below may still answer.
      }
    }
    var file = File(p.join(checkout, '.fvmrc'));
    if (!file.existsSync()) return null;
    try {
      var json = jsonDecode(file.readAsStringSync());
      return json is Map ? json['flutter'] as String? : null;
    } on FormatException {
      return null;
    }
  }

  static Future<({String? version, String? framework, String? engine})?>
  _metadata(String root) async {
    var file = File(p.join(root, 'bin', 'cache', 'flutter.version.json'));
    if (!file.existsSync()) return null;
    try {
      var json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) return null;
      return (
        version: json['frameworkVersion'] as String?,
        framework: json['frameworkRevision'] as String?,
        engine: json['engineContentHash'] as String?,
      );
    } on FormatException {
      // A half-written or hand-edited version file. Unknown, which
      // [rendersAs] already treats as "not the same".
      return null;
    }
  }

  @override
  String toString() => 'SdkIdentity($describe)';
}
