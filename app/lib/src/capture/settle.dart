/// Something the window is doing that a capture must not photograph through.
///
/// **Busy is what gets declared, not ready.** The inverse — every panel
/// announcing when it is finished — makes a plugin that never announces hang
/// the capture forever, and a plugin author who forgets is the common case. A
/// plugin that never registers here is treated as settled, so forgetting costs
/// a picture taken slightly early rather than a script that never returns.
abstract interface class SettleSource {
  /// A word for what is in flight, or null when nothing is.
  ///
  /// Deliberately the same shape as `CatalogSession.busyWith`, which is where
  /// the idea came from and is still the only thing slow enough to need it.
  String? get busyWith;
}

/// What the window was waiting on when the wait gave up.
typedef SettleOutcome = ({bool settled, List<String> waitingOn});

/// Who the window is waiting on, aggregated across every mounted panel.
///
/// Lives on `AppContext` rather than on a plugin: a capture is of the window,
/// so the question "is this worth photographing yet" spans whatever happens to
/// be mounted.
///
/// **Pure Dart, and it has to stay that way.** `AppContext` is on `bin/fw.dart`
/// and `bin/mcp.dart`'s import closure, so a `package:flutter` import here
/// makes the CLI unlinkable — which `entry_point_purity_test.dart` reported
/// within seconds of this file first importing `scheduler.dart`. The waiting,
/// which needs frames and therefore needs Flutter, is `waitForSettle` in
/// `settle_wait.dart`.
class SettleRegistry {
  final _sources = <SettleSource>{};

  void add(SettleSource source) => _sources.add(source);

  void remove(SettleSource source) => _sources.remove(source);

  /// What is in flight right now.
  List<String> get waitingOn => [for (var source in _sources) ?source.busyWith];

  bool get isIdle => waitingOn.isEmpty;
}
