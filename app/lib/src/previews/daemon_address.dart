import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../utils/run_dir.dart';

import 'protocol.dart';

/// Where the daemon serving a given [DaemonConfig] listens.
///
/// The address is *derived*, not assigned, so every consumer that wants the
/// same catalog — the GUI, `fw`, an agent, a test — arrives at the same socket
/// without being told about each other. Two configs that would produce
/// different entries, different generated code or different kernels hash
/// differently and get their own daemon.
class DaemonAddress {
  DaemonAddress(this.config);

  final DaemonConfig config;

  /// Everything that changes what the daemon would produce.
  ///
  /// Deliberately the whole config: adding a field to [DaemonConfig] without
  /// thinking about sharing should split the daemon, not silently hand a client
  /// someone else's compiler.
  ///
  /// That rule is right for one service and inverts for several. It works
  /// here because the process *is* the compiler, so "would produce a different
  /// kernel" and "should be a different process" are the same question. The day
  /// this process hosts a second service — a test runner, a resident analyzer —
  /// they stop being: `trackWidgetCreation` and `emitProbe` are knobs only the
  /// compiler cares about, and forking on them would duplicate a service that
  /// never heard of them.
  ///
  /// So a second service must **not** inherit this address. Identity splits in
  /// two at that point: a coarse process address, and a per-service config
  /// negotiated after connect, with this hash surviving unchanged as the key
  /// that picks one compiler out of several inside the one process.
  ///
  /// Deferred deliberately rather than built ahead of a use case — the
  /// granularity is undecided until something concrete moves in. The catalog is
  /// per *package*; `Session` and `fw` are per *worktree*; a shared daemon has
  /// to pick one, and which depends on whether the newcomer needs the compiler
  /// at all.
  late final String key = sha1
      .convert(utf8.encode(jsonEncode(_canonical(config.toJson()))))
      .toString()
      .substring(0, 16);

  /// A short, stable directory — see [flutterwareRunDir] for why it cannot live
  /// under the project's build directory.
  static String get runDir => flutterwareRunDir();

  String get socketPath => checkSocketPath(p.join(runDir, '$key.sock'));

  /// Held while deciding whether to spawn, so two clients starting at once
  /// produce one daemon rather than two.
  String get lockPath => p.join(runDir, '$key.lock');

  /// Where a daemon that dies before it can speak leaves its reason.
  String get logPath => p.join(runDir, '$key.log');

  /// Where a daemon that fails **while preparing** leaves the failure, for a
  /// client that has not managed to connect yet.
  ///
  /// The socket is not that channel and cannot be. The daemon binds, prepares,
  /// and on failure sends `DaemonFailed` to every connected session — but a
  /// preparation that fails quickly fails before anybody has connected, so the
  /// message reaches nobody and the socket is unlinked on the way out. The
  /// client is then polling a path that will never exist again, and does so
  /// until its deadline: **measured at 31.6 seconds for a catalog directory
  /// holding nothing, which the daemon detected in 1 millisecond.**
  ///
  /// A file closes that because it outlives the process that wrote it. Read
  /// once and deleted by the reader, and deleted again before every spawn, so a
  /// retry can never be answered by the previous run's reason.
  String get failurePath => p.join(runDir, '$key.failed');

  void ensureRunDir() => flutterwareRunDir();

  /// Sorts maps by key so the hash depends on the values, not on the order
  /// `toJson` happened to emit them in.
  static Object? _canonical(Object? value) => switch (value) {
    Map<String, Object?> map => {
      for (var key in map.keys.toList()..sort()) key: _canonical(map[key]),
    },
    List<Object?> list => [for (var item in list) _canonical(item)],
    _ => value,
  };
}
