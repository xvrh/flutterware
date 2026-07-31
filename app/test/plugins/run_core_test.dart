import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/run_core.dart';
import 'package:flutterware_app/src/plugins/native/run_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:flutterware_app/src/run/inventory.dart';
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
      expect([for (var c in report.children) c.id], ['phone', 'sim']);
      expect(report.children.first.status.message, contains('main.dart'));
      expect(report.children.last.status.message, 'free');
      // The dead handle is still on disk: computeAll may not open a socket, so
      // it cannot know the run is gone, and must not guess.
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
}

RunCore _coreFor(Directory worktree) {
  var tree = Worktree(path: worktree.path, isMain: true);
  return RunCore(
    PluginHost(
      id: runPluginId,
      label: 'Run',
      worktree: tree,
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

void _writeHandle(
  Directory runDir,
  Directory worktree, {
  required String device,
  required String entrypoint,
  String? entrypointName,
  String? worktreeName,
  String? vmService,
  int launcherPid = 1,
  DateTime? startedAt,
}) {
  var handle = RunHandle(
    worktree: worktree.path,
    worktreeName: worktreeName ?? '~',
    device: device,
    deviceName: device,
    entrypoint: entrypoint,
    entrypointName: entrypointName,
    launcherPid: launcherPid,
    vmService: vmService,
    startedAt: startedAt ?? DateTime.now(),
  );
  File(
    p.join(
      runDir.path,
      runHandleFileName(
        worktree: worktree.path,
        device: device,
        entrypoint: entrypoint,
        launcherPid: launcherPid,
      ),
    ),
  ).writeAsStringSync(jsonEncode(handle.toJson()));
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
