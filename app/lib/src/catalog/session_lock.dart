import 'dart:io';

import 'package:path/path.dart' as p;

/// Refuses to start a second catalog session against the same build directory.
///
/// A session owns a compiler daemon, a guest process and a generated
/// entrypoint; two of them would fight over the same files and quietly double
/// the process count. Cheap insurance, held for the life of the session.
class SessionLock {
  SessionLock._(this._file);

  final File _file;

  static SessionLock acquire(String buildDir) {
    var file = File(p.join(buildDir, 'session.lock'));
    file.parent.createSync(recursive: true);

    if (file.existsSync()) {
      var owner = int.tryParse(file.readAsStringSync().trim());
      if (owner != null && _isAlive(owner)) {
        throw StateError(
          'Another catalog session is already running (pid $owner). Close it '
          'first, or delete ${file.path} if it is stale.',
        );
      }
    }
    file.writeAsStringSync('$pid');
    return SessionLock._(file);
  }

  static bool _isAlive(int owner) =>
      Process.runSync('/bin/ps', ['-p', '$owner']).exitCode == 0;

  void release() {
    if (_file.existsSync()) _file.deleteSync();
  }
}
