import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'dart_executable.dart';

/// A child process holding an exclusive lock on [path], for as long as it
/// lives.
///
/// A real process, because an advisory lock is per process: a second take
/// inside this one succeeds and would prove nothing. Shared by the suites that
/// need somebody *else* to hold a lock — the build-directory claims and the
/// base-checkout sweep — which each had reason to want one.
Future<Process> holdLock(String path) async {
  var script =
      File(
        p.join(
          Directory.systemTemp.createTempSync('fw_lock_holder').path,
          'hold.dart',
        ),
      )..writeAsStringSync('''
import 'dart:io';

void main(List<String> args) {
  var handle = File(args.single).openSync(mode: FileMode.append);
  handle.lockSync();
  stdout.writeln('held');
  // Held until killed.
  stdin.listen((_) {});
}
''');
  var process = await Process.start(resolveDartExecutable(), [
    'run',
    script.path,
    path,
  ]);
  // **Registered before the first await, not after the caller's.** A child
  // that holds a lock and reads stdin holds it for ever, so anything between
  // starting it and arranging its death is a window where a failure orphans a
  // process — and the wait below is exactly such a failure. One did survive a
  // timeout and was still running hours later.
  addTearDown(() async {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  });
  // The lock is not taken until the child says so, and a race here would test
  // the unlocked path while calling itself the locked one.
  await process.stdout
      .map(String.fromCharCodes)
      .firstWhere((line) => line.contains('held'))
      .timeout(
        const Duration(seconds: 60),
        onTimeout: () => fail('the lock holder never started'),
      );
  return process;
}
