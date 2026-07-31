import 'dart:async';

import 'package:flutterware/plugins.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../run/handle.dart';
import '../../run/inventory.dart';
import '../../utils/daemon/device.dart';
import '../../utils/run_dir.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'run_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const runPluginId = 'flutterware.run';

/// Which devices exist, and which are already running something — from any
/// worktree of the repo, not just this one.
///
/// See `docs/superpowers/specs/2026-07-31-app-launcher-cockpit-brainstorm.md`;
/// this is the first slice of it, and it deliberately launches nothing.
///
/// Two sources, and the difference between them is the whole design:
///
/// - **Devices** come from a `flutter daemon`, which costs seconds to start
///   and answers about the machine. Whoever holds one publishes what it sees
///   to `devices.json`, and a cold `fw` reads that file **and says how old it
///   is**. A run is a fact that happened; it gets old, it does not become
///   wrong.
/// - **Occupancy** comes from the `app-*.json` handles in the run dir. Nobody
///   coordinates: a run announces itself in a file, anything that wants to
///   know connects to find out whether it is still there, and a handle nothing
///   answers is deleted by whoever noticed.
///
/// Holds to the [PluginCore.computeAll] budget: this class reads files and
/// nothing else until somebody either mounts the panel ([track]) or names an
/// action. Sockets and the daemon live behind both.
class RunCore extends PluginCore {
  RunCore(super.host);

  /// Where the ledger and the device cache live. A seam for tests, which point
  /// it at a temp dir rather than the developer's real run dir.
  @visibleForTesting
  static String Function() runDirProvider = flutterwareRunDir;

  DeviceCache? _cache;
  DeviceDaemon? _daemon;
  var _scanned = false;
  var _tracking = false;
  StreamSubscription<void>? _daemonChanges;
  Timer? _probeTimer;

  /// Handles as the last scan read them, and what the last probe found for
  /// each — keyed by handle path, which is what identifies a run on disk.
  List<RunHandle> _handles = const [];
  final _probes = <String, RunProbe>{};

  /// What to show: the live daemon's list when there is one, the cache
  /// otherwise. They are the same shape on purpose.
  List<DaemonDevice> get devices =>
      _daemon?.devices ?? _cache?.devices ?? const [];

  /// True when this process holds a daemon, so [devices] is a reading rather
  /// than a recollection.
  bool get isLive => _daemon != null;

  /// The runs currently announced, newest first — every worktree's, because a
  /// device held by another checkout is exactly the case this answers.
  List<RunHandle> get handles => _handles;

  RunProbe? probeOf(RunHandle handle) =>
      handle.handlePath == null ? null : _probes[handle.handlePath];

  @override
  Future<void> computeAll() async {
    _cache = DeviceCache.read(runDirProvider());
    _handles = scanRunHandles(runDirProvider());
    _scanned = true;
  }

