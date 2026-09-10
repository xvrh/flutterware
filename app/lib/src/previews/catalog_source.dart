import 'protocol.dart';

/// Where a session's catalog comes from: the entries, a compiled selection,
/// and what changed since.
///
/// Two implementations. [CompilerDaemonClient] is the real one — a resident
/// compiler that watches the project, compiles the entry asked for and hot
/// reloads the guest onto it. The inline one holds a table of entries that
/// are compiled into the host already, so a selection is a switch and never
/// a compile. The session reads through this and never knows which; a
/// [DaemonConnector] answers one of these beside the handshake.
abstract interface class CatalogSource {
  /// The last change announced, for a client that connected after it.
  CatalogChanged? get lastChange;

  Stream<CatalogChanged> get catalogChanges;
  Stream<AssetsChanged> get assetsChanges;

  /// Compiles [id] — the whole program when [full], only if something moved
  /// when [ifChanged] — and answers what to reload the guest with.
  Future<DaemonCompiled> select(
    String id, {
    bool full = false,
    bool ifChanged = false,
    Duration timeout = const Duration(minutes: 5),
  });

  /// Where the embedder host binary is, building it first if it must.
  Future<String> hostPath({Duration timeout = const Duration(minutes: 5)});

  /// Tells the source the guest is showing [id] without a compile.
  void shown(String id);

  /// Reads the project again. Fire and forget.
  void refresh();

  Future<void> close();
}
