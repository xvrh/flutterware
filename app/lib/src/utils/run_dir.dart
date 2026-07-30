import 'dart:io';

import 'package:path/path.dart' as p;

/// Where flutterware puts unix sockets and other per-run scratch.
///
/// Deliberately short and *not* under the project's build directory. A unix
/// socket path is capped at 104 bytes on macOS — `sun_path` in `man 7 unix` —
/// and the CLI installs its copy of the GUI under
/// `~/.flutterware/<sha1>/app/`, which is 70 characters before anything else is
/// appended. A socket under that copy's `build/` overflows, and the error the
/// OS gives is about path length rather than about anything the caller did.
String flutterwareRunDir() {
  var home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  var dir = p.join(home, '.flutterware', 'run');
  Directory(dir).createSync(recursive: true);
  return dir;
}

/// Deletes what previous runs left behind in [flutterwareRunDir].
///
/// Nothing used to. Every daemon writes a `<key>.log` and a `<key>.lock` there,
/// and its `<key>.sock` survives any exit that is not graceful — while the key
/// itself moves whenever the daemon's own sources change, so *every edit to the
/// daemon leaves a fresh set behind*. Measured on one machine after three days
/// of development: 458 files, 227 locks, 214 logs, 14 orphaned sockets. None of
/// it large, all of it permanent, and `_tailLog` reads a whole log on every
/// failed connect.
///
/// Two rules, and the difference between them is what makes this safe to run
/// while other flutterware processes are up:
///
/// - **Nothing modified within [keepFor] is touched.** That is what protects
///   everything in use: a live daemon appends to its log, and a client that is
///   *this moment* deciding whether to spawn is holding a lock it just created.
///   It also leaves a post-mortem window — the log of a daemon that died an hour
///   ago is the only account of why.
/// - **Older than that, a daemon socket is deleted only if nothing answers it**,
///   and its log and lock only if its socket did not. A daemon can legitimately
///   run for days; unlinking its socket would leave it running and unreachable,
///   which is worse than the litter.
///
/// Guest sockets (`g-*`, `shot-*`, and the spikes) are aged out without a
/// connect test. Unlinking a unix socket does not disturb connections already
/// established on it, so the cost of being wrong about a guest is that nobody
/// new can reach it — and a guest that has been up for [keepFor] is not a guest,
/// it is a leak. They are not probed because a guest's IPC socket expects a
/// protocol, not a knock.
///
/// Frame-scratch directories (`cap-*`) age out the same way. A session that
/// closes cleanly deletes its own; this catches the ones a crash left behind.
/// A directory's mtime moves with every file created or deleted inside it, and
/// a capture does both per frame, so a directory old enough to sweep belongs
/// to nothing.
///
/// `live-*.json` is left alone: there is exactly one per project, so it is
/// bounded, and [attachToLiveSession] already deletes one that will not connect.
///
/// Every failure is swallowed per file. This is housekeeping — another process
/// winning a race to delete the same orphan is the expected case, not an error,
/// and nothing here is worth failing a daemon start over.
///
/// [directory] defaults to [flutterwareRunDir] and exists so the rules can be
/// tested: what they turn on is a file's name and age, not where it sits, and
/// "spares a daemon that still answers" is not checkable against a directory the
/// test cannot put a listening socket in.
Future<int> sweepRunDir({
  Duration keepFor = const Duration(days: 1),
  String? directory,
}) async {
  var dir = Directory(directory ?? flutterwareRunDir());
  var cutoff = DateTime.now().subtract(keepFor);
  List<FileSystemEntity> entries;
  try {
    entries = dir.listSync();
  } on FileSystemException {
    return 0;
  }

  var deleted = 0;
  // Keys whose daemon is still there, so its log and lock stay with it.
  var serving = <String>{};

  for (var entity in entries) {
    var name = p.basename(entity.path);
    if (!name.endsWith('.sock')) continue;
    var key = name.substring(0, name.length - '.sock'.length);
    if (!_isOlderThan(entity, cutoff)) {
      serving.add(key);
      continue;
    }
    // A daemon key is the 16 hex characters of a config hash. Anything else in
    // here is a guest or a spike, and is aged out rather than knocked on.
    if (_daemonKey.hasMatch(key) && await _answers(entity.path)) {
      serving.add(key);
      continue;
    }
    if (_delete(entity)) deleted++;
  }

  for (var entity in entries) {
    var name = p.basename(entity.path);
    if (!name.endsWith('.log') && !name.endsWith('.lock')) continue;
    var key = name.substring(0, name.lastIndexOf('.'));
    if (serving.contains(key)) continue;
    if (!_isOlderThan(entity, cutoff)) continue;
    if (_delete(entity)) deleted++;
  }

  for (var entity in entries) {
    if (entity is! Directory) continue;
    if (!p.basename(entity.path).startsWith('cap-')) continue;
    if (!_isOlderThan(entity, cutoff)) continue;
    try {
      entity.deleteSync(recursive: true);
      deleted++;
    } on FileSystemException {
      // Another sweeper won the race, or a frame is mid-write; either way it
      // is not ours to force.
    }
  }

  return deleted;
}

final _daemonKey = RegExp(r'^[0-9a-f]{16}$');

bool _isOlderThan(FileSystemEntity entity, DateTime cutoff) {
  try {
    return entity.statSync().modified.isBefore(cutoff);
  } on FileSystemException {
    return false;
  }
}

/// Whether anything is listening on [socketPath].
///
/// The same test [CompilerDaemonClient] uses to decide whether to spawn: the
/// file being present proves only that a daemon once bound it.
Future<bool> _answers(String socketPath) async {
  try {
    var socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    ).timeout(const Duration(seconds: 1));
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}

bool _delete(FileSystemEntity entity) {
  try {
    entity.deleteSync();
    return true;
  } on FileSystemException {
    // Lost a race with another sweeper, or no permission. Neither is ours to
    // report.
    return false;
  }
}

/// The longest a unix socket path may be, minus the NUL terminator.
///
/// 104 on macOS, 108 on Linux; the smaller is used everywhere so a path that
/// works on one does not fail on the other.
const maxSocketPathLength = 103;

/// Fails early, and legibly, on a socket path the OS will refuse.
///
/// Without this the symptom is a `SocketException` naming a limit rather than
/// the thing that produced the path, which is a long way from the cause.
String checkSocketPath(String path) {
  if (path.length <= maxSocketPathLength) return path;
  throw StateError(
    'Socket path is ${path.length} bytes, over the $maxSocketPathLength-byte '
    'limit:\n  $path\n'
    'Put it under flutterwareRunDir() rather than a build directory.',
  );
}
