import 'dart:io';

import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The run directory's housekeeping.
///
/// Nothing swept it until now, and the litter is structural rather than
/// occasional: a daemon's key is a hash that *includes its own build*, so every
/// edit to the daemon leaves behind a socket, a lock and a log under a key
/// nothing will ever use again. One machine had 458 files after three days.
///
/// The interesting cases here are all the ones where deleting would be wrong —
/// a live daemon's log, a lock a client is holding right now, a socket that
/// still answers. [sweepRunDir] resolves those with two rules, and these tests
/// are those two rules.
///
/// The sweeper is pointed at a temp directory per test, so nothing here can
/// reach the developer's real `~/.flutterware/run` — and so a real listening
/// socket can be put in it. That directory is deliberately unnested: a unix
/// socket path is capped at 104 bytes and macOS temp paths start at ~50, which is
/// the same arithmetic that put the run dir under `$HOME` in the first place.
void main() {
  late Directory runDir;

  /// A file in the run dir, [age] old.
  File aged(String name, Duration age) {
    var file = File(p.join(runDir.path, name))..writeAsStringSync('x');
    file.setLastModifiedSync(DateTime.now().subtract(age));
    return file;
  }

  setUp(() => runDir = Directory.systemTemp.createTempSync('fw-run-'));

  tearDown(() {
    if (runDir.existsSync()) runDir.deleteSync(recursive: true);
  });

  Future<int> sweep({Duration keepFor = const Duration(days: 1)}) =>
      sweepRunDir(keepFor: keepFor, directory: runDir.path);

  group('what it deletes', () {
    test('an orphaned lock and log from a key nothing serves', () async {
      var key = 'a' * 16;
      aged('$key.lock', const Duration(days: 3));
      aged('$key.log', const Duration(days: 3));

      expect(await sweep(), 2);
      expect(runDir.listSync(), isEmpty);
    });

    test('a socket file with nobody listening', () async {
      var key = 'b' * 16;
      // A daemon that died without unlinking leaves a plain file where a socket
      // was — connecting to it fails, which is the liveness test.
      aged('$key.sock', const Duration(days: 3));
      aged('$key.log', const Duration(days: 3));

      expect(await sweep(), 2);
      expect(runDir.listSync(), isEmpty);
    });

    test('a guest socket, without knocking on it', () async {
      // `g-*` and `shot-*` are guest IPC sockets. They are aged out rather than
      // probed, because a guest expects a protocol and not a knock — and
      // unlinking a unix socket does not disturb a connection already
      // established on it.
      aged('g-session-4.sock', const Duration(days: 3));
      aged('shot-deadbeef.sock', const Duration(days: 3));

      expect(await sweep(), 2);
    });
  });

  group('what it spares', () {
    test('anything modified inside the window', () async {
      // The rule that protects everything in use: a live daemon appends to its
      // log, and a client deciding whether to spawn has just created its lock.
      var key = 'c' * 16;
      aged('$key.lock', const Duration(minutes: 1));
      aged('$key.log', const Duration(minutes: 1));
      aged('g-fresh.sock', const Duration(minutes: 1));

      expect(await sweep(), 0);
      expect(runDir.listSync(), hasLength(3));
    });

    test('a log old enough to delete, whose daemon still answers', () async {
      // The case that matters most. A daemon can legitimately run for days;
      // unlinking its socket would leave it running and unreachable, which is
      // worse than the litter it was cleaning up.
      var key = 'd' * 16;
      var socketPath = p.join(runDir.path, '$key.sock');
      var server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      addTearDown(() async {
        await server.close();
        if (File(socketPath).existsSync()) File(socketPath).deleteSync();
      });
      File(
        socketPath,
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 3)));
      aged('$key.log', const Duration(days: 3));

      expect(await sweep(), 0);
      expect(File(socketPath).existsSync(), isTrue);
      expect(
        File(p.join(runDir.path, '$key.log')).existsSync(),
        isTrue,
        reason: "a serving daemon's log is its own, however old",
      );
    });

    test('a published live session, which is bounded and self-healing', () async {
      // One file per project ever, and `attachToLiveSession` already deletes one
      // that will not connect. Ageing these out would break attach for a GUI
      // that has simply been open a long time.
      aged('live-${'e' * 16}.json', const Duration(days: 30));

      expect(await sweep(), 0);
      expect(runDir.listSync(), hasLength(1));
    });

    test('a file it does not recognise', () async {
      aged('something-a-person-put-here.txt', const Duration(days: 30));

      expect(await sweep(), 0);
      expect(runDir.listSync(), hasLength(1));
    });
  });

  test('a missing run directory is not an error', () async {
    runDir.deleteSync(recursive: true);
    expect(await sweep(), 0);
  });

  group('checkSocketPath', () {
    test('accepts a path the OS will take', () {
      expect(checkSocketPath('/tmp/short.sock'), '/tmp/short.sock');
    });

    test('names the limit and the offender', () {
      var tooLong = '/tmp/${'x' * 200}.sock';
      expect(
        () => checkSocketPath(tooLong),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('$maxSocketPathLength-byte'),
              contains('flutterwareRunDir'),
            ),
          ),
        ),
      );
    });
  });
}
