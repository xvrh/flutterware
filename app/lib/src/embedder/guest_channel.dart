/// How a host talks to a catalog guest: the service extensions it calls and
/// the events it listens to.
///
/// Two implementations. [GuestVmService] is the VM service of an embedder
/// process — the only channel a plain guest has. The in-process one calls the
/// same handlers directly, for a guest drawn inside the host as a widget: the
/// studio's web demo, and a widget test of the panel over a real entry. The
/// session and the inspect client read through this and never know which.
abstract interface class GuestChannel {
  /// Calls [method], or answers null when the guest does not declare it.
  Future<Map<String, dynamic>?> callExtension(
    String method, {
    Map<String, String> args,
  });

  /// [callExtension], but waits for a guest that is still registering.
  Future<Map<String, dynamic>?> requireExtension(
    String method, {
    Map<String, String> args,
  });

  /// Every event the guest posts under [kind].
  Stream<Map<String, Object?>> extensionEvents(String kind);

  /// What the guest prints through `dart:developer`'s log.
  Stream<String> developerLog();

  /// Hot-reloads the guest from a compiled dill. A guest that is compiled
  /// into the host has nothing to reload and answers at once.
  Future<void> reload(String dillPath);

  /// Whether the guest has gone away.
  bool get isGone;

  Future<void> close();
}
