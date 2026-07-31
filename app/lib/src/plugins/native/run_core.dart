import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
import 'package:flutterware/server.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../run/connection.dart';
import '../../run/entrypoints.dart';
import '../../run/handle.dart';
import '../../run/inspect.dart';
import '../../run/inventory.dart';
import '../../run/launch.dart';
import '../../run/logs.dart';
import '../../utils/daemon/device.dart';
import '../../utils/run_dir.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'run_results.dart';
import 'ui_catalog_core.dart' show UiCatalogCore;

/// The registered id — also what `tool/flutterware.dart` declares.
const runPluginId = 'flutterware.run';

/// How many dead runs to keep the reason for. Enough to cover a morning of
/// fighting one signing problem across two devices, and far short of a list
/// nobody reads.
const _maxRememberedFailures = 8;

/// Which devices exist, which are already running something — from any
/// worktree of the repo, not just this one — and launching an entry point onto
/// one.
///
/// See `docs/superpowers/specs/2026-07-31-app-launcher-cockpit-brainstorm.md`.
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
/// A launch is the third: a detached `flutter run --machine` whose output goes
/// to a log file beside its handle. Nobody waits on it, and the handle is a
/// *cache* of what the log says — so any process can bring one up to date and
/// then drive the app, whether or not it was there when the app started.
///
/// Holds to the [PluginCore.computeAll] budget: this class reads files and
/// nothing else until somebody either mounts the panel ([track]) or names an
/// action. Sockets, subprocesses and the daemon live behind both.
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

  /// What [handle]'s launcher log said at the last probe.
  ///
  /// Read on the probe loop rather than on demand, because a panel that read a
  /// file every time it built would read it sixty times a second while an
  /// animation ran.
  LaunchLog? logOf(RunHandle handle) =>
      handle.handlePath == null ? null : _logs[handle.handlePath];

  final _logs = <String, LaunchLog>{};

  /// True while any announced run has not come up yet — a build in flight.
  bool get isStarting => _handles.any(
    (handle) => handle.vmService == null && !(logOf(handle)?.stopped ?? false),
  );

  /// Declared packages, filtered to those the workspace knows about.
  late final List<String> packages = [
    for (var path in host.packagePaths)
      if (host.workspace.exists(path)) path,
  ];

  /// The entry points of [path]: what the config declared, or what a scan of
  /// its `lib/` found. Cached, because both are file reads and the report asks
  /// on every keystroke.
  List<EntrypointRef> entrypointsFor(String path) =>
      _entrypoints[path] ?? const [];

  final _entrypoints = <String, List<EntrypointRef>>{};

  /// True when [path]'s entry points came from `tool/flutterware.dart` rather
  /// than from scanning.
  bool isDeclared(String path) =>
      entrypointsFor(path).any((entry) => entry.declared);

  /// This machine's addresses on the local network — what a phone has to be
  /// told, since `localhost` on a phone is the phone.
  ///
  /// Cached from [computeAll] because a knob's offered values are built inside
  /// [report], which may not do I/O of any kind.
  List<String> get hostAddresses => _hostAddresses;
  var _hostAddresses = <String>[];

  @override
  Future<void> computeAll() async {
    _cache = DeviceCache.read(runDirProvider());
    _handles = scanRunHandles(runDirProvider());
    for (var path in packages) {
      var declared = declaredEntrypoints(_configFor(path));
      _entrypoints[path] = declared.isNotEmpty
          ? declared
          : scanEntrypoints(host.workspace.absolutePathOf(path));
    }
    _hostAddresses = await _readHostAddresses();
    _scanned = true;
  }

  Map<String, Object?> _configFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] == path) return config;
    }
    return const {};
  }

  /// The IPv4 addresses of this machine's real interfaces.
  ///
  /// A syscall rather than a socket, and it is here rather than behind an
  /// action because "which address can the phone reach me at" is the answer a
  /// knob has to offer *before* anybody presses anything.
  static Future<List<String>> _readHostAddresses() async {
    try {
      var interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      return [
        for (var interface in interfaces)
          for (var address in interface.addresses) address.address,
      ];
    } on Object {
      // No permission, no interfaces, an OS that refuses — none of it is worth
      // failing a report over. The knob simply offers less.
      return const [];
    }
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
    _scheduleProbe();
  }

  /// Polls fast while something is building and slowly otherwise.
  ///
  /// A cold build's only narration is the launcher's progress line, and five
  /// seconds between readings makes a ninety-second build look like a frozen
  /// panel. Once everything is up there is nothing to watch that closely.
  void _scheduleProbe() {
    if (isDisposed || !_tracking) return;
    _probeTimer?.cancel();
    _probeTimer = Timer(
      isStarting ? const Duration(seconds: 1) : const Duration(seconds: 5),
      () {
        _handles = scanRunHandles(runDirProvider());
        unawaited(_probeAll().then((_) => _scheduleProbe()));
      },
    );
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

  final _failures = <String, RunFailure>{};

  /// Runs that ended before they started, newest first.
  ///
  /// Keyed by [runHandleKey] and replaced rather than accumulated, because that
  /// key is stable across relaunch: trying the same thing again should correct
  /// the reason it failed, not stack a second copy of it underneath.
  List<RunFailure> get failures {
    var all = _failures.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    return all;
  }

  RunFailure? failureFor(String key) => _failures[key];

  /// Notes why a run is gone, so the panel has something to show where the
  /// chip used to be. See [RunFailure] for why the handle cannot simply stay.
  @visibleForTesting
  void recordFailure(RunHandle handle, LaunchLog log) {
    if (_failures.length >= _maxRememberedFailures &&
        !_failures.containsKey(handle.key)) {
      var oldest = failures.last;
      _failures.remove(oldest.key);
    }
    _failures[handle.key] = RunFailure(
      key: handle.key,
      device: handle.device,
      deviceName: handle.deviceName,
      entrypoint: handle.entrypoint,
      entrypointName: handle.entrypointName,
      package: handle.package,
      flavor: handle.flavor,
      headline: log.failureHeadline,
      detail: log.failure(launcherAlive: false),
      logPath: handle.logPath,
      at: DateTime.now(),
    );
  }

  /// Forgets a failure, for when the panel's user has read it.
  void dismissFailure(String key) {
    if (_failures.remove(key) != null) notifyChanged();
  }

  /// Probes every announced run and deletes the handles nothing answers.
  ///
  /// Returns how many were swept. A dead handle is one where neither the app
  /// nor its launcher is there — a live launcher with a silent app is a *cold
  /// build*, which on Android takes a minute and a half, and sweeping it would
  /// free a device that is very much in use.
  Future<int> _probeAll() async {
    // Top each handle up from its launcher's log first. The log is the source
    // of truth about a run and the handle is a cache of it, so a run launched
    // by somebody else — another `fw`, a GUI that has since closed — becomes
    // connectable here without this process ever having watched it start.
    var handles = [for (var handle in _handles) refreshFromLog(handle)];
    _handles = handles;
    var probes = await Future.wait([
      for (var handle in handles) probeRunHandle(handle),
    ]);
    if (isDisposed) return 0;
    var swept = 0;
    var alive = <RunHandle>[];
    for (var (index, handle) in handles.indexed) {
      var probe = probes[index];
      if (probe.isDead) {
        // Read before deleting, and only for a run that never started: an app
        // that ran and was stopped is not a failure and must leave nothing
        // behind, or every ordinary `stop` would post an obituary.
        var log = LaunchLog.read(handle.logPath ?? '');
        if (!log.started) recordFailure(handle, log);
        handle.delete();
        _probes.remove(handle.handlePath);
        _logs.remove(handle.handlePath);
        swept++;
        continue;
      }
      if (handle.handlePath != null) {
        _probes[handle.handlePath!] = probe;
        if (handle.logPath case var path?) {
          _logs[handle.handlePath!] = LaunchLog.read(path);
        }
      }
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
      // **Runs, not devices.** A child's id becomes the first address segment
      // (`_childAddress`), so these have to be the things the panel can be
      // pointed at — and since the rebuild the panel's subjects are runs. A
      // device list in the rail would have been a row of links to nowhere.
      //
      // Devices have not gone anywhere: they are the desk, which the panel
      // renders when nothing is running and which belongs in the shell's
      // chrome. The status line below still counts them.
      children: [
        for (var handle in _handles)
          PluginChild(
            id: handle.key,
            label: '${handle.entrypointLabel} · ${handle.deviceLabel}',
            status: _handleStatus(handle),
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
        PluginAction(
          'entrypoints',
          'Entry points',
          returns: RunEntrypointsResult,
          description:
              'The main() files each package can be launched from, with the '
              'dart-defines each one declares and the values worth offering '
              'for them. Declared in tool/flutterware.dart when the project '
              'says so, found by scanning lib/ when it does not.',
          parameters: [_packageParameter],
        ),
        PluginAction(
          'launch',
          'Launch',
          returns: RunLaunchResult,
          description:
              'Builds an entry point and runs it on a device. The launcher is '
              'detached and its output goes to a log file, so this can return '
              'while the app keeps running. A cold build is slow — about ten '
              'seconds warm on Android and a minute and a half cold — and on a '
              'wireless device it can stall on an OS permission dialog that '
              'nobody is looking at.',
          parameters: [
            ActionParameter(
              'device',
              'Device',
              kind: ActionParameterKind.choice,
              description: 'Which device to run on',
              options: [
                for (var device in devices)
                  ActionOption(device.id, label: device.displayName),
              ],
            ),
            _packageParameter,
            ActionParameter(
              'entrypoint',
              'Entry point',
              kind: ActionParameterKind.choice,
              required: false,
              description:
                  'Package-relative path, as `entrypoints` reports it. The '
                  "package's only entry point when omitted.",
              options: [
                for (var path in packages)
                  for (var entry in entrypointsFor(path))
                    ActionOption(entry.path, label: entry.name),
              ],
            ),
            const ActionParameter(
              'flavor',
              'Flavor',
              required: false,
              description:
                  'The `--flavor` to build. Defaults to what the entry point '
                  'declares. A project with product flavors cannot be built '
                  'without one at all — unlike a knob, leaving it out is a '
                  'build failure rather than a default value.',
            ),
            const ActionParameter(
              'knobs',
              'Knobs',
              required: false,
              description:
                  'Launch knobs to bake in: `NAME=value,NAME=value`, or a '
                  'JSON object. Each becomes a `--dart-define`, so changing '
                  'one costs a rebuild — which is why the entry point declares '
                  'which ones it wants and what values are worth using.',
            ),
            const ActionParameter(
              'wait',
              'Wait',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'true',
              description:
                  'Wait for the app to come up before answering. Off returns '
                  'as soon as the launcher is spawned, and `apps` is how you '
                  'find out how it went.',
            ),
            const ActionParameter(
              'timeout',
              'Timeout',
              kind: ActionParameterKind.integer,
              required: false,
              defaultValue: '300',
              description:
                  'Seconds to wait. A timeout is not a failure — the build '
                  'carries on and the answer says how far it got.',
            ),
          ],
        ),
        PluginAction(
          'reload',
          'Hot reload',
          returns: RunControlResult,
          description:
              'Applies edited sources to a running app, in a few hundred '
              'milliseconds. Needs the `flutter run` that launched it to still '
              'be alive: hot reload is registered by the tool, not by the app, '
              'so it goes away with it while the app keeps running.',
          parameters: _appSelector,
        ),
        PluginAction(
          'restart',
          'Hot restart',
          returns: RunControlResult,
          description:
              'Restarts a running app from its main(), in about a second, '
              'without rebuilding or reinstalling. Same requirement as reload: '
              'the launcher has to be alive.',
          parameters: _appSelector,
        ),
        PluginAction(
          'stop',
          'Stop',
          returns: RunControlResult,
          danger: true,
          description:
              'Asks a running app to exit, kills its launcher, and frees the '
              'device. Asking the app first matters: killing only the launcher '
              'leaves the app running on the phone.',
          parameters: _appSelector,
        ),
        PluginAction(
          'inspect',
          'Inspect',
          returns: RunInspectResult,
          description:
              'One reading of a running app — whether it is up, whether it can '
              'still be reloaded, and whatever you ask about it: its widget '
              'tree, a picture, what it printed. With no flags it answers the '
              'question worth asking first, whether anything has gone wrong. '
              'Everything else is opt-in and every flag you add is answered '
              'from the **same** connection, and the tree and the picture from '
              'the same reading — two calls against a live app are two moments '
              'that only happen to agree. Answers even while the app is still '
              'building, when the logs are the only thing there is to read.',
          parameters: [
            ..._appSelector,
            const ActionParameter(
              'tree',
              'Widget tree',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  'Report the widget tree, with the file, line and column '
                  'each widget was constructed at. Off by default because a '
                  'real app is thousands of tokens of tree.',
            ),
            const ActionParameter(
              'full',
              'Full tree',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  "Include the framework's own widgets, not just yours. "
                  'Large: a one-screen app is 25 summary nodes and about 517 '
                  'full ones, six megabytes of them.',
            ),
            const ActionParameter(
              'screenshot',
              'Screenshot',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  'Write a PNG of the same reading everything else comes from, '
                  'and hand back its path. Rendered by the app rather than '
                  'grabbed from the device, so it works on hardware that '
                  'cannot be asked for a screen grab — and platform views '
                  '(native maps, webviews, video) will not appear.',
            ),
            const ActionParameter(
              'out',
              'Output path',
              required: false,
              description:
                  "Where to write the PNG. A file beside the run's log when "
                  'omitted, overwritten on each call.',
            ),
            const ActionParameter(
              'logs',
              'What it printed',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  "Report the run's output. Read from the launcher's log file "
                  'rather than from the app, so it covers the build and '
                  'survives a crash.',
            ),
            const ActionParameter(
              'source',
              'Log source',
              kind: ActionParameterKind.choice,
              required: false,
              description:
                  "Whose lines: the app's own output, or `flutter run` talking "
                  'about the build. Both when omitted.',
              options: [
                ActionOption('app', label: 'The app'),
                ActionOption('tool', label: 'flutter run'),
              ],
            ),
            const ActionParameter(
              'lines',
              'Lines',
              kind: ActionParameterKind.integer,
              required: false,
              defaultValue: '200',
              description: 'How many of the most recent lines to return',
            ),
            const ActionParameter(
              'errors',
              'What broke',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'true',
              description:
                  'Report the lines the launcher marked as errors — never '
                  'guessed from the text. On by default, and with no other '
                  'flag it is the whole answer.',
            ),
          ],
        ),
        PluginAction(
          'emulators',
          'Emulators',
          returns: RunEmulatorsResult,
          description:
              'Every emulator and simulator this machine could boot, and '
              'whether each is already up. Different from devices, which only '
              'lists the ones that are: an emulator that is not running is not '
              'a device. Costs a few seconds — it starts a flutter daemon.',
        ),
        PluginAction(
          'bootEmulator',
          'Boot an emulator',
          returns: RunBootResult,
          description:
              'Starts an emulator and waits for it to appear as a device, '
              'which is well after the boot command returns. A cold Android '
              'emulator can take over a minute; running out of the wait is '
              'not a failure and the answer says so.',
          parameters: const [
            ActionParameter(
              'emulator',
              'Emulator',
              description: 'The id `emulators` reports',
            ),
            ActionParameter(
              'coldBoot',
              'Cold boot',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  'Skip the saved snapshot. Slower, and the answer to an '
                  'emulator that boots into a broken state.',
            ),
            ActionParameter(
              'timeout',
              'Timeout',
              kind: ActionParameterKind.integer,
              required: false,
              defaultValue: '120',
              description: 'Seconds to wait for it to become a device',
            ),
          ],
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

  /// What a run says about itself in the rail — capability, not liveness.
  ///
  /// The same distinction the panel header makes: an app whose launcher died
  /// keeps its tree and its screenshots and loses hot reload, and a row saying
  /// only "running" would hide it.
  Status _handleStatus(RunHandle handle) {
    var probe = probeOf(handle);
    var mine = handle.worktreeName == host.worktree.name;
    var where = mine ? '' : ' · ${handle.worktreeName}';
    if (probe == null) return Status.neutral('not probed$where');
    if (!probe.canInspect) {
      return Status.neutral('${logOf(handle)?.progress ?? 'building'}$where');
    }
    if (!probe.launcher) return Status.warn('no launcher$where');
    return Status.good('live$where');
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

  ActionParameter get _packageParameter => ActionParameter(
    'package',
    'Package',
    kind: ActionParameterKind.choice,
    required: false,
    description: 'Which declared package; the only one when there is one',
    options: [
      for (var path in packages)
        ActionOption(path, label: path == '.' ? 'root' : path),
    ],
  );

  /// Which running app a control action acts on.
  ///
  /// The device is the key because a device usually runs one app, and naming
  /// the entry point as well is only needed when it does not. Both optional:
  /// with exactly one app running there is nothing to disambiguate, and making
  /// the caller say so anyway is ceremony.
  List<ActionParameter> get _appSelector => [
    ActionParameter(
      'device',
      'Device',
      kind: ActionParameterKind.choice,
      required: false,
      description:
          'Which device the app is on; the only running app when omitted',
      options: [
        for (var device in devices)
          ActionOption(device.id, label: device.displayName),
      ],
    ),
    const ActionParameter(
      'entrypoint',
      'Entry point',
      required: false,
      description:
          'Package-relative path, when one device is running more than one',
    ),
  ];

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    return switch (actionId) {
      'devices' => _devicesAction(refresh: _boolArgument(arguments['refresh'])),
      'apps' => _appsAction(),
      'entrypoints' => _entrypointsAction(arguments['package'] as String?),
      'launch' => _launchAction(arguments),
      'reload' => _controlAction('reload', arguments),
      'restart' => _controlAction('restart', arguments),
      'stop' => _controlAction('stop', arguments),
      'inspect' => _inspectAction(arguments),
      'screenshot' => _screenshotAction(arguments),
      'emulators' => _emulatorsAction(),
      'bootEmulator' => _bootEmulatorAction(arguments),
      _ => super.invoke(actionId, arguments: arguments),
    };
  }

  Future<RunEntrypointsResult> _entrypointsAction(String? package) async {
    await computeAll();
    var wanted = package == null
        ? packages
        : [
            for (var path in packages)
              if (path == package) path,
          ];
    if (wanted.isEmpty) {
      return RunEntrypointsResult(
        packages: const [],
        note: package == null
            ? 'No packages are declared for this plugin. Add them in '
                  'tool/flutterware.dart: fw.use(Run(packages: [...])).'
            : 'No declared package at "$package".',
      );
    }
    return RunEntrypointsResult(
      packages: [
        for (var path in wanted)
          RunEntrypointPackage(
            path: path,
            declared: isDeclared(path),
            entrypoints: [
              for (var entry in entrypointsFor(path))
                RunEntrypointEntry(
                  path: entry.path,
                  name: entry.name,
                  description: entry.description,
                  flavor: entry.flavor,
                  knobs: [for (var knob in entry.knobs) _knobEntry(knob)],
                ),
            ],
          ),
      ],
      note: wanted.every((path) => entrypointsFor(path).isEmpty)
          ? 'Nothing found. Entry points are declared in tool/flutterware.dart '
                'or discovered as a top-level main() in lib/*.dart.'
          : null,
    );
  }

  /// Everything worth offering for [knob] — the config's own list plus
  /// whatever its `from:` points at right now.
  ///
  /// This is what makes "inject the local server's address" a choice rather
  /// than something to go and look up: the running servers and this machine's
  /// LAN addresses are both things the tool already knows. Public because the
  /// panel's dialog and the `entrypoints` action must offer the same values —
  /// a list only one surface had would be a capability the others could not
  /// see.
  List<String> optionsFor(LaunchKnob knob) {
    var options = [...knob.options];
    switch (knob.from) {
      case KnobSource.servers:
        for (var handle in scanServerHandles(runDirProvider())) {
          var url = handle.baseUrl;
          if (url != null && !options.contains(url)) options.add(url);
        }
      case KnobSource.hostAddresses:
        for (var address in hostAddresses) {
          if (!options.contains(address)) options.add(address);
        }
      case null:
        break;
    }
    return options;
  }

  RunKnobEntry _knobEntry(LaunchKnob knob) => RunKnobEntry(
    define: knob.define,
    label: knob.label,
    description: knob.description,
    defaultValue: knob.defaultValue,
    options: optionsFor(knob),
  );

  Future<RunLaunchResult> _launchAction(Map<String, Object?> arguments) async {
    await computeAll();
    var device = arguments['device'] as String?;
    if (device == null) {
      throw ArgumentError.value(device, 'device', 'which device to run on');
    }
    var (package, entry) = _resolveEntrypoint(
      arguments['package'] as String?,
      arguments['entrypoint'] as String?,
    );
    var knobs = _resolveKnobs(
      entry,
      UiCatalogCore.parseKnobs(arguments['knobs']),
    );

    var handle = await launch(
      device: device,
      package: package,
      entry: entry,
      // The caller's word beats the declaration, and an empty string is how a
      // caller says "no flavor" about an entry point that declares one.
      flavor: switch (arguments['flavor']) {
        String given => given.isEmpty ? null : given,
        _ => entry.flavor,
      },
      knobs: knobs,
    );

    var wait = _boolArgument(arguments['wait'] ?? true);
    var log = LaunchLog.read(handle.logPath ?? '');
    if (wait) {
      var timeout = Duration(seconds: _intArgument(arguments['timeout'], 300));
      (handle, log) = await awaitLaunch(handle, timeout);
    }
    _handles = scanRunHandles(runDirProvider());
    await _probeAll();

    var probe = probeOf(handle) ?? await probeRunHandle(handle);
    var failure = log.failure(launcherAlive: probe.launcher);
    var status = switch (log) {
      // A run that stopped without ever starting did not stop, it failed —
      // and saying `stopped` for it was how an iOS build that could not be
      // signed came back looking like something somebody had turned off.
      _ when failure != null || (log.stopped && !log.started) => 'failed',
      _ when log.stopped => 'stopped',
      _ when log.started => 'running',
      _ => 'starting',
    };
    if (status == 'failed') {
      // A launcher that never came up is not holding the device, and leaving
      // its handle behind would make the next person's `devices` say a phone
      // is busy running something that is not there. The log stays: it is
      // where the reason is, and [logPath] below is what points at it.
      recordFailure(handle, log);
      handle.delete();
      _handles = scanRunHandles(runDirProvider());
    }
    return RunLaunchResult(
      status: status,
      waited: wait,
      progress: log.progress,
      error:
          failure ?? (status == 'failed' ? 'the app stopped starting' : null),
      headline: status == 'failed' ? log.failureHeadline : null,
      logPath: status == 'failed' ? handle.logPath : null,
      note: status == 'starting' && wait
          ? 'Still building after the timeout. It has not failed — follow it '
                'with the apps action, or read ${handle.logPath}.'
          : null,
      app: _appEntry(handle, probe),
    );
  }

  /// Starts a run. The panel's entry point too — a button that could only be
  /// reached through `invoke` would be behaviour the other surfaces could not
  /// see.
  Future<RunHandle> launch({
    required String device,
    required String package,
    required EntrypointRef entry,
    String? flavor,
    Map<String, String> knobs = const {},
  }) async {
    var deviceName = devices
        .where((candidate) => candidate.id == device)
        .map((candidate) => candidate.displayName)
        .firstOrNull;
    var handle = await launchApp(
      sdk: host.workspace.flutterSdk,
      runDir: runDirProvider(),
      worktree: host.worktree.path,
      worktreeName: host.worktree.name,
      packageRoot: host.workspace.absolutePathOf(package),
      package: package,
      device: device,
      deviceName: deviceName,
      entrypoint: entry.path,
      entrypointName: entry.declared ? entry.name : null,
      flavor: flavor ?? entry.flavor,
      knobs: knobs,
    );
    _handles = [handle, ..._handles];
    notifyChanged();
    return handle;
  }

  /// The package and entry point a launch means, or an [ArgumentError] naming
  /// what it could have meant.
  (String, EntrypointRef) _resolveEntrypoint(String? package, String? path) {
    var candidates = package == null
        ? packages
        : [
            for (var candidate in packages)
              if (candidate == package) candidate,
          ];
    if (candidates.isEmpty) {
      throw ArgumentError.value(
        package,
        'package',
        'not a declared package; declared: ${packages.join(', ')}',
      );
    }
    var matches = [
      for (var candidate in candidates)
        for (var entry in entrypointsFor(candidate))
          if (path == null || entry.path == path || entry.name == path)
            (candidate, entry),
    ];
    if (matches.isEmpty) {
      throw ArgumentError.value(
        path,
        'entrypoint',
        'no such entry point; known: ${[for (var candidate in candidates)
          for (var entry in entrypointsFor(candidate)) entry.path].join(', ')}',
      );
    }
    if (matches.length > 1) {
      throw ArgumentError.value(
        path,
        'entrypoint',
        'ambiguous; name one of: ${[for (var (_, entry) in matches) entry.path].join(', ')}',
      );
    }
    return matches.single;
  }

  /// The knobs a launch will bake in: what the caller gave, over the declared
  /// defaults, with anything the entry point did not declare refused.
  ///
  /// Refused rather than passed through, because a misspelled define compiles
  /// perfectly and does nothing — the app reads the fallback and behaves as if
  /// nobody set anything, which is a very long way from a legible failure.
  Map<String, String> _resolveKnobs(
    EntrypointRef entry,
    Map<String, String> given,
  ) {
    var declared = {for (var knob in entry.knobs) knob.define: knob};
    if (declared.isNotEmpty) {
      for (var name in given.keys) {
        if (!declared.containsKey(name)) {
          throw ArgumentError.value(
            name,
            'knobs',
            '${entry.name} declares no such knob; it declares '
                '${declared.keys.join(', ')}',
          );
        }
      }
    }
    return {
      for (var knob in entry.knobs) knob.define: ?knob.defaultValue,
      ...given,
    };
  }

  Future<RunControlResult> _controlAction(
    String action,
    Map<String, Object?> arguments,
  ) async {
    _handles = scanRunHandles(runDirProvider());
    await _probeAll();
    var handle = _selectApp(
      arguments['device'] as String?,
      arguments['entrypoint'] as String?,
    );
    var started = DateTime.now();
    try {
      await control(action, handle);
      return RunControlResult(
        action: action,
        device: handle.device,
        entrypoint: handle.entrypoint,
        ok: true,
        ms: DateTime.now().difference(started).inMilliseconds,
      );
    } on Object catch (e) {
      return RunControlResult(
        action: action,
        device: handle.device,
        entrypoint: handle.entrypoint,
        ok: false,
        ms: DateTime.now().difference(started).inMilliseconds,
        error: '$e',
      );
    }
  }

  /// Does one thing to one running app. The panel's entry point as well.
  Future<void> control(String action, RunHandle handle) async {
    var uri = handle.vmService;
    if (uri == null && action != 'stop') {
      throw StateError(
        '${handle.entrypointLabel} has no VM service yet — it is still '
        'building. Watch ${handle.logPath}.',
      );
    }
    RunConnection? connection;
    try {
      if (uri != null) {
        connection = await RunConnection.connect(
          uri,
          // Stopping needs no registration at all — `ext.flutter.exit` is the
          // app's own — so it should not wait for one.
          waitFor: switch (action) {
            'reload' => const {'reloadSources'},
            'restart' => const {'hotRestart'},
            _ => const {},
          },
        );
      }
      switch (action) {
        case 'reload':
          await connection!.reload();
        case 'restart':
          await connection!.restart();
        case 'stop':
          // The app first, then its launcher. The other order leaves an
          // orphaned app running on the phone with nothing able to reload it,
          // which is the worst of both.
          await connection?.exitApp();
          if (isProcessAlive(handle.launcherPid)) {
            Process.killPid(handle.launcherPid, ProcessSignal.sigterm);
          }
          handle.delete();
          _handles = [
            for (var other in _handles)
              if (other.handlePath != handle.handlePath) other,
          ];
        default:
          throw ArgumentError.value(action, 'action', 'unknown');
      }
    } finally {
      unawaited(connection?.close());
      notifyChanged();
    }
  }

  /// The one running app a control action means.
  /// What the desk can offer to boot. Empty until [loadEmulators] has run.
  List<DaemonEmulator> get emulators => _daemon?.emulators ?? const [];

  /// Asks the daemon what it could boot, for the desk.
  ///
  /// Separate from [track] because it is a second round trip nobody needs to
  /// open the panel, and the desk only shows when nothing is running.
  Future<void> loadEmulators() async {
    var daemon = await _acquireDaemon();
    await daemon.refreshEmulators();
    if (!isDisposed) notifyChanged();
  }

  /// Boots one. The panel's entry point, and `bootEmulator`'s.
  Future<DaemonDevice?> bootEmulator(String id, {bool coldBoot = false}) async {
    var daemon = await _acquireDaemon();
    return daemon.launchEmulator(id, coldBoot: coldBoot);
  }

  /// Everything bootable, and whether it is already up.
  ///
  /// Costs a daemon — seconds — which is why it is its own action rather than
  /// part of `devices`: most callers want the desk, not the garage.
  Future<RunEmulatorsResult> _emulatorsAction() async {
    var daemon = await _acquireDaemon();
    var emulators = await daemon.refreshEmulators();
    return RunEmulatorsResult(
      emulators: [
        for (var emulator in emulators)
          RunEmulatorEntry(
            id: emulator.id,
            name: emulator.displayName,
            platform: emulator.platformType,
            booted: isEmulatorBooted(emulator, daemon.devices),
          ),
      ],
      note: emulators.isEmpty
          ? 'Nothing to boot. Android emulators come from the AVD manager and '
                'iOS simulators from Xcode.'
          : emulators.any((e) => e.platformType == 'ios')
          ? 'The iOS row opens the Simulator rather than naming one device, so '
                'it cannot say whether anything is booted. `devices` lists what '
                'actually is.'
          : null,
    );
  }

  Future<RunBootResult> _bootEmulatorAction(
    Map<String, Object?> arguments,
  ) async {
    var id = arguments['emulator'] as String?;
    if (id == null || id.isEmpty) {
      throw ArgumentError.value(id, 'emulator', 'Name one to boot');
    }
    var daemon = await _acquireDaemon();
    var started = DateTime.now();
    var device = await daemon.launchEmulator(
      id,
      coldBoot: _boolArgument(arguments['coldBoot']),
      timeout: Duration(seconds: _intArgument(arguments['timeout'], 120)),
    );
    return RunBootResult(
      emulator: id,
      started: true,
      device: device?.id,
      deviceName: device?.displayName,
      ms: DateTime.now().difference(started).inMilliseconds,
      note: device == null
          ? 'Started, but it had not appeared as a device before the wait ran '
                'out. It is probably still booting — check `devices`.'
          : null,
    );
  }

  /// Refreshes the ledger and picks the one app the arguments name.
  ///
  /// The same opening as [_controlAction]: a handle is a cache of its
  /// launcher's log, so topping it up is what lets a run started by somebody
  /// else — another `fw`, a GUI that has since closed — be read here.
  Future<RunHandle> _selectRunningApp(Map<String, Object?> arguments) async {
    _handles = scanRunHandles(runDirProvider());
    await _probeAll();
    return _selectApp(
      arguments['device'] as String?,
      arguments['entrypoint'] as String?,
    );
  }

  /// What the last launch from this panel chose.
  ///
  /// Held here rather than in the page's state so it survives the page being
  /// closed and reopened, which is the whole point: running the same thing
  /// again should be opening the page and pressing Start. Deliberately not
  /// persisted to disk — "what I ran a minute ago" is a fact about this
  /// session, and restoring it from last week would be a worse guess than the
  /// first device in the list.
  ({
    String device,
    String package,
    String entrypoint,
    String? flavor,
    Map<String, String> knobs,
  })?
  lastLaunch;

  /// The picture and the widget tree of one run, from **one** reading.
  ///
  /// What the panel's Screen tab calls, and the reason `inspect` was merged
  /// into one action: the two are shown side by side, so they have to be the
  /// same frame. Two calls would be two moments, and a live app animates,
  /// fires timers and takes in data between them — the tree would describe a
  /// screen the picture no longer shows.
  Future<InspectRead> inspectRead(
    RunHandle handle, {
    bool tree = true,
    bool screenshot = true,
    bool summary = true,
  }) => _withInspector(
    handle,
    (i) => i.read(tree: tree, screenshot: screenshot, summary: summary),
  );

  /// The widget tree of one run, on its own.
  Future<InspectTree> inspectTree(RunHandle handle, {bool summary = true}) =>
      _withInspector(handle, (i) => i.tree(summary: summary));

  /// A picture of one run.
  Future<Uint8List> screenshot(RunHandle handle, {int? maxSide}) =>
      _withInspector(handle, (i) => i.screenshot(maxSide: maxSide));

  /// One run's log, read from the file rather than the app — so it works while
  /// the app is still building and after it has died.
  List<RunLogLine> readLogs(
    RunHandle handle, {
    RunLogSource? only,
    bool errorsOnly = false,
    int? tail,
  }) {
    var path = handle.logPath;
    if (path == null) return const [];
    return readRunLog(path, only: only, errorsOnly: errorsOnly, tail: tail);
  }

  /// Opens a connection for reading rather than for driving.
  ///
  /// **Waits for no registration, and that is the point.** Reload and restart
  /// have to wait for the `flutter run` to register them; the inspector is the
  /// *app's* own and exists the moment its isolate does. So everything built on
  /// this keeps working on a run whose launcher has died — the surviving half
  /// of the two-tier split.
  Future<T> _withInspector<T>(
    RunHandle handle,
    Future<T> Function(RunInspector inspector) body,
  ) async {
    var uri = handle.vmService;
    if (uri == null) {
      throw StateError(
        '${handle.entrypointLabel} has no VM service yet — it is still '
        'building. Watch ${handle.logPath}.',
      );
    }
    var connection = await RunConnection.connect(uri);
    try {
      return await body(RunInspector(connection));
    } finally {
      await connection.close();
    }
  }

  /// One file per run, overwritten. A screenshot is an observation of a
  /// moment, and keeping every one would fill the run dir with pictures nobody
  /// asked to keep; a caller that wants to keep one says where.
  ///
  /// `runHandleKey` already carries the `app-` stem the handle and the log
  /// share, so the picture joins them rather than starting a third naming
  /// scheme.
  String _screenshotPathFor(RunHandle handle, Object? given) =>
      given is String && given.isNotEmpty
      ? given
      : p.join(
          runDirProvider(),
          '${runHandleKey(handle.worktree, handle.device, handle.entrypoint)}.png',
        );

  Future<RunScreenshotResult> _screenshotAction(
    Map<String, Object?> arguments,
  ) async {
    var handle = await _selectRunningApp(arguments);
    var out = _screenshotPathFor(handle, arguments['out']);
    var maxSide = switch (arguments['maxSide']) {
      null => null,
      var value => _intArgument(value, 0),
    };
    var started = DateTime.now();
    var bytes = await _withInspector(
      handle,
      (i) => i.screenshot(
        maxSide: maxSide == null || maxSide <= 0 ? null : maxSide,
      ),
    );
    var file = File(out);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return RunScreenshotResult(
      device: handle.device,
      entrypoint: handle.entrypoint,
      path: file.absolute.path,
      bytes: bytes.length,
      ms: DateTime.now().difference(started).inMilliseconds,
    );
  }

  Future<RunInspectResult> _inspectAction(
    Map<String, Object?> arguments,
  ) async {
    var handle = await _selectRunningApp(arguments);
    var probe = probeOf(handle);
    var log = logOf(handle);
    var mine = handle.worktreeName == host.worktree.name;
    var wantsTree = _boolArgument(arguments['tree']);
    var full = _boolArgument(arguments['full']);
    var wantsShot = _boolArgument(arguments['screenshot']);
    var wantsLogs = _boolArgument(arguments['logs']);
    var wantsErrors = arguments['errors'] == null
        ? true
        : _boolArgument(arguments['errors']);
    var limit = _intArgument(arguments['lines'], 200);
    var source = switch (arguments['source']) {
      'app' => RunLogSource.app,
      'tool' => RunLogSource.tool,
      _ => null,
    };

    // The log first, and unconditionally reachable: it needs no connection, so
    // it is the half that still answers while the app is building or gone.
    var lines = wantsLogs
        ? readLogs(handle, only: source, tail: limit)
        : const <RunLogLine>[];
    var errors = wantsErrors
        ? readLogs(handle, errorsOnly: true, tail: limit)
        : const <RunLogLine>[];

    var up = probe?.canInspect ?? false;
    InspectTree? tree;
    String? shotPath;
    String? failure;
    if (up && (wantsTree || wantsShot)) {
      try {
        var read = await _withInspector(
          handle,
          (inspector) => inspector.read(
            tree: wantsTree,
            screenshot: wantsShot,
            summary: !full,
          ),
        );
        tree = read.tree;
        if (read.image case var bytes?) {
          var file = File(_screenshotPathFor(handle, arguments['out']));
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes);
          shotPath = file.absolute.path;
        }
      } on Object catch (e) {
        // Reported rather than thrown: the logs and the liveness in this same
        // answer are often what explains the failure.
        failure = '$e';
      }
    }

    return RunInspectResult(
      device: handle.device,
      entrypoint: handle.entrypoint,
      worktree: handle.worktreeName,
      mine: mine,
      up: up,
      reloadable: (probe?.canReload ?? false) && mine,
      progress: up ? null : log?.progress,
      tree: tree?.root?.toJson(),
      nodes: tree?.length,
      summary: wantsTree ? !full : null,
      screenshot: shotPath,
      logs: wantsLogs ? [for (var line in lines) _logEntry(line)] : null,
      logLines: wantsLogs ? lines.length : null,
      errors: wantsErrors && errors.isNotEmpty
          ? [for (var line in errors) _logEntry(line)]
          : null,
      log: handle.logPath,
      note: failure ?? _inspectNote(up: up, wanted: wantsTree || wantsShot),
    );
  }

  static RunLogEntry _logEntry(RunLogLine line) =>
      RunLogEntry(source: line.source.name, text: line.text, error: line.error);

  static String? _inspectNote({required bool up, required bool wanted}) {
    if (up) return null;
    return wanted
        ? 'The app is not answering, so there is no tree and no picture. It is '
              'either still building or it died — the logs say which.'
        : 'The app is not answering yet.';
  }

  RunHandle _selectApp(String? device, String? entrypoint) {
    var matches = [
      for (var handle in _handles)
        if (device == null || handle.device == device)
          if (entrypoint == null ||
              handle.entrypoint == entrypoint ||
              handle.entrypointName == entrypoint)
            handle,
    ];
    if (matches.isEmpty) {
      throw StateError(
        device == null
            ? 'Nothing is running.'
            : 'Nothing is running on "$device".',
      );
    }
    if (matches.length > 1) {
      throw StateError(
        'More than one app matches. Name a device and an entry point: '
        '${matches.map((h) => '${h.device}/${h.entrypoint}').join(', ')}',
      );
    }
    return matches.single;
  }

  RunAppEntry _appEntry(RunHandle handle, RunProbe? probe) => RunAppEntry(
    device: handle.device,
    deviceName: handle.deviceName,
    worktree: handle.worktreeName,
    mine: p.canonicalize(handle.worktree) == p.canonicalize(host.worktree.path),
    package: handle.package,
    entrypoint: handle.entrypoint,
    entrypointName: handle.entrypointName,
    knobs: handle.knobs,
    since: handle.startedAt.toUtc().toIso8601String(),
    app: probe?.app ?? false,
    launcher: probe?.launcher ?? false,
    vmService: handle.vmService,
    log: handle.logPath,
    error: probe?.error,
  );

  static int _intArgument(Object? value, int fallback) => switch (value) {
    int n => n,
    String s => int.tryParse(s) ?? fallback,
    _ => fallback,
  };

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
            kind: device.kind.name,
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
    return RunAppsResult(
      swept: swept,
      note: _handles.isEmpty
          ? 'Nothing is running. This lists apps launched through flutterware, '
                'which announce themselves in ${runDirProvider()}.'
          : null,
      apps: [for (var handle in _handles) _appEntry(handle, probeOf(handle))],
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
