import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/run_address.dart';
import 'package:flutterware_app/src/plugins/native/run_plugin.dart';
import 'package:flutterware_app/src/plugins/native/run_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/run/entrypoints.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:flutterware_app/src/run/inventory.dart';
import 'package:flutterware_app/src/run/launch.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/daemon/device.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

/// The devices-and-occupancy half of the run cockpit, against a temp run dir.
///
/// No `flutter daemon` is started anywhere here: the cache is a file, and this
/// exercises the path a cold `fw` takes — read the file, scan the ledger, probe
/// what it found, say how old the answer is.
void main() {
  late Directory runDir;
  late Directory worktree;
  late Directory otherWorktree;
  late RunCore core;

  setUp(() {
    runDir = Directory.systemTemp.createTempSync('fw-run-');
    worktree = Directory.systemTemp.createTempSync('fw-run-wt-');
    otherWorktree = Directory.systemTemp.createTempSync('fw-run-other-');
    RunCore.runDirProvider = () => runDir.path;
    core = _coreFor(worktree);
  });

  tearDown(() {
    core.dispose();
    RunCore.runDirProvider = flutterwareRunDir;
    for (var dir in [runDir, worktree, otherWorktree]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  group('the device cache', () {
    test('round-trips through the file and carries its age', () {
      DeviceCache.write(runDir.path, [
        const DaemonDevice(
          id: 'RF8M12L8GHW',
          name: 'SM G970F',
          platform: 'android-arm64',
          platformType: 'android',
          sdk: 'Android 12 (API 31)',
          connectionInterface: 'attached',
        ),
      ]);

      var cache = DeviceCache.read(runDir.path)!;
      expect(cache.devices.single.displayName, 'SM G970F');
      expect(cache.devices.single.isWireless, isFalse);
      expect(cache.ageDescription, 'just now');
    });

    test('is null when nothing has ever written one', () {
      expect(DeviceCache.read(runDir.path), isNull);
    });

    test('drops a device with no id rather than the whole list', () {
      File(DeviceCache.pathIn(runDir.path)).writeAsStringSync(
        jsonEncode({
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'devices': [
            {'name': 'nameless'},
            {'id': 'good', 'name': 'Good'},
          ],
        }),
      );

      expect(DeviceCache.read(runDir.path)!.devices.single.id, 'good');
    });

    test('orders physical devices before emulators and desktops', () {
      var devices = [
        const DaemonDevice(id: 'macos', name: 'macOS', ephemeral: false),
        const DaemonDevice(id: 'sim', name: 'iPhone 16 sim', emulator: true),
        const DaemonDevice(id: 'phone', name: 'Xavier iPhone'),
      ]..sort(compareDevices);

      expect([for (var d in devices) d.id], ['phone', 'sim', 'macos']);
    });
  });

  group('the ledger', () {
    test("lists every worktree's runs, newest first", () {
      _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'a.dart',
        startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      _writeHandle(runDir, otherWorktree, device: 'sim', entrypoint: 'b.dart');

      var handles = scanRunHandles(runDir.path);
      expect([for (var h in handles) h.entrypoint], ['b.dart', 'a.dart']);
    });

    test('filters to one worktree when asked, including the root itself', () {
      _writeHandle(runDir, worktree, device: 'phone', entrypoint: 'a.dart');
      _writeHandle(runDir, otherWorktree, device: 'sim', entrypoint: 'b.dart');

      var handles = scanRunHandles(runDir.path, underRoot: worktree.path);
      expect(handles.single.entrypoint, 'a.dart');
    });

    test('ignores a handle it cannot read', () {
      File(p.join(runDir.path, 'app-torn-1.json')).writeAsStringSync('{"wor');
      expect(scanRunHandles(runDir.path), isEmpty);
    });
  });

  group('report', () {
    test('reads the cache and the ledger without probing anything', () async {
      DeviceCache.write(runDir.path, [
        const DaemonDevice(id: 'phone', name: 'Xavier iPhone'),
        const DaemonDevice(id: 'sim', name: 'iPhone 16 sim', emulator: true),
      ]);
      var dead = await _deadPid();
      _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        launcherPid: dead,
      );

      await core.computeAll();
      var report = core.report;

      expect(report.status.message, contains('2 devices'));
      expect(report.status.message, contains('1 busy'));
      // **The children are runs, not devices.** A child's id becomes the first
      // address segment, and since the panel became run-centric those are the
      // only things it can be pointed at. Devices are counted in the status
      // line above and listed in the desk.
      expect(
        [for (var c in report.children) c.id],
        [runHandleKey(worktree.path, 'phone', 'lib/main.dart')],
      );
      expect(report.children.single.label, contains('main.dart'));
      // Nothing has been probed, and computeAll may not open a socket to find
      // out — so the row says it does not know rather than guessing.
      expect(report.children.single.status.message, contains('not probed'));
      // The dead handle is still on disk, for the same reason.
      expect(scanRunHandles(runDir.path), hasLength(1));
    });

    test('says the list is only cached when no daemon is running', () async {
      DeviceCache.write(runDir.path, [const DaemonDevice(id: 'phone')]);
      await core.computeAll();
      expect(core.isLive, isFalse);
      expect(core.report.status.message, contains('just now'));
    });
  });

  group('devices', () {
    test('reports occupancy with the holding worktree', () async {
      DeviceCache.write(runDir.path, [
        const DaemonDevice(
          id: 'phone',
          name: 'Xavier iPhone',
          platformType: 'ios',
          connectionInterface: 'wireless',
        ),
      ]);
      _writeHandle(
        runDir,
        otherWorktree,
        device: 'phone',
        entrypoint: 'lib/main_staging.dart',
        entrypointName: 'Staging',
        worktreeName: 'feature-x',
        launcherPid: pid,
      );

      var result = (await core.invoke('devices'))! as RunDevicesResult;

      expect(result.live, isFalse);
      expect(result.age, 'just now');
      var device = result.devices.single;
      expect(device.connection, 'wireless');
      expect(device.running.single.worktree, 'feature-x');
      expect(device.running.single.entrypointName, 'Staging');
    });

    test('explains an empty list rather than leaving an empty array', () async {
      var result = (await core.invoke('devices'))! as RunDevicesResult;
      expect(result.devices, isEmpty);
      expect(result.note, contains('No device list has been taken'));
    });
  });

  group('apps', () {
    test('keeps a run that is still building and says so', () async {
      // A live launcher and no VM service yet: this is a cold Android build,
      // which takes a minute and a half. Sweeping it would free a device that
      // is very much in use.
      _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        launcherPid: pid,
      );

      var result = (await core.invoke('apps'))! as RunAppsResult;

      expect(result.swept, 0);
      var app = result.apps.single;
      expect(app.launcher, isTrue);
      expect(app.app, isFalse);
      expect(app.mine, isTrue);
      expect(app.error, 'not started yet');
    });

    test('sweeps a handle nothing answers', () async {
      _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        launcherPid: await _deadPid(),
      );

      var result = (await core.invoke('apps'))! as RunAppsResult;

      expect(result.swept, 1);
      expect(result.apps, isEmpty);
      expect(scanRunHandles(runDir.path), isEmpty);
    });

    test('the rail carries the one thing a list of runs cannot say', () {
      // `+ New run` was a chip in the panel; the chips are gone, so it is a
      // command on the plugin's own rail row. It names a place rather than a
      // callback, so the button and a typed address do the same thing.
      var command = RunPlugin(core).rowCommands().single;
      expect(command.label, 'New run');
      expect(command.opens, newRunSegment);
      expect(runPlace([command.opens]).isNew, isTrue);
    });

    test('a failed run is a rail row, not only a panel state', () async {
      // The rail is the list — the chip row that used to hold failures is
      // gone, so a launch that failed has to be a child here or it has
      // vanished a second time.
      var handle = _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        entrypointName: 'App',
        logPath: p.join(runDir.path, 'app-railed.log'),
        launcherPid: await _deadPid(),
      );
      File(handle.logPath!).writeAsStringSync('Error: could not code sign\n');

      await core.invoke('apps');
      await core.computeAll();

      var child = core.report.children.singleWhere((c) => c.id == handle.key);
      expect(child.label, 'App · phone');
      expect(child.status.tone, Tone.error);
      expect(child.status.message, 'Error: could not code sign');

      // And a *different process* sees it. This was memory first, which meant
      // a launch that failed under `fw` was missing from the GUI's rail — the
      // one list it had just been promoted into.
      var elsewhere = _coreFor(worktree);
      addTearDown(elsewhere.dispose);
      await elsewhere.computeAll();
      expect(elsewhere.failureFor(handle.key)?.headline, contains('code sign'));
    });

    test('a failure older than the window is history, and is left alone', () {
      var stale = RunFailure(
        key: 'app-stale',
        device: 'phone',
        entrypoint: 'lib/main.dart',
        at: DateTime.now().subtract(const Duration(days: 2)),
      );
      stale.write(runDir.path);

      expect(scanRunFailures(runDir.path), isEmpty);
      // Not deleted here. This scan runs inside `computeAll`, which reads and
      // does not write; the run dir's sweeper ages `.failed` out on the same
      // rule as the log beside it.
      expect(
        File(p.join(runDir.path, 'app-stale.failed')).existsSync(),
        isTrue,
      );
    });

    test('a long failure keeps its cause, not its summary', () {
      // A tool states the fault first and summarises last. Capping to the tail
      // would drop `Error (Xcode): …` and keep `App failed to start`, which is
      // the bug the block exists to fix.
      var path = p.join(runDir.path, 'app-long.log');
      File(path).writeAsStringSync(
        [
          'Error (Xcode): No Account for Team "B7V224LKE4".',
          for (var i = 0; i < 60; i++) 'noise $i',
          'App failed to start',
        ].join('\n'),
      );

      var failure = LaunchLog.read(path).failure(launcherAlive: false)!;

      expect(failure, startsWith('Error (Xcode): No Account'));
      expect(failure, contains('more lines in the log'));
      expect(failure, isNot(contains('App failed to start')));
      expect(
        LaunchLog.read(path).failureHeadline,
        'Error (Xcode): No Account for Team "B7V224LKE4".',
      );
    });

    test('sweeping a run that never started keeps why', () async {
      // The handle must go — a dead launcher is not holding the phone — but
      // deleting it was also deleting the only thing on screen, which is what
      // a failed launch closing "without explanation" actually was.
      var handle = _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        logPath: p.join(runDir.path, 'app-failed.log'),
        launcherPid: await _deadPid(),
      );
      File(
        handle.logPath!,
      ).writeAsStringSync('Error: could not code sign the application\n');

      await core.invoke('apps');

      expect(scanRunHandles(runDir.path), isEmpty);
      var failure = core.failureFor(handle.key)!;
      expect(failure.headline, 'Error: could not code sign the application');
      expect(failure.deviceLabel, 'phone');
      expect(failure.logPath, handle.logPath);
      expect(core.failures, hasLength(1));
    });

    test('a run that started and was stopped leaves no obituary', () async {
      var handle = _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        logPath: p.join(runDir.path, 'app-ran.log'),
        launcherPid: await _deadPid(),
      );
      File(
        handle.logPath!,
      ).writeAsStringSync('${_event('app.started', {'appId': 'a1'})}\n');

      await core.invoke('apps');

      expect(scanRunHandles(runDir.path), isEmpty);
      expect(core.failures, isEmpty);
    });

    test(
      'reports why an app did not answer while its launcher lives',
      () async {
        _writeHandle(
          runDir,
          worktree,
          device: 'phone',
          entrypoint: 'lib/main.dart',
          launcherPid: pid,
          // Nothing listens on port 1; the connect fails immediately.
          vmService: 'ws://127.0.0.1:1/ws',
        );

        var result = (await core.invoke('apps'))! as RunAppsResult;

        expect(result.swept, 0);
        expect(result.apps.single.app, isFalse);
        expect(result.apps.single.launcher, isTrue);
        expect(result.apps.single.error, isNotNull);
      },
    );

    test("marks another worktree's run as not mine", () async {
      _writeHandle(
        runDir,
        otherWorktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        worktreeName: 'feature-x',
        launcherPid: pid,
      );

      var result = (await core.invoke('apps'))! as RunAppsResult;

      expect(result.apps.single.mine, isFalse);
      expect(result.apps.single.worktree, 'feature-x');
    });
  });

  group('entry points', () {
    test('a scan finds top-level mains and nothing below them', () {
      _writePackage(worktree, 'app', {
        'lib/main.dart': 'void main() {}',
        'lib/main_staging.dart': 'Future<void> main() async {}',
        'lib/widget.dart': 'class Widget {}',
        // A `main()` under `lib/src/` is somebody's helper or a generated
        // harness, and offering it in a launch menu is noise.
        'lib/src/tool.dart': 'void main() {}',
      });

      var found = scanEntrypoints(p.join(worktree.path, 'app'));

      expect(
        [for (var e in found) e.path],
        ['lib/main.dart', 'lib/main_staging.dart'],
      );
      expect(found.every((e) => !e.declared), isTrue);
    });

    test('a declaration wins over the scan, and carries the knobs', () async {
      _writePackage(worktree, 'app', {
        'lib/main.dart': 'void main() {}',
        'lib/other.dart': 'void main() {}',
      });
      core = _coreFor(
        worktree,
        config: {
          'packages': [
            {
              'path': 'app',
              'entrypoints': [
                {
                  'path': 'lib/main.dart',
                  'name': 'Staging',
                  'knobs': [
                    {'define': 'API_BASE_URL', 'from': 'hostAddresses'},
                  ],
                },
              ],
            },
          ],
        },
      );

      var result = (await core.invoke('entrypoints'))! as RunEntrypointsResult;

      var package = result.packages.single;
      expect(package.declared, isTrue);
      // `lib/other.dart` has a main() and is not offered: naming two entry
      // points meant those two.
      expect(package.entrypoints.single.name, 'Staging');
      expect(package.entrypoints.single.knobs.single.define, 'API_BASE_URL');
    });

    test('a knob offers the servers that are running right now', () async {
      _writePackage(worktree, 'app', {'lib/main.dart': 'void main() {}'});
      File(p.join(runDir.path, 'srv-abc-api-42.json')).writeAsStringSync(
        jsonEncode({
          'projectRoot': worktree.path,
          'name': 'api',
          'socketPath': p.join(runDir.path, 'srv-abc-api-42.sock'),
          'pid': 42,
          'startedAt': DateTime.now().toUtc().toIso8601String(),
          'baseUrl': 'http://192.168.1.20:8080',
        }),
      );
      core = _coreFor(
        worktree,
        config: {
          'packages': [
            {
              'path': 'app',
              'entrypoints': [
                {
                  'path': 'lib/main.dart',
                  'knobs': [
                    {'define': 'API', 'from': 'servers', 'default': 'x'},
                  ],
                },
              ],
            },
          ],
        },
      );

      var result = (await core.invoke('entrypoints'))! as RunEntrypointsResult;

      var knob = result.packages.single.entrypoints.single.knobs.single;
      expect(knob.options, contains('http://192.168.1.20:8080'));
      expect(knob.defaultValue, 'x');
    });

    test('launching refuses a knob the entry point does not declare', () async {
      _writePackage(worktree, 'app', {'lib/main.dart': 'void main() {}'});
      core = _coreFor(
        worktree,
        config: {
          'packages': [
            {
              'path': 'app',
              'entrypoints': [
                {
                  'path': 'lib/main.dart',
                  'knobs': [
                    {'define': 'API'},
                  ],
                },
              ],
            },
          ],
        },
      );

      // A misspelled define compiles perfectly and does nothing — the app
      // reads its fallback and behaves as though nobody set anything.
      await expectLater(
        core.invoke(
          'launch',
          arguments: {'device': 'phone', 'knobs': 'APII=x'},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            contains('declares no such knob'),
          ),
        ),
      );
    });
  });

  group('the launcher log', () {
    test('reads the app id, the VM service and the outcome', () {
      var path = p.join(runDir.path, 'app-x.log');
      File(path).writeAsStringSync(
        [
          _event('app.start', {
            'appId': 'a1',
            'deviceId': 'phone',
            'directory': '/tmp/app',
            'supportsRestart': true,
            'launchMode': 'run',
          }),
          _event('app.progress', {
            'appId': 'a1',
            'id': '0',
            'progressId': 'launch',
            'message': 'Installing and launching…',
            'finished': false,
          }),
          _event('app.debugPort', {
            'appId': 'a1',
            'port': 4242,
            'wsUri': 'ws://127.0.0.1:4242/tok=/ws',
            'baseUri': 'http://127.0.0.1:4242/tok=/',
          }),
          _event('app.started', {'appId': 'a1'}),
        ].join('\n'),
      );

      var log = LaunchLog.read(path);

      expect(log.appId, 'a1');
      expect(log.vmService, 'ws://127.0.0.1:4242/tok=/ws');
      expect(log.progress, 'Installing and launching…');
      expect(log.started, isTrue);
      expect(log.summary, 'running');
    });

    test('a plain line is context, not a verdict', () {
      // `flutter run` opens with this, every time, before it has done anything
      // wrong. Treating it as a failure ended a wait on the first poll and
      // reported a launch as failed while it was still starting.
      var path = p.join(runDir.path, 'app-y.log');
      File(path).writeAsStringSync(
        'No devices found yet. Checking for wireless devices...\n',
      );

      var log = LaunchLog.read(path);

      expect(log.error, isNull);
      expect(log.output, startsWith('No devices found yet'));
      expect(log.failure(launcherAlive: true), isNull);
      // Once the launcher is gone it is the only account there is.
      expect(log.failure(launcherAlive: false), startsWith('No devices'));
    });

    test('a structured error is a verdict even while the launcher lives', () {
      var path = p.join(runDir.path, 'app-z.log');
      File(path).writeAsStringSync(
        _event('daemon.logMessage', {
          'level': 'error',
          'message': 'Gradle task assembleDebug failed',
        }),
      );

      var log = LaunchLog.read(path);

      expect(
        log.failure(launcherAlive: true),
        'Gradle task assembleDebug failed',
      );
    });

    test('two flavors of one entry point are two runs', () {
      // Not cosmetic: `dev` and `prod` install as different bundle ids and sit
      // on the phone together. One key would give them one handle and one log,
      // which is the collision that already published a dead VM service once.
      var base = runHandleKey(worktree.path, 'phone', 'lib/main.dart');
      var dev = runHandleKey(worktree.path, 'phone', 'lib/main.dart', 'dev');
      var prod = runHandleKey(worktree.path, 'phone', 'lib/main.dart', 'prod');

      expect(dev, isNot(prod));
      expect(dev, isNot(base));
      // A run with no flavor keeps the key it always had, so nothing written
      // before flavors existed is orphaned.
      expect(runHandleKey(worktree.path, 'phone', 'lib/main.dart', null), base);
    });

    test('a flavor survives the handle file and the label says it', () {
      var handle = _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        entrypointName: 'App',
        flavor: 'staging',
      );

      var read = scanRunHandles(runDir.path).single;
      expect(read.flavor, 'staging');
      expect(read.key, handle.key);
      expect(read.runLabel, 'App (staging)');
      // And a run without one is unchanged.
      expect(
        _writeHandle(
          runDir,
          worktree,
          device: 'sim',
          entrypoint: 'lib/main.dart',
          entrypointName: 'App',
        ).runLabel,
        'App',
      );
    });

    test('an iOS build failure reports its reason, not its last line', () {
      // Trimmed from a real log: `fw run run launch` on a cabled iPhone 16
      // against a project whose signing team has no account on this machine.
      // The tool emits **nothing structured** for any of it — no
      // `daemon.logMessage`, no error on `app.stop` — so the reason is only in
      // the plain lines, and the last of them is the one that says nothing.
      var path = p.join(runDir.path, 'app-ios.log');
      File(path).writeAsStringSync(
        [
          _event('app.start', {
            'appId': 'a1',
            'deviceId': '00008140-0011296E1E60801C',
            'directory': '/tmp/app',
            'launchMode': 'run',
          }),
          _event('app.progress', {
            'appId': 'a1',
            'id': '0',
            'message': 'Running Xcode build...',
            'finished': false,
          }),
          _event('app.progress', {'appId': 'a1', 'id': '0', 'finished': true}),
          'Xcode build done.                                            3.1s',
          'Failed to build iOS app',
          'Could not build the precompiled application for the device.',
          'Error (Xcode): No Account for Team "B7V224LKE4".',
          '/tmp/app/ios/Runner.xcodeproj',
          '',
          'Error: could not code sign the application.',
          '',
          'To resolve this issue, try the following steps:',
          '  1. Open the project in Xcode:',
          '     open ios/Runner.xcworkspace',
          "Error launching application on Xavier's iPhone16.",
          _event('app.stop', {'appId': 'a1'}),
          'App failed to start',
        ].join('\n'),
      );

      var log = LaunchLog.read(path);

      // Nothing structured said a word about it.
      expect(log.error, isNull);
      expect(log.stopped, isTrue);
      expect(log.started, isFalse);

      var failure = log.failure(launcherAlive: false)!;
      // The cause, which used to be dropped entirely.
      expect(failure, contains('No Account for Team "B7V224LKE4"'));
      expect(failure, contains('could not code sign the application'));
      // And the fix, which is the reason a block beats a line.
      expect(failure, contains('open ios/Runner.xcworkspace'));
      // The summary line is still there, just no longer the whole answer.
      expect(failure, contains('App failed to start'));
      // A row gets one line, and it is not the useless one.
      expect(log.failureHeadline, 'Failed to build iOS app');
    });

    test('app.stop does not clear the words printed after it', () {
      // The ordering that made this subtle: `app.stop` arrives *before* the
      // tool explains itself, so a rule of "a structured event ends the block"
      // applied to it would throw away the whole reason.
      var path = p.join(runDir.path, 'app-order.log');
      File(path).writeAsStringSync(
        [
          _event('app.stop', {'appId': 'a1'}),
          'Error: something went wrong afterwards',
        ].join('\n'),
      );

      expect(
        LaunchLog.read(path).failure(launcherAlive: false),
        contains('something went wrong afterwards'),
      );
    });

    test('a started run that later stops is not a failure', () {
      var path = p.join(runDir.path, 'app-stopped.log');
      File(path).writeAsStringSync(
        [
          _event('app.started', {'appId': 'a1'}),
          _event('app.stop', {'appId': 'a1'}),
          'Application finished.',
        ].join('\n'),
      );

      var log = LaunchLog.read(path);

      expect(log.started, isTrue);
      expect(log.failure(launcherAlive: false), isNull);
    });

    test('a half-written event line is a log that says less, not a crash', () {
      // Read while another process appends to it, so a torn line is normal.
      var path = p.join(runDir.path, 'app-torn.log');
      File(path).writeAsStringSync('[{"event":"app.st}]\nstill building\n');

      expect(LaunchLog.read(path).output, 'still building');
    });

    test('tops a handle up from its log and rewrites the file', () {
      var handle = _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        launcherPid: pid,
        logPath: p.join(runDir.path, 'app-w.log'),
      );
      File(handle.logPath!).writeAsStringSync(
        [
          _event('app.debugPort', {
            'appId': 'a9',
            'port': 1,
            'wsUri': 'ws://127.0.0.1:9/t=/ws',
            'baseUri': 'http://127.0.0.1:9/t=/',
          }),
        ].join('\n'),
      );

      var updated = refreshFromLog(handle);

      expect(updated.vmService, 'ws://127.0.0.1:9/t=/ws');
      expect(updated.appId, 'a9');
      // Rewritten, so the next process to read the ledger does not have to
      // parse the log again — and a process that never watched the launch can
      // still drive the app.
      expect(
        scanRunHandles(runDir.path).single.vmService,
        'ws://127.0.0.1:9/t=/ws',
      );
    });

    test('corrects a handle whose service address is stale', () {
      // The regression that made a relaunch look dead. The key is stable across
      // relaunch by design, so two runs of the same entry point on the same
      // device share one log file — and a handle written during the window
      // before the new launcher truncated it carries the *previous* run's URI.
      // `refreshFromLog` used to return early once the handle had both fields,
      // which made that wrong value permanent.
      var handle = _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        launcherPid: pid,
        logPath: p.join(runDir.path, 'app-w.log'),
        vmService: 'ws://127.0.0.1:1111/old=/ws',
        appId: 'previous',
      );
      File(handle.logPath!).writeAsStringSync(
        _event('app.debugPort', {
          'appId': 'current',
          'port': 2222,
          'wsUri': 'ws://127.0.0.1:2222/new=/ws',
          'baseUri': 'http://127.0.0.1:2222/new=/',
        }),
      );

      var updated = refreshFromLog(handle);

      expect(updated.vmService, 'ws://127.0.0.1:2222/new=/ws');
      expect(updated.appId, 'current');
      expect(
        scanRunHandles(runDir.path).single.vmService,
        'ws://127.0.0.1:2222/new=/ws',
      );
    });
  });

  group('control', () {
    // "I cannot tell what you meant" throws, the way a bad argument does
    // anywhere else; "I tried and it did not work" comes back as ok: false.
    // The difference is whether anything was attempted.
    test('says what is running when nothing is', () async {
      await expectLater(
        core.invoke('reload'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Nothing is running'),
          ),
        ),
      );
    });

    test('refuses to guess between two running apps', () async {
      for (var entrypoint in ['lib/a.dart', 'lib/b.dart']) {
        _writeHandle(
          runDir,
          worktree,
          device: 'phone',
          entrypoint: entrypoint,
          launcherPid: pid,
        );
      }

      await expectLater(
        core.invoke('restart'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('More than one app matches'),
          ),
        ),
      );
    });

    test('reports a reload it could not do rather than throwing', () async {
      // The app is unreachable, so the attempt is real and it fails. That is
      // an outcome, not a mistake by the caller.
      _writeHandle(
        runDir,
        worktree,
        device: 'phone',
        entrypoint: 'lib/main.dart',
        launcherPid: pid,
        vmService: 'ws://127.0.0.1:1/ws',
      );

      var result = (await core.invoke('reload'))! as RunControlResult;

      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });
  });
}

