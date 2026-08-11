import 'dart:convert';
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

  /// A run handle naming [launcherPid], [age] old. Only the pid and start
  /// time are read by the sweeper; the rest is there so the file is a real
  /// handle rather than a shape that happens to parse.
  File handle(String name, int launcherPid, Duration age, {DateTime? started}) {
    var file = File(p.join(runDir.path, name))
      ..writeAsStringSync(
        jsonEncode({
          'worktree': '/tmp/wt',
          'worktreeName': '~',
          'device': 'phone',
          'entrypoint': 'lib/main.dart',
          'launcherPid': launcherPid,
          'startedAt': (started ?? DateTime.now()).toUtc().toIso8601String(),
        }),
      );
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

    test('a failure marker nobody came back for', () async {
      // Normally the client waiting on the spawn reads it and deletes it. A
      // client that had already connected hears the failure over the socket
      // instead and never looks at the file — so it is orphaned exactly when a
      // daemon fails with somebody attached, and the key moves on every edit to
      // the daemon's own sources.
      var key = 'f' * 16;
      aged('$key.failed', const Duration(days: 3));

      expect(await sweep(), 1);
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

    test('a frame-scratch directory a crash left behind', () async {
      // A session that closes cleanly deletes its own `cap-*`; only a crash
      // leaves one, and a capture in progress keeps its directory's mtime
      // fresh by writing and deleting frames in it.
      var dir = Directory(p.join(runDir.path, 'cap-session-9-0'))..createSync();
      File(p.join(dir.path, 'screenshot.rawframe')).writeAsStringSync('x');
      // `Directory` has no setLastModifiedSync; this file already assumes a
      // unix machine by binding unix-domain sockets.
      var stamp = DateTime.now().subtract(const Duration(days: 3));
      String two(int n) => n.toString().padLeft(2, '0');
      var when =
          '${stamp.year}${two(stamp.month)}${two(stamp.day)}'
          '${two(stamp.hour)}${two(stamp.minute)}';
      Process.runSync('touch', ['-m', '-t', when, dir.path]);

      expect(await sweep(), 1);
      expect(dir.existsSync(), isFalse);
    });

    test("a dead server's socket, and its handle with it", () async {
      // `srv-*` is probed like a daemon, not aged like a guest — but this one
      // is a plain file where a socket was, so nothing answers, and the
      // handle would otherwise keep announcing a server that is gone.
      aged('srv-12ab34cd-api-4242.sock', const Duration(days: 3));
      aged('srv-12ab34cd-api-4242.json', const Duration(days: 3));

      expect(await sweep(), 2);
      expect(runDir.listSync(), isEmpty);
    });

    test('a run handle whose launcher is gone', () async {
      // A run announces itself in `app-*.json` and points at a VM service on a
      // device, so there is no socket here to knock on. The launcher's pid is
      // the one thing this sweeper can check cheaply, and a dead one on a
      // handle this old is what a crash leaves behind.
      var process = await Process.start('true', const []);
      await process.exitCode;
      handle(
        'app-deadbeef1234-${process.pid}.json',
        process.pid,
        const Duration(days: 3),
      );

      expect(await sweep(), 1);
      expect(runDir.listSync(), isEmpty);
    });

    test('a run handle nothing can parse', () async {
      aged('app-torn-1.json', const Duration(days: 3));

      expect(await sweep(), 1);
      expect(runDir.listSync(), isEmpty);
    });
  });

  group('what it spares', () {
    test("a living run's journal, however old", () async {
      // The handle is still in the ledger — its launcher is this very test's
      // process — so the run's story stays replayable in the Steps tab. Only
      // the handle's own death starts the journal's clock.
      handle('app-z-$pid.json', pid, const Duration(days: 3));
      aged('app-z-$pid.journal.jsonl', const Duration(days: 30));

      expect(await sweep(), 0);
      expect(runDir.listSync(), hasLength(2));
    });

    test('a run handle whose launcher is still alive, however old', () async {
      // A desktop session can legitimately be up since Monday. Sweeping its
      // handle would free a device that is very much in use — the same lie the
      // `srv-*` rule exists to avoid, arrived at from the other side.
      handle('app-abcdef123456-$pid.json', pid, const Duration(days: 30));

      expect(await sweep(), 0);
      expect(runDir.listSync(), hasLength(1));
    });

    test("a dead run's journal, its rotation and its artifacts", () async {
      // No handle named app-x-9 exists, so the story's run is gone and the
      // story ages out. Before this rule the journals matched no sweep rule
      // and grew forever.
      aged('app-x-9.journal.jsonl', const Duration(days: 3));
      aged('app-x-9.journal.jsonl.1', const Duration(days: 3));
      var artifacts = Directory(p.join(runDir.path, 'journal', 'app-x-9'))
        ..createSync(recursive: true);
      File(p.join(artifacts.path, '1-9.png')).writeAsStringSync('x');
      // `File.setLastModifiedSync` has no `Directory` counterpart.
      var old = DateTime.now().subtract(const Duration(days: 3));
      String two(int n) => n.toString().padLeft(2, '0');
      Process.runSync('touch', [
        '-mt',
        '${old.year}${two(old.month)}${two(old.day)}${two(old.hour)}${two(old.minute)}',
        artifacts.path,
      ]);

      expect(await sweep(), 3);
      expect(artifacts.existsSync(), isFalse);
    });

    test('a journal in the same pass as its dying handle', () async {
      // The handle is swept by loop three — dead launcher — and the journal
      // rule runs after it, so one pass takes the run and its story together
      // rather than leaving the story for tomorrow's sweep.
      var dead = await _deadPid();
      handle('app-y-$dead.json', dead, const Duration(days: 3));
      aged('app-y-$dead.journal.jsonl', const Duration(days: 3));

      expect(await sweep(), 2);
      expect(runDir.listSync(), isEmpty);
    });

    test('a run handle whose pid was recycled is swept anyway', () async {
      // The pid is alive — it is this very test's — but the handle claims a
      // launcher recorded two days ago, and this process is minutes old. A
      // number that young is somebody else wearing a dead launcher's pid;
      // without the age check the handle read as alive forever and pinned
      // its device as busy in every worktree.
      handle(
        'app-abcdef123456-$pid.json',
        pid,
        const Duration(days: 3),
        started: DateTime.now().subtract(const Duration(days: 2)),
      );

      expect(await sweep(), 1);
      expect(runDir.listSync(), isEmpty);
    });

    test('the device cache, which is bounded and self-refreshing', () async {
      // One file per machine, overwritten by the next daemon. Deleting it only
      // makes a cold `fw devices` answer "nobody has ever looked".
      aged('devices.json', const Duration(days: 30));

      expect(await sweep(), 0);
      expect(runDir.listSync(), hasLength(1));
    });

    test('a server socket that still answers, however old', () async {
      // The guest rule would be wrong here: a dev server legitimately runs
      // for days, and unlinking a live one's socket makes it unreachable for
      // new attachers — the next scan would then delete its handle as dead,
      // and the server would vanish from the list while still running. The
      // probe is free: an inspected server writes nothing to a connection
      // that has not sent `meta/attach`.
      var base = 'srv-12ab34cd-api-4242';
      var socketPath = p.join(runDir.path, '$base.sock');
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
      aged('$base.json', const Duration(days: 3));

      expect(await sweep(), 0);
      expect(File(socketPath).existsSync(), isTrue);
      expect(
        File(p.join(runDir.path, '$base.json')).existsSync(),
        isTrue,
        reason: "a live server's handle is what keeps it discoverable",
      );
    });

    test('anything modified inside the window', () async {
      // The rule that protects everything in use: a live daemon appends to its
      // log, and a client deciding whether to spawn has just created its lock.
      var key = 'c' * 16;
      aged('$key.lock', const Duration(minutes: 1));
      aged('$key.log', const Duration(minutes: 1));
      aged('g-fresh.sock', const Duration(minutes: 1));
      Directory(p.join(runDir.path, 'cap-session-1-0')).createSync();

      expect(await sweep(), 0);
      expect(runDir.listSync(), hasLength(4));
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

  group('process age', () {
    // `etime` rather than `lstart` because elapsed prints the same way in
    // every locale. These pin the format: [[dd-]hh:]mm:ss.
    test('parses every etime shape ps produces', () {
      expect(parseElapsed('04:05'), const Duration(minutes: 4, seconds: 5));
      expect(
        parseElapsed(' 03:04:05\n'),
        const Duration(hours: 3, minutes: 4, seconds: 5),
      );
      expect(
        parseElapsed('12-03:04:05'),
        const Duration(days: 12, hours: 3, minutes: 4, seconds: 5),
      );
      expect(parseElapsed('nonsense'), isNull);
      expect(parseElapsed(''), isNull);
    });

    test('this process is current against a record from before it', () {
      expect(isProcessCurrent(pid, DateTime.now()), isTrue);
    });

    test('this process is not the launcher a day-old record names', () {
      expect(
        isProcessCurrent(pid, DateTime.now().subtract(const Duration(days: 1))),
        isFalse,
      );
    });
  });
}

/// A pid that is certainly gone: a process started and waited for.
///
/// Better than a large constant, which is only *probably* free and would make
/// these tests flaky on whichever machine happened to be using it.
Future<int> _deadPid() async {
  var process = await Process.start('true', const []);
  await process.exitCode;
  return process.pid;
}
