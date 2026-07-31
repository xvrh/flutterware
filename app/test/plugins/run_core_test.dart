import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/run_core.dart';
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