RunCore _coreFor(Directory worktree, {Map<String, Object?> config = const {}}) {
  var tree = Worktree(path: worktree.path, isMain: true);
  return RunCore(
    PluginHost(
      id: runPluginId,
      label: 'Run',
      worktree: tree,
      config: config,
      workspace: Workspace(
        root: tree.path,
        declared: [],
        discovered: [],
        appContext: AppContext(logger: LogClient.print()),
        flutterSdk: FlutterSdkPath('/tmp/flutter'),
      ),
    ),
  );
}

/// A package directory with [files] in it, keyed by package-relative path.
void _writePackage(Directory worktree, String path, Map<String, String> files) {
  for (var file in files.entries) {
    File(p.join(worktree.path, path, file.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(file.value);
  }
}

/// One `--machine` line, as the launcher writes them.
String _event(String name, Map<String, Object?> params) => jsonEncode([
  {'event': name, 'params': params},
]);

RunHandle _writeHandle(
  Directory runDir,
  Directory worktree, {
  required String device,
  required String entrypoint,
  String? logPath,
  String? entrypointName,
  String? worktreeName,
  String? vmService,
  String? appId,
  String? flavor,
  int launcherPid = 1,
  DateTime? startedAt,
}) {
  return RunHandle(
    worktree: worktree.path,
    worktreeName: worktreeName ?? '~',
    device: device,
    deviceName: device,
    entrypoint: entrypoint,
    entrypointName: entrypointName,
    flavor: flavor,
    launcherPid: launcherPid,
    vmService: vmService,
    appId: appId,
    logPath: logPath,
    startedAt: startedAt ?? DateTime.now(),
  ).publish(runDir.path);
}

/// A pid that is certainly gone: a process started and waited for.
///
/// Better than a large constant, which is only *probably* free and would make
/// the sweep tests flaky on whichever machine happened to be using it.
Future<int> _deadPid() async {
  var process = await Process.start('true', const []);
  await process.exitCode;
  return process.pid;
}