  /// Starts the daemon and keeps probing the ledger. Idempotent; called by the
  /// panel on mount.
  ///
  /// Spawns a process, which [computeAll] may not — the panel being open is a
  /// caller who chose to pay for a live list.
  void track() {
    if (_tracking || isDisposed) return;
    _tracking = true;
    unawaited(computeAll().then((_) => notifyChanged()));
    unawaited(_startDaemon());
    unawaited(_probeAll());
    _probeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _handles = scanRunHandles(runDirProvider());
      unawaited(_probeAll());
    });
  }

  /// Takes this core's one lease on the shared daemon, starting it if nobody
  /// else has.
  ///
  /// One lease per core, however many times this is called: [track] and the
  /// `devices --refresh` action both want a daemon, and counting each of them
  /// would leave the process alive after the core that asked for it is gone.
  Future<DeviceDaemon> _acquireDaemon() async {
    var existing = _daemon;
    if (existing != null) return existing;
    var daemon = await DeviceDaemon.acquire(
      host.workspace.flutterSdk,
      runDir: runDirProvider(),
    );
    if (isDisposed || _daemon != null) {
      // Disposed while starting, or another call won the race — either way this
      // lease has no holder and must go back.
      daemon.release();
      return _daemon ?? daemon;
    }
    _daemon = daemon;
    _daemonError = null;
    return daemon;
  }

  Future<void> _startDaemon() async {
    try {
      var daemon = await _acquireDaemon();
      if (isDisposed) return;
      _daemonChanges = daemon.changes.listen((_) => notifyChanged());
      notifyChanged();
    } on Object catch (e) {
      if (isDisposed) return;
      _daemonError = '$e';
      notifyChanged();
    }
  }

  String? _daemonError;

  /// Probes every announced run and deletes the handles nothing answers.
  ///
  /// Returns how many were swept. A dead handle is one where neither the app
  /// nor its launcher is there — a live launcher with a silent app is a *cold
  /// build*, which on Android takes a minute and a half, and sweeping it would
  /// free a device that is very much in use.
  Future<int> _probeAll() async {
    var handles = _handles;
    var probes = await Future.wait([
      for (var handle in handles) probeRunHandle(handle),
    ]);
    if (isDisposed) return 0;
    var swept = 0;
    var alive = <RunHandle>[];
    for (var (index, handle) in handles.indexed) {
      var probe = probes[index];
      if (probe.isDead) {
        handle.delete();
        _probes.remove(handle.handlePath);
        swept++;
        continue;
      }
      if (handle.handlePath != null) _probes[handle.handlePath!] = probe;
      alive.add(handle);
    }
    _handles = alive;
    notifyChanged();
    return swept;
  }

  @override
  PluginReport get report {
    var devices = this.devices;
    var busy = _busyDeviceIds();
    return PluginReport(
      id: host.id,
      label: host.label,
      status: _status(devices, busy),
      badge: _daemonError != null
          ? const StatusBadge.dot(Tone.error)
          : busy.isNotEmpty
          ? StatusBadge.count(busy.length, tone: Tone.good)
          : StatusBadge.none,
      children: [
        for (var device in devices)
          PluginChild(
            id: device.id,
            label: device.displayName,
            status: _deviceStatus(device),
          ),
      ],
      actions: [
        PluginAction(
          'devices',
          'Devices',
          returns: RunDevicesResult,
          description:
              'Every device an app could run on, with what is already running '
              'on it and from which worktree. Reads a cached list and says how '
              'old it is; pass refresh to start a flutter daemon and take a '
              'fresh one, which costs a few seconds.',
          parameters: const [
            ActionParameter(
              'refresh',
              'Refresh',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  'Ask a live flutter daemon instead of reading the cache',
            ),
          ],
        ),
        PluginAction(
          'apps',
          'Running apps',
          returns: RunAppsResult,
          description:
              "Every app announcing itself under this machine's run "
              'directory, from any worktree, probed: whether the app still '
              'answers, whether the launcher that can hot-reload it is still '
              'alive, and where its log is. Handles nothing answers are '
              'deleted.',
        ),
      ],
      view: PluginView([
        if (_daemonError != null)
          ViewText(
            'Could not start a flutter daemon: $_daemonError',
            tone: Tone.error,
          ),
        if (!_scanned)
          ViewText('Not scanned yet.')
        else ...[
          ViewSection('Devices', [
            if (devices.isEmpty)
              ViewText(
                isLive
                    ? 'Nothing connected.'
                    : 'No device list has been taken yet. Run the devices '
                          'action with refresh, or open this panel.',
              )
            else
              ViewItems([
                for (var device in devices)
                  ViewItem(
                    device.displayName,
                    detail: _deviceDetail(device),
                    tone: busy.contains(device.id) ? Tone.info : Tone.neutral,
                  ),
              ]),
            if (!isLive && _cache != null)
              ViewField('Taken', _cache!.ageDescription),
          ]),
          ViewSection('Running', [
            if (_handles.isEmpty)
              ViewText('Nothing running.')
            else
              ViewItems([
                for (var handle in _handles)
                  ViewItem(
                    '${handle.entrypointLabel} on '
                    '${handle.deviceName ?? handle.device}',
                    detail: _handleDetail(handle),
                  ),
              ]),
          ]),
        ],
      ]),
    );
  }

  Status _status(List<DaemonDevice> devices, Set<String> busy) {
    if (_daemonError != null) return Status.error('no device list');
    if (!_scanned) return Status.none;
    if (devices.isEmpty) {
      return Status.neutral(isLive ? 'no devices' : 'no device list yet');
    }
    var count = '${devices.length} device${devices.length == 1 ? '' : 's'}';
    var freshness = isLive ? '' : ', ${_cache?.ageDescription ?? 'cached'}';
    if (busy.isEmpty) return Status.neutral('$count$freshness');
    return Status.good('$count, ${busy.length} busy$freshness');
  }

  Status _deviceStatus(DaemonDevice device) {
    var holders = _handles.where((h) => h.device == device.id).toList();
    if (!device.isConnected) return Status.warn('not connected');
    if (holders.isEmpty) return Status.neutral('free');
    var first = holders.first;
    var suffix = holders.length > 1 ? ' +${holders.length - 1}' : '';
    return Status.info(
      '${first.entrypointLabel} · ${first.worktreeName}$suffix',
    );
  }

  String _deviceDetail(DaemonDevice device) => [
    ?device.platformType,
    ?device.sdk,
    if (device.emulator) 'emulator',
    if (device.isWireless) 'wireless',
    if (!device.isConnected) 'not connected',
  ].join(' · ');

  String _handleDetail(RunHandle handle) {
    var probe = probeOf(handle);
    return [
      handle.worktreeName,
      if (probe == null)
        'not probed'
      else if (probe.canReload)
        'reloadable'
      else if (probe.canInspect)
        'no launcher'
      else
        'starting',
    ].join(' · ');
  }

  Set<String> _busyDeviceIds() => {for (var handle in _handles) handle.device};

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    return switch (actionId) {
      'devices' => _devicesAction(refresh: _boolArgument(arguments['refresh'])),
      'apps' => _appsAction(),
      _ => super.invoke(actionId, arguments: arguments),
    };
  }

  Future<RunDevicesResult> _devicesAction({required bool refresh}) async {
    if (refresh) {
      try {
        await (await _acquireDaemon()).refresh();
      } on Object catch (e) {
        _daemonError = '$e';
        return RunDevicesResult(
          devices: const [],
          live: false,
          note: 'Could not start a flutter daemon: $e',
        );
      }
    } else {
      _cache = DeviceCache.read(runDirProvider());
    }

    _handles = scanRunHandles(runDirProvider());
    await _probeAll();

    var devices = this.devices;
    var cache = _cache;
    return RunDevicesResult(
      live: isLive,
      updatedAt: isLive
          ? DateTime.now().toUtc().toIso8601String()
          : cache?.updatedAt.toUtc().toIso8601String(),
      age: isLive ? 'just now' : cache?.ageDescription,
      note: _devicesNote(devices, cache),
      devices: [
        for (var device in devices)
          RunDeviceEntry(
            id: device.id,
            name: device.displayName,
            platform: device.platformType,
            sdk: device.sdk,
            emulator: device.emulator,
            physical: device.ephemeral && !device.emulator,
            connected: device.isConnected,
            connection: device.connectionInterface,
            running: [
              for (var handle in _handles)
                if (handle.device == device.id) _holder(handle),
            ],
          ),
      ],
    );
  }

  /// An empty list has three different causes and they need three different
  /// next steps — nothing plugged in, nobody has looked yet, or the cache is
  /// stale and empty. An empty array with no note reads as the first.
  String? _devicesNote(List<DaemonDevice> devices, DeviceCache? cache) {
    if (devices.isNotEmpty) return null;
    if (isLive) return 'Nothing is connected.';
    if (cache == null) {
      return 'No device list has been taken on this machine yet. Pass refresh '
          'to start a flutter daemon and take one.';
    }
    return 'The cached list is empty, ${cache.ageDescription}. Pass refresh to '
        'take a fresh one.';
  }

  RunHolder _holder(RunHandle handle) {
    var probe = probeOf(handle);
    return RunHolder(
      worktree: handle.worktreeName,
      package: handle.package,
      entrypoint: handle.entrypoint,
      entrypointName: handle.entrypointName,
      since: handle.startedAt.toUtc().toIso8601String(),
      canReload: probe?.canReload ?? false,
      canInspect: probe?.canInspect ?? false,
    );
  }

  Future<RunAppsResult> _appsAction() async {
    _handles = scanRunHandles(runDirProvider());
    var swept = await _probeAll();
    var here = p.canonicalize(host.worktree.path);
    return RunAppsResult(
      swept: swept,
      note: _handles.isEmpty
          ? 'Nothing is running. This lists apps launched through flutterware, '
                'which announce themselves in ${runDirProvider()}.'
          : null,
      apps: [
        for (var handle in _handles)
          RunAppEntry(
            device: handle.device,
            deviceName: handle.deviceName,
            worktree: handle.worktreeName,
            mine: p.canonicalize(handle.worktree) == here,
            package: handle.package,
            entrypoint: handle.entrypoint,
            entrypointName: handle.entrypointName,
            knobs: handle.knobs,
            since: handle.startedAt.toUtc().toIso8601String(),
            app: probeOf(handle)?.app ?? false,
            launcher: probeOf(handle)?.launcher ?? false,
            vmService: handle.vmService,
            log: handle.logPath,
            error: probeOf(handle)?.error,
          ),
      ],
    );
  }

  static bool _boolArgument(Object? value) => switch (value) {
    bool b => b,
    String s => s == 'true',
    _ => false,
  };

  @override
  void dispose() {
    _probeTimer?.cancel();
    unawaited(_daemonChanges?.cancel());
    // Give the lease back rather than stopping the daemon: another open
    // worktree may still be holding it, and closing one tab must not cost the
    // others their device list. When this was the last holder — which is
    // always the case for `fw` — the daemon stops here, and it has to: the
    // child keeps the VM alive, so a CLI that leaked it would print its answer
    // and then never exit.
    _daemon?.release();
    _daemon = null;
    super.dispose();
  }
}

PluginCore runCoreFactory(PluginHost host) => RunCore(host);
