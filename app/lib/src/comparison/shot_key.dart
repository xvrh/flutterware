import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The name a rendered picture is filed under: everything that decides its
/// pixels, hashed.
///
/// Two renders with the same key are the same picture, so a key that is
/// already in the cache is a render that does not have to happen. That is what
/// makes the base side free after the first comparison against a commit, and
/// what makes five worktrees branched off one base share one set of pictures.
///
/// The rule for what belongs in here is blunt: **if it can change a pixel, it
/// is in the key.** A forgotten input is a cache that serves a wrong picture,
/// and a wrong picture in a comparison is worse than no comparison — it is a
/// regression reported as clean.
class ShotKey {
  /// What the *tooling* renders like, as opposed to what the code says.
  ///
  /// **Bump this whenever a change to the renderer changes a pixel** — the
  /// generated entrypoint, the capture settings, the guest's own setup. None of
  /// those are in the closure of the entry being rendered, so without it a
  /// picture taken by last week's generator is served against one taken by
  /// today's, and the comparison reports a difference in the tooling as a
  /// difference in the branch. Measured: a warm cache answered *2 changed*
  /// where a cold one answered *3*, twice.
  ///
  /// v2 — the generated entrypoint pins the clock through `package:clock`
  /// rather than through flutterware's own wrapper.
  /// v3 — a capture waits for animations to stop, not only for images.
  static const revision = 'v3';

  /// [closure] is a [SourceClosure.fingerprint]; [sdk] identifies the engine
  /// (see `SdkIdentity`); [axes] and [knobs] are whatever was applied.
  ///
  /// [extra] is for the inputs one caller has and another does not — a
  /// scenario's device and language, a preview's viewport — rather than a
  /// parameter per surface. Names are the caller's; ordering is not, because
  /// this sorts.
  static String of({
    required String kind,
    required String entryId,
    required String closure,
    required String sdk,
    Map<String, String> axes = const {},
    Map<String, String> knobs = const {},
    Map<String, String> extra = const {},
  }) {
    var buffer = StringBuffer()
      ..writeln(revision)
      ..writeln(kind)
      ..writeln(entryId)
      ..writeln(closure)
      ..writeln(sdk);
    _writeSorted(buffer, 'axes', axes);
    _writeSorted(buffer, 'knobs', knobs);
    _writeSorted(buffer, 'extra', extra);
    return sha1.convert(utf8.encode(buffer.toString())).toString();
  }

  /// Sorted, because a map's iteration order is its insertion order — so two
  /// callers applying the same two axes in the other order would otherwise
  /// render twice and cache twice.
  ///
  /// The name is written even when the section is empty, so "no knobs" and "a
  /// knob named nothing" cannot collide.
  static void _writeSorted(
    StringBuffer buffer,
    String section,
    Map<String, String> values,
  ) {
    buffer.writeln('[$section]');
    var keys = values.keys.toList()..sort();
    for (var key in keys) {
      buffer.writeln('$key=${values[key]}');
    }
  }
}
