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
