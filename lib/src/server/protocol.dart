/// The wire and rendezvous vocabulary shared by the in-server inspector and
/// its attachers (GUI, `fw`, MCP).
///
/// One frame shape in both directions, newline-delimited JSON:
///
///     {"ch": "sql", "t": "event", "e": 12, "ts": 1690000000000, "p": {…}}
///     {"ch": "sql", "t": "req",  "id": 7, "m": "explain", "p": {…}}
///     {"ch": "sql", "t": "res",  "id": 7, "p": {…}}
///     {"ch": "sql", "t": "err",  "id": 7, "p": {"message": "…"}}
///
/// `ch` is a sub-protocol name. New feature = new channel name; the envelope
/// itself is expected to stay at [protocolVersion] indefinitely — see
/// `docs/superpowers/specs/2026-07-30-server-inspection-design.md`.
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const protocolVersion = 1;

/// Frame keys, spelled once.
const frameChannel = 'ch';
const frameType = 't';
const framePayload = 'p';
const frameMethod = 'm';
const frameRequestId = 'id';
const frameEventId = 'e';
const frameTimestamp = 'ts';
const frameCorrelation = 'rid';

const typeEvent = 'event';
const typeRequest = 'req';
const typeResponse = 'res';
const typeError = 'err';

/// The built-in channel. `meta/attach` is the handshake that turns a
/// connection into an attachment; `replay-done` marks the ring/live boundary.
const metaChannel = 'meta';
const metaAttach = 'attach';
const metaReplayDone = 'replay-done';

String encodeFrame(Map<String, Object?> frame) => '${jsonEncode(frame)}\n';

/// Decodes one line into a frame, or null for anything that is not a JSON
/// object — a probe's noise, a partial line from a dying peer. The read loops
/// on both sides ignore null rather than erroring: tolerating garbage is what
/// makes a connect-and-close liveness knock free.
Map<String, Object?>? tryDecodeFrame(String line) {
  try {
    var decoded = jsonDecode(line);
    if (decoded is! Map) return null;
    return decoded.cast<String, Object?>();
  } on FormatException {
    return null;
  }
}

/// `~/.flutterware/run` if it exists, else null — **never created here**.
///
/// Its absence is one of the inspector's gates: a machine that never ran
/// flutterware has no run dir, and a server there stays inert even under
/// `dart run`. Creating it (as the GUI's `flutterwareRunDir()` does) would
/// defeat that.
String? existingRunDir() {
  var home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null) return null;
  var dir = p.join(home, '.flutterware', 'run');
  return Directory(dir).existsSync() ? dir : null;
}

/// Whether the inspector may come alive, from the three gates the spec names:
/// release builds are inert, machines without a run dir are inert, and
/// `FW_SERVER_INSPECT` overrides in both directions.
bool serverInspectionEnabled({
  required bool product,
  required String? envOverride,
  required bool runDirExists,
}) {
  if (envOverride == '0') return false;
  if (envOverride == '1') return true;
  if (product) return false;
  return runDirExists;
}

/// 8 hex of sha1 — a filename uniquifier only. Attachers match handles by
/// [ServerHandle.projectRoot] containment, never by parsing this back.
String projectRootHash(String projectRoot) =>
    sha1.convert(utf8.encode(projectRoot)).toString().substring(0, 8);

/// A server name made safe for a socket filename: the allowed alphabet, and
/// short enough that the path stays under the 104-byte `sun_path` cap.
String sanitizeServerName(String name) {
  var safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
  if (safe.isEmpty) safe = 'server';
  return safe.length <= 24 ? safe : safe.substring(0, 24);
}

String serverHandleBaseName({
  required String projectRoot,
  required String name,
  required int pid,
}) => 'srv-${projectRootHash(projectRoot)}-${sanitizeServerName(name)}-$pid';

/// The published announcement: one JSON file per live server process.
class ServerHandle {
  ServerHandle({
    required this.projectRoot,
    required this.name,
    required this.socketPath,
    required this.pid,
    required this.startedAt,
    this.protocol = protocolVersion,
    this.handlePath,
  });

  final String projectRoot;
  final String name;
  final String socketPath;
  final int pid;
  final DateTime startedAt;
  final int protocol;

  /// Where this handle was read from — null on the publishing side.
  final String? handlePath;

  Map<String, Object?> toJson() => {
    'projectRoot': projectRoot,
    'name': name,
    'socketPath': socketPath,
    'pid': pid,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'protocol': protocol,
  };

  static ServerHandle? tryRead(File file) {
    try {
      var json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return null;
      var map = json.cast<String, Object?>();
      return ServerHandle(
        projectRoot: map['projectRoot']! as String,
        name: map['name']! as String,
        socketPath: map['socketPath']! as String,
        pid: map['pid']! as int,
        startedAt: DateTime.parse(map['startedAt']! as String),
        protocol: map['protocol'] as int? ?? protocolVersion,
        handlePath: file.path,
      );
    } on Object {
      // Torn write, stale schema, deleted meanwhile — a handle that cannot be
      // read is a handle that does not exist.
      return null;
    }
  }

  @override
  String toString() => 'ServerHandle($name, pid $pid, $projectRoot)';
}

/// The `srv-*.json` handles in [runDir], newest first, optionally filtered to
/// servers whose project root sits inside [underRoot].
///
/// Containment rather than equality, deliberately: a server in a monorepo runs
/// from `repo/server_pkg/` and must still appear under the `repo` worktree.
/// Reads files and nothing else — liveness is decided by connecting, and this
/// is called from places (`report`, `computeAll`) that must not open sockets.
List<ServerHandle> scanServerHandles(String runDir, {String? underRoot}) {
  List<FileSystemEntity> entries;
  try {
    entries = Directory(runDir).listSync();
  } on FileSystemException {
    return [];
  }
  var handles = <ServerHandle>[];
  for (var entity in entries) {
    var name = p.basename(entity.path);
    if (entity is! File ||
        !name.startsWith('srv-') ||
        !name.endsWith('.json')) {
      continue;
    }
    var handle = ServerHandle.tryRead(entity);
    if (handle == null) continue;
    if (underRoot != null &&
        !p.equals(underRoot, handle.projectRoot) &&
        !p.isWithin(underRoot, handle.projectRoot)) {
      continue;
    }
    handles.add(handle);
  }
  handles.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return handles;
}

/// Deletes a handle's files — used after a failed connect, the same
/// "on the way past" cleanup `attachToLiveSession` does.
void deleteServerHandle(ServerHandle handle) {
  for (var path in [handle.handlePath, handle.socketPath]) {
    if (path == null) continue;
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // Somebody else swept it first; that was the goal.
    }
  }
}
