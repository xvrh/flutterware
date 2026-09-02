/// What a core needs to paint a tree from the branch delta, written once.
///
/// The previews and scenarios cores each hold scans per package and each
/// answer "how did the branch touch this entry" from them. What differs is
/// only what a scan is and how its entries become spans; everything else —
/// the listener on the controller, re-registering on install, the memo — is
/// this.
library;

import 'branch_delta.dart';
import 'branch_delta_controller.dart';

class DeltaPainting<Scan> {
  DeltaPainting({
    required this.owner,
    required this.filesOf,
    required this.spansOf,
    required this.onChanged,
  });

  /// The plugin id — what the controller keys this core's files by.
  final String owner;

  /// The worktree-relative files [scan] declares entries in.
  final Set<String> Function(String package, Scan scan) filesOf;

  /// [scan]'s entries as the classifier sees them.
  final List<EntrySpan> Function(String package, Scan scan) spansOf;

  /// The core's own notification, forwarded when the delta moves.
  final void Function() onChanged;

  final _scans = <String, Scan>{};
  final _cache = EntryChangesCache();

  /// The worktree's delta, installed by the session. Null for a core built
  /// without one, which paints nothing and answers no `change`.
  BranchDeltaController? get controller => _controller;
  BranchDeltaController? _controller;
  set controller(BranchDeltaController? value) {
    _controller?.removeListener(onChanged);
    _controller = value;
    value?.addListener(onChanged);
    for (var MapEntry(key: package, value: scan) in _scans.entries) {
      value?.track('$owner:$package', filesOf(package, scan));
    }
  }

  /// A scan of [package] landed: register its files, which looks again.
  void scanLanded(String package, Scan scan) {
    _scans[package] = scan;
    _controller?.track('$owner:$package', filesOf(package, scan));
  }

  /// How the branch touched each entry of [package], or null before the
  /// delta has landed — the tree is untinted until then, never blocked.
  EntryChanges? changesFor(String package) {
    var scan = _scans[package];
    return _cache.of(
      package,
      _controller?.value,
      scan,
      () => spansOf(package, scan as Scan),
    );
  }

  /// [changesFor] as a listing's header carries it, or null when there is
  /// nothing to say.
  BranchChangeSummary? summaryFor(String package) {
    var changes = changesFor(package);
    if (changes == null || changes.isEmpty && changes.suppressedReach == 0) {
      return null;
    }
    return BranchChangeSummary.of(changes);
  }

  void dispose() => controller = null;
}
