import 'dart:io';

import 'package:flutterware/src/build_lock.dart';

/// One contender for [withBuildLock], run as its own process.
///
/// A process rather than an isolate because that is the boundary the lock is
/// about: the OS lock is advisory per process, so two isolates would both walk
/// straight through it and a test built that way would pass on a broken lock.
///
/// Usage: `<lock file> <transcript> <name>`.
void main(List<String> arguments) async {
  var [lockFile, transcript, name] = arguments;
  await withBuildLock(lockFile, () async {
    var file = File(transcript);
    file.writeAsStringSync('$name in\n', mode: FileMode.append, flush: true);
    // Long enough that a lock that does not hold interleaves — the other
    // process is spawned inside this window.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    file.writeAsStringSync('$name out\n', mode: FileMode.append, flush: true);
  }, onWait: () => stdout.writeln('waited'));
}
