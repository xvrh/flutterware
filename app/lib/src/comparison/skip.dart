import 'closure.dart';

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
