import 'dart:async';

import 'package:flutter/foundation.dart';

import '../shell/worktree.dart';
import 'facts.dart';
import 'facts_probe.dart';
import 'facts_store.dart';

/// Holds the explorer's facts for the window, and decides when to re-probe.
///
/// **The one Flutter-aware file in this directory.** Everything under it —
/// the model, the probe, the providers, the store, the text projection — is
/// pure Dart, because `fw worktrees` links those and must not drag in Flutter.
/// This is the GUI's wrapper around them, the same split as `PluginCore` and
/// `NativePlugin`.
///
/// **No polling timer.** Refreshing happens when the explorer becomes visible
/// and when the button is pressed. Filesystem watchers are the third trigger
/// and are not here yet; when they land they call [refresh] like everything
/// else, so nothing above this changes.
class WorktreeFactsController extends ChangeNotifier {
  WorktreeFactsController({required this.repoRoot, WorktreeFactsProbe? probe})
    : _probe =
          probe ??
          WorktreeFactsProbe(
            repoRoot: repoRoot,
            store: WorktreeFactsStore.open(repoRoot),
          );

  /// The main checkout. Branch diffs are repository-wide, so the cache under it
  /// is shared by every worktree rather than copied per checkout.
  final String repoRoot;

  final WorktreeFactsProbe _probe;

  Map<String, WorktreeFacts> get facts => _facts;
  var _facts = const <String, WorktreeFacts>{};

  WorktreeFacts factsFor(Worktree worktree) =>
      _facts[worktree.path] ?? const WorktreeFacts();

  bool get isRefreshing => _refreshing;
  var _refreshing = false;

  DateTime? get refreshedAt => _refreshedAt;
  DateTime? _refreshedAt;

  /// How many worktrees will not progress until you do something.
  ///
  /// What the pinned tab's badge counts — and the reason the explorer is a tab
  /// rather than a menu item, since only a tab can carry it.
  int get needsYou => _facts.values.where((f) => f.needsYou).length;

  /// Re-probes every worktree.
  ///
  /// **Coalesced, not queued.** A second call while one is in flight returns the
  /// same future rather than starting a second sweep: the triggers are a screen
  /// appearing and a button, and both can fire twice in a frame.
  ///
  /// [force] is what the button means and arriving does not: it re-asks the
  /// forge instead of believing the last answer for five minutes. Git is
  /// re-read either way — it is cheap and local, and a refresh that skipped it
  /// would be lying about what it did.
  Future<void> refresh(List<Worktree> worktrees, {bool force = false}) {
    return _inFlight ??= _refresh(worktrees, force: force).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void>? _inFlight;

  Future<void> _refresh(List<Worktree> worktrees, {required bool force}) async {
    _refreshing = true;
    _notify();
    try {
      _facts = await _probe.probe(worktrees, refreshForge: force);
      _refreshedAt = DateTime.now();
    } catch (e) {
      // A probe that throws must not take the window down. Individual facts
      // already carry their own failures; this is the backstop for the sweep
      // itself.
      debugPrint('worktree facts refresh failed: $e');
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  /// Notifies on a microtask rather than now.
  ///
  /// **Because a refresh starts from `initState`.** Becoming visible is one of
  /// the refresh triggers, and the moment a screen knows it became visible is
  /// inside the build phase — where marking the shell dirty synchronously
  /// throws `setState() called during build`. Same reason and same fix as
  /// `PluginCore.notifyChanged`.
  void _notify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  var _notifyScheduled = false;

  /// Records that you opened [worktree] — the one activity clock nothing else
  /// knows about, and the reason a checkout you visited but did not commit in
  /// still sorts where you left it.
  void markOpened(Worktree worktree) {
    _probe.store.markOpened(worktree.path, DateTime.now());
    _probe.store.save();
  }

  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
