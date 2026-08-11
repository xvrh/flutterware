import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware/channels.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart' show RPCError;

import '../../run/channel_client.dart';
import '../../run/connection.dart';
import '../../run/define_scripts.dart';
import '../../run/defines.dart';
import '../../run/drive_session.dart';
import '../../run/entrypoints.dart';
import '../../run/flavors.dart';
import '../../run/handle.dart';
import '../../run/inspect.dart';
import '../../run/inventory.dart';
import '../../run/journal.dart';
import '../../run/launch.dart';
import '../../run/logs.dart';
import '../../run/panel_client.dart';
import '../../shell/worktree_discovery.dart';
import '../../utils/daemon/device.dart';
import '../../utils/run_dir.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'run_results.dart';
import 'previews_core.dart' show PreviewsCore;

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

  /// Where this core's run state lives — what production reads, so a test that
  /// redirects [runDirProvider] redirects everything rather than most things.
  String get runDir => runDirProvider();

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

  /// True while a device list is on its way and has not arrived.
  ///
  /// **[_tracking] is the whole point of this, and leaving it out cost every
  /// `fw capture` on this repo its entire timeout.** A capture process opens
  /// the shell, goes to one panel and photographs it; it never mounts the Run
  /// panel, so it never calls [track], so no daemon is ever started and
  /// [devices] stays empty forever. The condition this replaces —
  /// `!isLive && devices.isEmpty` — read that as "still finding devices" and
  /// held the window busy until the wait gave up. Measured: 300 of the 360
  /// seconds a cold capture took, waiting for a scan nobody had started, to
  /// photograph a panel that has nothing to do with devices.
  ///
  /// So: busy only while something is actually looking. Nothing in flight is
  /// not a slow answer, it is no question.
  ///
  /// It ends when [_startDaemon] does, either way — a daemon or an error. The
  /// gap between the daemon coming up and its first `device.added` is not
  /// covered, and that is deliberate: the flutter daemon has no "here is the
  /// initial list" event, only a stream of additions, so any wait for a first
  /// device is a wait with no guaranteed end. A capture that catches the list
  /// one frame early is a bounded imprecision; the alternative was an
  /// unbounded one.
  bool get isFindingDevices => _tracking && !isLive && _daemonError == null;

  /// The runs currently announced, newest first — every worktree's, because a
  /// device held by another checkout is exactly the case this answers.
  List<RunHandle> get handles => _handles;

  /// The runs this worktree launched — what the rail lists and what the panel
  /// falls back to when the address names no run.
  ///
  /// The split matters: [handles] stays every worktree's because *occupancy*
  /// is a machine question, but the rail's rows are subjects you can drive,
  /// and another checkout's app is not one of yours. It is reached through the
  /// desk instead, which jumps to the worktree holding it.
  List<RunHandle> get ownHandles => [
    for (var handle in _handles)
      if (isMine(handle)) handle,
  ];

  /// Whether this worktree launched [handle]. Canonicalized, because the
  /// handle was written by another process whose spelling of the path — a
  /// symlink, a trailing separator — is not ours to assume.
  bool isMine(RunHandle handle) => _isOwnPath(handle.worktree);

  bool _isOwnPath(String path) =>
      p.canonicalize(path) == p.canonicalize(host.worktree.path);

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

  /// True while a run this worktree launched has not come up yet — a build in
  /// flight.
  ///
  /// Own runs only: this gates `busyWith`, and a capture of *this* worktree
  /// must not wait out another checkout's ninety-second Android build.
  bool get isStarting => ownHandles.any(
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

  /// [path]'s `flutter: default-flavor:`, when its pubspec declares one.
  ///
  /// Cached beside the entry points because it is read the same way, at the
  /// same moment, and answers the same question: what would be built if nobody
  /// filled anything in.
  String? defaultFlavorFor(String path) => _defaultFlavors[path];

  final _defaultFlavors = <String, String?>{};

  /// Every `--dart-define` [path]'s own `lib/` reads, by define name.
  ///
  /// Package-level rather than per entry point, because that is as far as an
  /// unresolved parse can honestly go — see [scanDefines].
  ///
  /// **Scanned on first ask, not in [computeAll].** Measured warm, the scan
  /// costs ~0.2ms per file in `lib/` — 2ms for `examples/example`'s 11 files,
  /// but 100ms for a 500-file package, because every file is read before the
  /// substring prefilter can rule it out. `computeAll` is ~430ms across this
  /// repo and *every* `fw` invocation pays it, so putting a real app's 100ms
  /// there would tax `fw status` for something only the `entrypoints` action
  /// and the New run page ever read.
  ///
  /// The cache is dropped by [computeAll] rather than kept forever: a reload
  /// means the sources may have moved, and a define list that outlived the code
  /// it was read from is the one wrong answer worth paying to avoid.
  Map<String, DefineRef> definesReadBy(String path) => _defines.putIfAbsent(
    path,
    () => scanDefines(host.workspace.absolutePathOf(path)),
  );

  final _defines = <String, Map<String, DefineRef>>{};

  /// The defines to offer for [entry], and what the scan says about each.
  ///
  /// The config is authority when it declared any — the rule entry points
  /// already follow, and for the same reason: declaring two defines meant those
  /// two. What the scan adds there is the **default the code actually uses**
  /// when the config named none, and the fact that a declared define is read
  /// nowhere at all.
  ///
  /// When the config declared none, the scan *is* the list. That is the zero
  /// config case, and it is worth having: the define's name and its real
  /// default are already written in the app, and repeating them in
  /// `tool/flutterware.dart` only creates two places to be wrong.
  List<({DartDefine define, DefineRef? read})> definesFor(
    String package,
    EntrypointRef entry,
  ) {
    var read = definesReadBy(package);
    if (entry.defines.isNotEmpty) {
      return [
        for (var define in entry.defines)
          (define: define, read: read[define.name]),
      ];
    }
    return [
      for (var define in read.values)
        (
          define: DartDefine(define.name, defaultValue: define.defaultValue),
          read: define,
        ),
    ];
  }

  /// What [entry] builds with when nobody overrides it, and where that came
  /// from — its own declaration, or [package]'s `flutter: default-flavor:`.
  ///
  /// One chain, used by the panel and by the `launch` action, because a form
  /// that pre-fills `dev` and an agent that passes nothing must build the same
  /// thing. They did not before: the action stopped at the entry point's
  /// declaration and never looked at the pubspec.
  ({String? flavor, FlavorSource source}) flavorFor(
    String package,
    EntrypointRef entry,
  ) => resolveFlavor(
    entrypointFlavor: entry.flavor,
    packageDefault: defaultFlavorFor(package),
  );

  /// The devices [entry] can run on, in the order every surface lists them.
  ///
  /// The whole list when the entry point declared no platforms, which is the
  /// ordinary case and has to stay free.
  List<DaemonDevice> devicesFor(EntrypointRef entry) => [
    for (var device in devices)
      if (device.allowedBy(entry)) device,
  ];

  /// True when [path]'s entry points came from `tool/flutterware.dart` rather
  /// than from scanning.
  bool isDeclared(String path) =>
      entrypointsFor(path).any((entry) => entry.declared);

  /// This machine's addresses on the local network — what a phone has to be
  /// told, since `localhost` on a phone is the phone — each with the interface
  /// it was found on.
  ///
  /// Cached from [computeAll] because a define's offered values are built inside
  /// [report], which may not do I/O of any kind.
  List<({String interface, String address})> get hostAddresses =>
      _hostAddresses;
  var _hostAddresses = <({String interface, String address})>[];

  /// What each [ScriptSource] said last time it was asked, by script and args.
  ///
  /// **Not filled by [computeAll], unlike everything else here**, because
  /// asking means running a process and `computeAll` may not. Filled by
  /// [resolveScriptSources], which the surfaces that chose to pay for it call:
  /// the `entrypoints` action, the panel on mount, and every launch.
  ///
  /// **Not keyed on the script's content**, deliberately. The answer changes
  /// when the dev stack goes up or down, which does not touch the file — a
  /// cache that invalidated on the source would hold a port from before the
  /// stack moved and be confident about it.
  final _scriptOutcomes = <String, ScriptOutcome>{};

  /// Keyed by script and args, separated by a character no argument can
  /// contain: `args: ['a b']` and `args: ['a', 'b']` are two different
  /// questions and must not share an answer.
  static String _scriptKey(ScriptSource source) =>
      [source.path, ...source.args].join('\u0000');

  ScriptOutcome? outcomeOf(ScriptSource source) =>
      _scriptOutcomes[_scriptKey(source)];

  /// Machine-global on purpose — see [handles] vs [ownHandles] for where the
  /// worktree line is drawn.
  List<RunHandle> _scanHandles() => scanRunHandles(runDirProvider());

  @override
  Future<void> computeAll() async {
    _cache = DeviceCache.read(runDirProvider());
    _handles = _scanHandles();
    _failures = {
      for (var failure in scanRunFailures(runDirProvider()))
        failure.key: failure,
    };
    for (var path in packages) {
      var root = host.workspace.absolutePathOf(path);
      var declared = declaredEntrypoints(_configFor(path));
      _entrypoints[path] = declared.isNotEmpty
          ? declared
          : scanEntrypoints(root);
      _defaultFlavors[path] = defaultFlavorOf(root);
    }
    // Not rescanned here — see [definesFor]. Dropped so the next ask re-reads
    // sources that may have moved since.
    _defines.clear();
    _hostAddresses = await _readHostAddresses();
    _scanned = true;
  }

  Map<String, Object?> _configFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] == path) return config;
    }
    return const {};
  }

  /// The IPv4 addresses of this machine's real interfaces, each named by the
  /// interface it came from.
  ///
  /// A syscall rather than a socket, and it is here rather than behind an
  /// action because "which address can the phone reach me at" is the answer a
  /// define has to offer *before* anybody presses anything.
  ///
  /// No attempt to guess which one is *the* address. Nothing here can tell a
  /// Wi-Fi address from a VPN's without asking the network, which is precisely
  /// what this must not do — so the interface name goes out with each one and
  /// the reader decides.
  static Future<List<({String interface, String address})>>
  _readHostAddresses() async {
    try {
      var interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      return [
        for (var interface in interfaces)
          for (var address in interface.addresses)
            (interface: interface.name, address: address.address),
      ];
    } on Object {
      // No permission, no interfaces, an OS that refuses — none of it is worth
      // failing a report over. The define simply offers less.
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
    if (debugLive) {
      // Same bargain as the daemon: the form is about to show what each define
      // will be, and it cannot show a computed one without asking for it.
      unawaited(resolveScriptSources().then((_) => notifyChanged()));
      unawaited(_startDaemon());
      unawaited(_probeAll());
      _scheduleProbe();
    }
  }

  /// False in a widget test. Mounting the panel starts a `flutter daemon` and
  /// a repeating probe, which is right in the app and is a subprocess and a
  /// pending timer in a test — neither of which a pumped panel can settle.
  @visibleForTesting
  static bool debugLive = true;

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
        _handles = _scanHandles();
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

  var _failures = <String, RunFailure>{};

  /// Runs that ended before they started, newest first.
  ///
  /// Keyed by [runHandleKey] and replaced rather than accumulated, because that
  /// key is stable across relaunch: trying the same thing again should correct
  /// the reason it failed, not stack a second copy of it underneath.
  ///
  /// Read from `*.failed` files, so a launch that failed under `fw` is in the
  /// GUI's rail and vice versa — the same rule as every other fact about a run
  /// here.
  List<RunFailure> get failures =>
      _failures.values.toList()..sort((a, b) => b.at.compareTo(a.at));

  /// The failures this worktree's launches recorded, for the rail.
  ///
  /// A record with no worktree — written before failures carried one — is
  /// kept everywhere rather than shown nowhere.
  List<RunFailure> get ownFailures => [
    for (var failure in failures)
      if (failure.worktree == null || _isOwnPath(failure.worktree!)) failure,
  ];

  RunFailure? failureFor(String key) => _failures[key];

  /// Notes why a run is gone, so the panel has something to show where the
  /// chip used to be. See [RunFailure] for why the handle cannot simply stay.
  @visibleForTesting
  void recordFailure(RunHandle handle, LaunchLog log) {
    if (_failures.length >= _maxRememberedFailures &&
        !_failures.containsKey(handle.key)) {
      var oldest = failures.last;
      _failures.remove(oldest.key);
      RunFailure.forget(runDirProvider(), oldest.key);
    }
    var failure = RunFailure(
      key: handle.key,
      worktree: handle.worktree,
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
    _failures[handle.key] = failure;
    failure.write(runDirProvider());
  }

  /// Forgets a failure, for when somebody has read it.
  void dismissFailure(String key) {
    RunFailure.forget(runDirProvider(), key);
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
    _failures = {
      for (var failure in scanRunFailures(runDirProvider()))
        failure.key: failure,
    };
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
          : ownHandles.isNotEmpty
          ? StatusBadge.count(ownHandles.length, tone: Tone.good)
          : StatusBadge.none,
      // **Runs, not devices.** A child's id becomes the first address segment
      // (`_childAddress`), so these have to be the things the panel can be
      // pointed at — and since the rebuild the panel's subjects are runs. A
      // device list in the rail would have been a row of links to nowhere.
      //
      // Devices have not gone anywhere: they are the desk, which the panel
      // renders when nothing is running and which belongs in the shell's
      // chrome. The status line below still counts them.
      //
      // **This worktree's runs, not the machine's.** The unfiltered ledger
      // put every checkout's runs in every rail, indistinguishable at a
      // glance and first in line for the panel's fallback — opening Run in
      // one worktree landed you on another's app. Occupancy stays global
      // ([handles], the desk, the `apps` action); the rows do not. The badge
      // counts the rows, so it cannot claim runs the rail will not show.
      children: [
        for (var handle in ownHandles)
          PluginChild(
            id: handle.key,
            label: '${handle.runLabel} · ${handle.deviceLabel}',
            status: _handleStatus(handle),
          ),
        // Runs that never started, listed with the live ones. They were in the
        // panel's chip row and nowhere else, which was the wrong half: the rail
        // is the list, so a launch that failed has to be in it or it has
        // vanished again.
        for (var failure in ownFailures)
          PluginChild(
            id: failure.key,
            label: '${failure.runLabel} · ${failure.deviceLabel}',
            status: Status.error(failure.headline ?? 'failed'),
          ),
      ],
      teardown: _teardown,
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
                  'without one at all — unlike a define, leaving it out is a '
                  'build failure rather than a default value.',
            ),
            const ActionParameter(
              'defines',
              'Defines',
              required: false,
              description:
                  '`--dart-define`s to bake in: `NAME=value,NAME=value`, or a '
                  'JSON object. Compiled in rather than read at run time, so '
                  'changing one costs a full rebuild — which is why the entry '
                  'point declares which ones it wants and what values are '
                  'worth using. Not to be confused with a preview knob, which '
                  'is read while a widget builds and costs a frame.',
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
          'act',
          'Act',
          returns: RunActResult,
          description:
              'One drive transaction against a running app: resolve the '
              'target, check the pointer can reach it (retrying through '
              'route transitions until a deadline), perform the verb, settle, '
              'and observe — texts, a screenshot, what was printed — all in '
              'one reply describing one moment. Needs the app to have been '
              'launched by flutterware (the launch wraps it in the drive '
              'guest); anything else is inspect-only. A refusal still '
              'observes: the error comes back with the screen it happened '
              "on. Every step is appended to the run's journal. On a phone "
              'the app has to be in the foreground: iOS suspends a '
              'backgrounded app, which answers nothing until somebody brings '
              'it back — that comes back as a timeout saying so, never a '
              'hang. A hidden desktop window is fine, and so is a '
              'backgrounded Android app.',
          parameters: [
            ..._appSelector,
            const ActionParameter(
              'verb',
              'Verb',
              kind: ActionParameterKind.choice,
              description: 'What to do',
              options: [
                ActionOption('tap'),
                ActionOption('longPress'),
                ActionOption('drag'),
                ActionOption('scrollTo'),
                ActionOption('enterText'),
                ActionOption('back'),
                ActionOption('wait'),
                ActionOption('observe'),
                ActionOption('navigate'),
              ],
            ),
            const ActionParameter(
              'target',
              'Target',
              required: false,
              description:
                  'What to act on. Bare text matches a visible string; JSON '
                  'names the rest: {"key": …}, {"label": …}, {"tooltip": …}, '
                  '{"containing": …}, {"within": {"scope": …, "child": …}}, '
                  '{"nth": {"target": …, "index": …}}. Resolved inside the '
                  'app at act time, and refused loudly on zero or several '
                  'matches — never a silent wrong-target tap. A reply text '
                  'ending in … was truncated: target it with '
                  '{"containing": <prefix>}.',
            ),
            const ActionParameter(
              'text',
              'Text',
              required: false,
              description: 'What enterText types, as one editing value',
            ),
            const ActionParameter(
              'dx',
              'Drag dx',
              required: false,
              description: 'Horizontal drag distance, logical pixels',
            ),
            const ActionParameter(
              'dy',
              'Drag dy',
              required: false,
              description:
                  'Vertical drag distance. Negative moves the finger up the '
                  'screen, the touch convention.',
            ),
            const ActionParameter(
              'within',
              'Scroll within',
              required: false,
              description:
                  'For scrollTo: which scrollable to walk, as a target. The '
                  'first one on screen when omitted.',
            ),
            const ActionParameter(
              'route',
              'Route',
              required: false,
              description:
                  "For navigate: the route the app's registered navigation "
                  'handler understands',
            ),
            const ActionParameter(
              'waitMs',
              'Wait',
              kind: ActionParameterKind.integer,
              required: false,
              description: 'For wait: real milliseconds to let the app run',
            ),
            ..._observationParameters,
            const ActionParameter(
              'actor',
              'Actor',
              required: false,
              defaultValue: 'agent',
              description: 'Who this step is journaled as',
            ),
          ],
        ),
        PluginAction(
          'observe',
          'Observe',
          returns: RunActResult,
          description:
              'The act-less transaction: settle the running app and look — '
              'texts, a screenshot, what it printed since the last step. The '
              'opening move of a drive loop, and the call to make after a '
              'hot reload. Same reply shape and same journal as act.',
          parameters: [
            ..._appSelector,
            ..._observationParameters,
            const ActionParameter(
              'actor',
              'Actor',
              required: false,
              defaultValue: 'agent',
              description: 'Who this step is journaled as',
            ),
          ],
        ),
        PluginAction(
          'navigate',
          'Navigate',
          returns: RunActResult,
          description:
              'Jumps the running app straight to a screen, through the '
              'navigation handler the app registered (router_outlet does, '
              'and any router can in one line: GuestDrive.navigator = …). '
              'Refuses plainly when the app declares none — it never falls '
              'back to hunting the UI with taps.',
          parameters: [
            ..._appSelector,
            const ActionParameter(
              'route',
              'Route',
              description: "The route, as the app's handler understands it",
            ),
            ..._observationParameters,
          ],
        ),
        PluginAction(
          'panels',
          'Panels',
          returns: RunPanelsResult,
          description:
              'What the app says about *itself*: the panels its own devbar '
              'plugins declare, with every knob and its live value, every '
              'action and its parameters, the states it can be asked for and '
              'the feeds it reports on. Where `observe` sees what flutterware '
              'can see of the screen, this is what the app chose to expose — '
              'feature flags, a simulated push, whatever the project wrote. '
              'Answers plainly for an app with no `Devbar` mounted. One '
              "attach per call, so recent feed events replay from the app's "
              'ring rather than needing a live subscription.',
          parameters: [
            ..._appSelector,
            const ActionParameter(
              'panel',
              'Panel',
              required: false,
              description: 'One panel by id; all of them when omitted',
            ),
            const ActionParameter(
              'events',
              'Feed events',
              kind: ActionParameterKind.integer,
              required: false,
              defaultValue: '20',
              description:
                  'How many recent events to bring back per feed, newest '
                  'kept. Zero for the declarations alone.',
            ),
          ],
        ),
        PluginAction(
          'panelInvoke',
          'Run a panel action',
          returns: RunPanelResult,
          description:
              'Runs one of the commands a panel declares, inside the app. '
              'This is the reach a test cannot buy: a push notification '
              'delivered with no backend, a permission answered with no '
              'device. The action ids and their parameters come from '
              "`panels`; a refusal is the app's own words, not a wrapper's.",
          parameters: [
            ..._appSelector,
            const ActionParameter(
              'panel',
              'Panel',
              description: 'The panel id `panels` reports',
            ),
            const ActionParameter(
              'action',
              'Action',
              description: "The action id, from that panel's `actions`",
            ),
            const ActionParameter(
              'args',
              'Arguments',
              required: false,
              description:
                  "The action's arguments as a JSON object — "
                  '{"title": "Order ready", "link": "/cart"}. A panel action '
                  'takes whatever it declared, so this stays free-form rather '
                  'than one flag per parameter.',
            ),
            const ActionParameter(
              'event',
              'Event',
              kind: ActionParameterKind.integer,
              required: false,
              description:
                  'For an item action: the id of the feed event to run it '
                  'on, as `panels` reports it.',
            ),
          ],
        ),
        PluginAction(
          'panelKnob',
          'Set a panel knob',
          returns: RunPanelResult,
          description:
              "Writes one of a panel's read-write values — a feature flag, a "
              'permission, an environment. Answers with the knobs **after** '
              'the write, because an app is allowed to clamp or refuse and a '
              'reply that echoed the request would be a lie. A picker is set '
              'by its label.',
          parameters: [
            ..._appSelector,
            const ActionParameter('panel', 'Panel'),
            const ActionParameter(
              'knob',
              'Knob',
              description: 'The knob name `panels` reports',
            ),
            const ActionParameter(
              'value',
              'Value',
              description:
                  'The new value. Parsed as JSON when it parses — so true, 3 '
                  'and "text" arrive as the right type — and taken as a plain '
                  'string when it does not.',
            ),
          ],
        ),
        PluginAction(
          'panelState',
          'Read a panel state',
          returns: RunPanelResult,
          description:
              'Asks the app for one snapshot it offers — the permissions it '
              'holds, its package info, its own account of the device. A '
              'separate call from `panels` because producing one can be '
              'expensive, and nothing should pay for it by listing.',
          parameters: [
            ..._appSelector,
            const ActionParameter('panel', 'Panel'),
            const ActionParameter(
              'state',
              'State',
              description: 'The state id `panels` reports',
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

  /// The launcher's line for a launch this process is waiting out.
  ///
  /// **Because nothing else is watching.** The rail's row fills in from the
  /// probe loop, which only runs where something subscribed — the GUI. A
  /// headless `launch` waits ninety seconds with a live log in front of it and
  /// used to publish none of it, so `fw` and an agent both watched a blank
  /// space. Reading it into the report puts it where every renderer already
  /// looks, and MCP forwards each change as progress.
  final _launching = <String, Status>{};

  void _setLaunching(String key, Status? status) {
    if (status == null) {
      _launching.remove(key);
    } else {
      _launching[key] = status;
    }
    notifyChanged();
  }

  Status _status(List<DaemonDevice> devices, Set<String> busy) {
    if (_launching.values.firstOrNull case var launching?) return launching;
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
    if (probe == null) return const Status.neutral('not probed');
    if (!probe.canInspect) {
      return Status.neutral(logOf(handle)?.progress ?? 'building');
    }
    if (!probe.launcher) return const Status.warn('no launcher');
    return const Status.good('live');
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
  /// One step per app this worktree launched, so closing the checkout does
  /// not leave one running on a phone with nothing able to reach it.
  ///
  /// **One step per app rather than one "stop 3 apps" row**, which is what
  /// [TeardownStep.arguments] is for: each row names its own device and says
  /// how long it has been up, and one can be left ticked while another is not.
  /// A lumped row can only be taken or left whole, and the reason to leave one
  /// running — it is on a phone somebody is holding — applies to one app and
  /// not the rest.
  ///
  /// Scoped to *this* worktree. The ledger is deliberately every worktree's, so
  /// that a device held by another checkout is visible; a teardown that stopped
  /// those too would be closing one tab and killing somebody else's run.
  List<TeardownStep> get _teardown => [
    for (var handle in ownHandles)
      TeardownStep(
        'stop',
        'Stop ${handle.runLabel} on ${handle.deviceLabel}',
        detail: _startedAgo(handle.startedAt),
        // The same arguments the `stop` action takes from `fw` and a form,
        // because it is the same action.
        arguments: {'device': handle.device, 'entrypoint': handle.entrypoint},
        checked: true,
        phase: TeardownPhase.apps,
      ),
  ];

  static String _startedAgo(DateTime startedAt) {
    var elapsed = DateTime.now().difference(startedAt);
    if (elapsed.inMinutes < 1) return 'started just now';
    if (elapsed.inHours < 1) return 'started ${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return 'started ${elapsed.inHours}h ago';
    return 'started ${elapsed.inDays}d ago';
  }

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
    const ActionParameter(
      'worktree',
      'Worktree',
      required: false,
      description:
          'Worktree name or path, to reach a run another checkout launched; '
          'only runs from this worktree match when omitted',
    ),
    const ActionParameter(
      'run',
      'Run',
      required: false,
      description:
          'The run id `apps` reports as `run`, and the ambiguity refusal '
          'lists — the last resort, and the only thing that separates two runs '
          'of the same entry point on the same device from the same worktree. '
          'The stable key an address carries is accepted too, where it is not '
          'ambiguous. Explicit like `worktree`: naming one reaches any run of '
          'this repository.',
    ),
  ];

  /// What every drive transaction lets you tune about its observation.
  static const _observationParameters = [
    ActionParameter(
      'settleMs',
      'Settle budget',
      kind: ActionParameterKind.integer,
      required: false,
      defaultValue: '800',
      description:
          'Milliseconds to wait for the app to stop animating before '
          'observing. Running out is reported (settled: false), never an '
          'error — a spinner would otherwise hang every step.',
    ),
    ActionParameter(
      'screenshot',
      'Screenshot',
      kind: ActionParameterKind.boolean,
      required: false,
      defaultValue: 'true',
      description:
          "Write the step's PNG under the run's journal directory and "
          'return its path. On by default — the picture is what makes the '
          'loop self-verifying.',
    ),
    ActionParameter(
      'tree',
      'Widget tree',
      kind: ActionParameterKind.boolean,
      required: false,
      defaultValue: 'false',
      description:
          'Include the widget tree in the reply. Off by default because a '
          'real app is thousands of tokens of tree; the texts ride along '
          'either way.',
    ),
    ActionParameter(
      'maxSide',
      'Screenshot cap',
      kind: ActionParameterKind.integer,
      required: false,
      description:
          "Cap the screenshot's longest side, in pixels — the render is "
          'scaled, not re-encoded. Full resolution when omitted.',
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
      'act' => _actAction(arguments),
      'observe' => _actAction({...arguments, 'verb': 'observe'}),
      'navigate' => _actAction({...arguments, 'verb': 'navigate'}),
      'panels' => _panelsAction(arguments),
      'panelInvoke' => _panelInvokeAction(arguments),
      'panelKnob' => _panelKnobAction(arguments),
      'panelState' => _panelStateAction(arguments),
      'emulators' => _emulatorsAction(),
      'bootEmulator' => _bootEmulatorAction(arguments),
      _ => super.invoke(actionId, arguments: arguments),
    };
  }

  Future<RunEntrypointsResult> _entrypointsAction(String? package) async {
    await computeAll();
    // A caller who asked what the defines are is a caller who chose to pay for
    // the answer, which computeAll may not spend a process on.
    await resolveScriptSources();
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
                  flavor: flavorFor(path, entry).flavor,
                  flavorSource: switch (flavorFor(path, entry).source) {
                    FlavorSource.none => null,
                    var source => source.name,
                  },
                  platforms: [
                    for (var platform in entry.platforms) platform.name,
                  ],
                  devices: entry.platforms.isEmpty
                      ? const []
                      : [for (var device in devicesFor(entry)) device.id],
                  defines: [
                    for (var (:define, :read) in definesFor(path, entry))
                      _defineEntry(define, read),
                  ],
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

  /// Everything worth offering for [define] — the config's own list plus
  /// whatever its `from:` points at right now.
  ///
  /// This is what makes "point the app at this machine" a choice rather than
  /// something to go and look up. Public because the panel's dialog and the
  /// `entrypoints` action must offer the same values — a list only one surface
  /// had would be a capability the others could not see.
  ///
  /// Bare values, with no decoration: this is what gets baked into the build,
  /// and an agent reading `entrypoints` wants the value. Which interface an
  /// address belongs to is [hostInterfaceOf], asked for separately by the one
  /// surface that can render it.
  List<String> optionsFor(DartDefine define) {
    var options = [...define.options];
    switch (define.from) {
      case HostAddressesSource():
        for (var host in hostAddresses) {
          if (!options.contains(host.address)) options.add(host.address);
        }
      case ScriptSource source:
        // Only the list form. A script that computed a single value did not
        // offer a choice, and putting it here as well would show it twice —
        // once pre-filled in the field and once as a chip that changes nothing.
        for (var value in outcomeOf(source)?.options ?? const <String>[]) {
          if (!options.contains(value)) options.add(value);
        }
      case null:
        break;
    }
    return options;
  }

  /// Asks every [ScriptSource] any declared define points at, concurrently.
  ///
  /// Every call re-asks. The point of a script source is that it knows
  /// something that changes without the project changing — which port this
  /// worktree's stack came up on — so a resolution kept from last time would be
  /// the wrong kind of fast.
  ///
  /// Distinct by script *and* args: two defines fed by the same tool with
  /// different arguments are two questions, while two defines that ask the
  /// identical thing are one process.
  Future<void> resolveScriptSources() => _resolveScripts([
    for (var path in packages)
      for (var entry in entrypointsFor(path)) ...entry.defines,
  ]);

  /// Asks the script sources among [defines], concurrently, and records what
  /// they said.
  ///
  /// **Takes the defines rather than reading them off this core**, which is
  /// what makes it safe to call from [launch]. The sweep above walks
  /// `entrypointsFor`, which is empty until `computeAll` has run — so a launch
  /// that relied on it would find no source to ask, then refuse itself for a
  /// value that was never looked up. Resolving exactly the defines the caller
  /// is about to use cannot disagree with the caller.
  Future<void> _resolveScripts(Iterable<DartDefine> defines) async {
    var sources = <String, ScriptSource>{};
    for (var define in defines) {
      if (define.from case ScriptSource source) {
        sources[_scriptKey(source)] = source;
      }
    }
    if (sources.isEmpty) return;
    var dart = p.join(host.workspace.flutterSdk.root, 'bin', 'dart');
    var asked = sources.entries.toList();
    var outcomes = await Future.wait([
      for (var entry in asked)
        runDefineScript(
          entry.value,
          dartExecutable: dart,
          worktreePath: host.worktree.path,
        ),
    ]);
    for (var (index, entry) in asked.indexed) {
      _scriptOutcomes[entry.key] = outcomes[index];
    }
  }

  /// The value a script source computed for [define], when one did.
  ///
  /// Beats what the config wrote and what the code falls back to, because it is
  /// the only one of the three that was worked out just now. A config's
  /// `defaultValue` is a guess made when the file was written; a scanned one is
  /// what the app does when nobody says anything.
  String? scriptValueFor(DartDefine define) => switch (define.from) {
    ScriptSource source => outcomeOf(source)?.value,
    _ => null,
  };

  /// Why [define] cannot be resolved, when its script source could not answer.
  String? scriptProblemFor(DartDefine define) => switch (define.from) {
    ScriptSource source => outcomeOf(source)?.problem,
    _ => null,
  };

  /// The interface an offered address was found on — `en0` — or null when it
  /// is not one of ours.
  ///
  /// Worth carrying because [hostAddresses] is every non-loopback IPv4 this
  /// machine has, which on a laptop is the Wi-Fi address plus a VPN `utun`,
  /// a Docker bridge and whatever a VM left behind. Exactly one of them is the
  /// one the phone can reach, and without the interface name the list gives a
  /// reader no way to tell which.
  String? hostInterfaceOf(String address) {
    for (var host in hostAddresses) {
      if (host.address == address) return host.interface;
    }
    return null;
  }

  DartDefineEntry _defineEntry(
    DartDefine define,
    DefineRef? read,
  ) => DartDefineEntry(
    name: define.name,
    label: define.label,
    description: define.description,
    // A script's answer first, because it is the only one worked out just now;
    // then the config's word; then the code's real fallback.
    defaultValue:
        scriptValueFor(define) ?? define.defaultValue ?? read?.defaultValue,
    options: optionsFor(define),
    kind: read?.kind,
    readAt: read?.file,
    problem: _defineProblem(define, read),
  );

  /// What is wrong with [define], worst first.
  ///
  /// A script that could not answer outranks a define nothing reads, because it
  /// is the one that will otherwise be discovered by an app talking to the
  /// wrong backend.
  String? _defineProblem(DartDefine define, DefineRef? read) {
    if (scriptProblemFor(define) case var problem?) {
      return '$problem. Until it answers, ${define.name} has no computed '
          'value and a launch that does not set it will be refused.';
    }
    if (read == null) {
      return 'nothing in this package reads ${define.name}. Setting it '
          'compiles and changes nothing — check the spelling against the '
          'fromEnvironment call.';
    }
    return null;
  }

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
    _checkDevice(device, entry);
    var defines = PreviewsCore.parsePairs(arguments['defines']);
    _checkDefineNames(package, entry, defines);

    var handle = await launch(
      device: device,
      package: package,
      entry: entry,
      // The caller's word beats every declaration, and an empty string is how a
      // caller says "no flavor" about an entry point that declares one.
      flavor: switch (arguments['flavor']) {
        String given => given.isEmpty ? null : given,
        _ => flavorFor(package, entry).flavor,
      },
      defines: defines,
    );

    var wait = _boolArgument(arguments['wait'] ?? true);
    var log = LaunchLog.read(handle.logPath ?? '');
    if (wait) {
      var timeout = Duration(seconds: _intArgument(arguments['timeout'], 300));
      try {
        (handle, log) = await awaitLaunch(
          handle,
          timeout,
          onProgress: (line) => _setLaunching(handle.key, Status.info(line)),
        );
      } finally {
        _setLaunching(handle.key, null);
      }
    }
    _handles = _scanHandles();
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
      _handles = _scanHandles();
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
  ///
  /// [defines] is what the caller *chose*; the defaults and anything a script
  /// source computes are filled in here, so both surfaces bake in the same set.
  Future<RunHandle> launch({
    required String device,
    required String package,
    required EntrypointRef entry,
    String? flavor,
    Map<String, String> defines = const {},
  }) async {
    var resolved = await _resolveDefines(entry, defines);
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
      flavor: flavor,
      defines: resolved,
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

  /// Refuses a device [entry] declared it cannot run on.
  ///
  /// Before the build rather than after it, which is the whole value: the
  /// alternative is a Gradle or Xcode failure minutes later saying something
  /// true about the toolchain and nothing about the choice that caused it.
  ///
  /// A device the daemon has never mentioned is *not* refused here — `launch`
  /// has always let a caller name one the cache has not caught up with, and
  /// turning that into an error would break launching onto a phone plugged in
  /// a second ago.
  void _checkDevice(String device, EntrypointRef entry) {
    if (entry.allowedPlatforms.isEmpty) return;
    var target = devices.where((candidate) => candidate.id == device);
    for (var candidate in target) {
      if (candidate.allowedBy(entry)) return;
      throw ArgumentError.value(
        device,
        'device',
        '${candidate.displayName} is '
            '${candidate.platformType ?? candidate.category ?? 'a platform'}, '
            'and ${entry.name} declares '
            '${[for (var platform in entry.platforms) platform.name].join(', ')}. '
            'Runs on: ${[for (var allowed in devicesFor(entry)) allowed.id].join(', ')}',
      );
    }
  }

  /// Refuses a define name neither declared nor read anywhere in the package.
  ///
  /// Refused rather than passed through, because a misspelled define compiles
  /// perfectly and does nothing — the app reads the fallback and behaves as if
  /// nobody set anything, which is a very long way from a legible failure.
  ///
  /// The scan is what makes the refusal safe to extend. Before it, the only
  /// defines known were the declared ones, so a package that declared none had to
  /// accept anything; now `APII` is refused against the defines the code
  /// genuinely reads, and the error can name them.
  ///
  /// Only the action path needs this — the panel builds its fields from the same
  /// list, so it cannot produce a name that is not on it. Filling in defaults is
  /// [_resolveDefines], which both paths share.
  void _checkDefineNames(
    String package,
    EntrypointRef entry,
    Map<String, String> given,
  ) {
    var known = {
      for (var (:define, read: _) in definesFor(package, entry))
        define.name: define,
    };
    if (known.isEmpty) return;
    for (var name in given.keys) {
      if (!known.containsKey(name)) {
        throw ArgumentError.value(
          name,
          'defines',
          '${entry.name} has no such define; it takes '
              '${known.keys.join(', ')}',
        );
      }
    }
  }

  /// The defines a launch will bake in: what the caller gave, over what a script
  /// source computed, over what the config declared.
  ///
  /// **Both launch paths go through this**, which is the point of it being here
  /// rather than in the action. They used to disagree: the action omitted a
  /// scanned default while the panel seeded its text field with one and then
  /// sent it, so the same launch through two surfaces produced two different
  /// build commands.
  ///
  /// **A script source that could not answer refuses the launch.** Everything
  /// else in this file degrades — an unreadable handle is a handle that does not
  /// exist, an OS that will not list interfaces means a shorter list. This one
  /// may not, because the define it failed to compute is compiled in, and an app
  /// built against the wrong port behaves exactly like an app built against the
  /// right one until it is talking to another worktree's database.
  Future<Map<String, String>> _resolveDefines(
    EntrypointRef entry,
    Map<String, String> given,
  ) async {
    await _resolveScripts(entry.defines);
    var resolved = <String, String>{};
    var unresolved = <String>[];
    // Only what the *config* declared. A scanned define's default is the value
    // the code already falls back to, so passing it back as a `--dart-define`
    // sets nothing, lengthens the build command and fills the run's handle with
    // values nobody picked — and only a config can declare a `from:` at all.
    for (var define in entry.defines) {
      if (given.containsKey(define.name)) continue;
      if (define.from case ScriptSource source) {
        var outcome = outcomeOf(source);
        if (outcome == null || outcome.failed) {
          unresolved.add(
            '${define.name} (${outcome?.problem ?? 'not resolved'})',
          );
          continue;
        }
        if (outcome.value case var value?) {
          resolved[define.name] = value;
          continue;
        }
      }
      if (define.defaultValue case var value?) resolved[define.name] = value;
    }
    if (unresolved.isNotEmpty) {
      throw StateError(
        'cannot work out ${unresolved.join(', ')}. Fix the script, or pass the '
        'define explicitly to launch without it.',
      );
    }
    return {...resolved, ...given};
  }

  Future<RunControlResult> _controlAction(
    String action,
    Map<String, Object?> arguments,
  ) async {
    _handles = _scanHandles();
    await _probeAll();
    var handle = _selectApp(arguments, await _repoWorktrees);
    var started = DateTime.now();
    try {
      await control(action, handle);
      // Reloads and restarts are steps in the run's story too: the strip
      // that shows what the agent tapped should show what it reloaded
      // between the taps.
      appendJournal(
        handle,
        JournalEntry(
          at: started.toUtc().toIso8601String(),
          verb: action,
          elapsedMs: DateTime.now().difference(started).inMilliseconds,
        ),
      );
      return RunControlResult(
        action: action,
        run: handle.runId,
        device: handle.device,
        entrypoint: handle.entrypoint,
        ok: true,
        ms: DateTime.now().difference(started).inMilliseconds,
      );
    } on Object catch (e) {
      return RunControlResult(
        action: action,
        run: handle.runId,
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
          unawaited(_driveSessions.remove(_driveKey(handle))?.close());
          await connection?.exitApp();
          // Current, not merely alive: this pid came out of a file that can
          // be a day old, and SIGTERM to a recycled number is SIGTERM to
          // whatever unrelated process holds it now.
          if (isProcessCurrent(handle.launcherPid, handle.startedAt)) {
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
    _handles = _scanHandles();
    await _probeAll();
    return _selectApp(arguments, await _repoWorktrees);
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
    Map<String, String> defines,
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
  }) =>
      debugRead?.call(handle) ??
      _withInspector(
        handle,
        (i) => i.read(tree: tree, screenshot: screenshot, summary: summary),
      );

  /// Stands in for the VM service so the panel can be pumped in a test.
  ///
  /// The same seam scenarios has for its runner, and for the same reason: the
  /// pane's mount-and-read is where a `setState` on an ancestor slipped in, and
  /// nothing that needs a real app could ever have caught it.
  @visibleForTesting
  Future<InspectRead> Function(RunHandle handle)? debugRead;

  /// Puts a probe result in as though one had been taken.
  @visibleForTesting
  void debugSetProbe(RunHandle handle, RunProbe probe) {
    if (handle.handlePath case var path?) _probes[path] = probe;
  }

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

  /// Attaches to the app's channels for the length of one action.
  ///
  /// **A fresh attach per call, deliberately.** The alternative is a cached
  /// attachment per handle, and the cost of that is a queue nobody is draining
  /// between calls: the app would ring events for a peer that might never
  /// return. Attaching costs one round trip and buys the ring's replay, which
  /// is what makes recent feed events readable at all from a stateless call.
  ///
  /// The peer id is unique per call for the same reason the cockpit's is
  /// unique per pane — two attachers sharing a queue race for it, and the
  /// drain that loses returns frames the winner already took.
  Future<T> _withPanels<T>(
    RunHandle handle,
    Future<T> Function(RunChannelClient client, RunPanels panels) body,
  ) async {
    var uri = handle.vmService;
    if (uri == null) {
      throw StateError(
        '${handle.entrypointLabel} has no VM service yet — it is still '
        'building. Watch ${handle.logPath}.',
      );
    }
    var connection = await RunConnection.connect(uri);
    RunChannelClient client;
    try {
      client = await RunChannelClient.attach(
        connection,
        peer: 'action:${_nextPanelPeer++}',
      );
    } on Object {
      await connection.close();
      // Not a failure of this call so much as a fact about the app: an app
      // that mounts no `Devbar` installs no channels, and saying which is the
      // difference between a bug hunt and reading one line.
      throw StateError(
        '${handle.entrypointLabel} is not reporting any panels. An app '
        'reports them by mounting `Devbar(plugins: …)` around its own widget '
        'and being launched by flutterware.',
      );
    }
    try {
      return await body(client, RunPanels(client));
    } finally {
      await client.close();
      await connection.close();
    }
  }

  var _nextPanelPeer = 1;

  /// The events this attachment replayed, per feed, newest [limit] kept.
  Map<String, List<Map<String, Object?>>> _feedEvents(
    RunChannelClient client,
    List<PanelDescriptor> panels,
    int limit,
  ) {
    if (limit <= 0) return const {};
    var wanted = {
      for (var panel in panels)
        for (var feed in panel.feeds) panel.feedChannel(feed.id),
    };
    var byChannel = <String, List<Map<String, Object?>>>{};
    for (var event in client.received) {
      if (!wanted.contains(event.channel)) continue;
      (byChannel[event.channel] ??= []).add({
        'event': event.id,
        'at': event.time.toIso8601String(),
        if (event.rid != null) 'rid': event.rid,
        ...event.payload,
      });
    }
    return {
      for (var entry in byChannel.entries)
        entry.key: entry.value.length <= limit
            ? entry.value
            : entry.value.sublist(entry.value.length - limit),
    };
  }

  Future<RunPanelsResult> _panelsAction(Map<String, Object?> arguments) async {
    var handle = await _selectRunningApp(arguments);
    var only = arguments['panel'] as String?;
    var limit = switch (arguments['events']) {
      null => 20,
      var value => _intArgument(value, 20),
    };
    return _withPanels(handle, (client, panels) async {
      var listed = await panels.list();
      var chosen = only == null
          ? listed
          : [
              for (var panel in listed)
                if (panel.id == only) panel,
            ];
      if (only != null && chosen.isEmpty) {
        throw StateError(
          'This app declares no panel "$only" — it has '
          '${listed.isEmpty ? 'none' : listed.map((p) => p.id).join(', ')}.',
        );
      }
      return RunPanelsResult(
        device: handle.device,
        entrypoint: handle.entrypoint,
        panels: [for (var panel in chosen) panel.toJson()],
        events: _feedEvents(client, chosen, limit),
        note: listed.isEmpty
            ? 'The app is reporting, but no plugin declared a panel. A devbar '
                  'plugin joins by implementing `DevbarPanelSource`.'
            : null,
      );
    });
  }

  Future<RunPanelResult> _panelInvokeAction(
    Map<String, Object?> arguments,
  ) async {
    var handle = await _selectRunningApp(arguments);
    var panelId = _requiredArgument(arguments, 'panel');
    var actionId = _requiredArgument(arguments, 'action');
    var args = _jsonObjectArgument(arguments['args'], 'args');
    if (arguments['event'] case var event?) {
      args = {...args, 'event': _intArgument(event, 0)};
    }
    return _withPanels(handle, (client, panels) async {
      var result = await panels.invoke(panelId, actionId, args);
      return RunPanelResult(
        device: handle.device,
        entrypoint: handle.entrypoint,
        panel: panelId,
        result: result,
      );
    });
  }

  Future<RunPanelResult> _panelKnobAction(
    Map<String, Object?> arguments,
  ) async {
    var handle = await _selectRunningApp(arguments);
    var panelId = _requiredArgument(arguments, 'panel');
    var knob = _requiredArgument(arguments, 'knob');
    var raw = arguments['value'];
    return _withPanels(handle, (client, panels) async {
      var knobs = await panels.setKnob(panelId, knob, _looseValue(raw));
      var after = knobs.where((k) => k.name == knob).firstOrNull;
      return RunPanelResult(
        device: handle.device,
        entrypoint: handle.entrypoint,
        panel: panelId,
        result: {'knob': knob, 'value': after?.value},
        knobs: [for (var k in knobs) k.toJson()],
        note: after == null
            ? 'The app kept no knob called "$knob" — it may have been declared '
                  'by a screen that has since unmounted.'
            : null,
      );
    });
  }

  Future<RunPanelResult> _panelStateAction(
    Map<String, Object?> arguments,
  ) async {
    var handle = await _selectRunningApp(arguments);
    var panelId = _requiredArgument(arguments, 'panel');
    var stateId = _requiredArgument(arguments, 'state');
    return _withPanels(handle, (client, panels) async {
      var snapshot = await panels.state(panelId, stateId);
      return RunPanelResult(
        device: handle.device,
        entrypoint: handle.entrypoint,
        panel: panelId,
        result: snapshot,
      );
    });
  }

  static String _requiredArgument(Map<String, Object?> arguments, String id) {
    var value = arguments[id];
    if (value is String && value.isNotEmpty) return value;
    throw ArgumentError('`$id` is required');
  }

  /// A knob value the way a caller can actually type one: `true`, `3` and
  /// `"prod"` all arrive as strings from `fw` and from a form, and the app
  /// wants the real type. Anything that is not JSON is itself — a bare
  /// `Staging` is the string, not a syntax error.
  static Object? _looseValue(Object? raw) {
    if (raw is! String) return raw;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return raw;
    }
  }

  static Map<String, Object?> _jsonObjectArgument(Object? raw, String id) {
    if (raw == null) return const {};
    if (raw is Map) return raw.cast<String, Object?>();
    if (raw is! String || raw.isEmpty) return const {};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw ArgumentError('`$id` is not JSON: $e');
    }
    if (decoded is! Map) {
      throw ArgumentError(
        '`$id` must be a JSON object, not ${decoded.runtimeType}',
      );
    }
    return decoded.cast<String, Object?>();
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

  /// Held drive connections, one per run — the loop's fast path. A session
  /// drops its connection on any error and reconnects on the next call;
  /// closed here on stop and on dispose.
  final _driveSessions = <String, DriveSession>{};

  String _driveKey(RunHandle handle) =>
      handle.handlePath ?? handle.vmService ?? handle.entrypoint;

  DriveSession _driveSessionFor(RunHandle handle) =>
      _driveSessions[_driveKey(handle)] ??= DriveSession(handle);

  /// Stands in for the guest wire so the act path can be pumped in a test —
  /// the same seam [debugRead] is for inspect.
  @visibleForTesting
  Future<Map<String, dynamic>> Function(RunHandle, Map<String, String>)?
  debugAct;

  /// `act`, `observe` and `navigate` — one funnel, because the last two are
  /// the first with the verb fixed.
  Future<RunActResult> _actAction(Map<String, Object?> arguments) async {
    var handle = await _selectRunningApp(arguments);
    var verb = arguments['verb'] as String? ?? 'observe';
    var actor = arguments['actor'] as String? ?? 'agent';
    var wantsTree = _boolArgument(arguments['tree']);
    var wantsShot = arguments['screenshot'] == null
        ? true
        : _boolArgument(arguments['screenshot']);
    // The tree is requested from the guest regardless of [wantsTree]: it is
    // persisted as a journal artifact either way — a reviewer of the step
    // strip gets the same three legs a scenario step has — and only *returned*
    // inline when asked, because a real app is thousands of tokens of tree.
    var wire = <String, String>{
      'verb': verb,
      if (!wantsShot) 'screenshot': 'false',
      for (var key in const [
        'target',
        'text',
        'dx',
        'dy',
        'within',
        'step',
        'maxScrolls',
        'route',
        'waitMs',
        'settleMs',
        'actTimeoutMs',
        'maxSide',
      ])
        if (arguments[key] case var value?) key: '$value',
    };
    var started = DateTime.now();

    Map<String, dynamic> reply;
    try {
      reply =
          await (debugAct?.call(handle, wire) ??
              _driveSessionFor(handle).act(wire));
    } on Object catch (e) {
      // -32601: the extension does not exist — the app runs without the
      // guest, which is a fact about how it was launched, not a fault.
      var error = e is RPCError && e.code == -32601
          ? 'This app is running without the drive guest, so it can be '
                'inspected but not driven. Launch it through flutterware '
                '(the GUI, `fw run launch`, or MCP) to get a driveable run.'
          : '$e';
      appendJournal(
        handle,
        JournalEntry(
          at: started.toUtc().toIso8601String(),
          verb: verb,
          actor: actor,
          target: arguments['target'] as String?,
          error: error,
        ),
      );
      return RunActResult(
        device: handle.device,
        entrypoint: handle.entrypoint,
        worktree: handle.worktreeName,
        verb: verb,
        ok: false,
        error: error,
        journal: journalPathFor(handle),
      );
    }

    var step = (reply['step'] as Map?)?.cast<String, Object?>();
    var settle = (step?['settle'] as Map?)?.cast<String, Object?>();
    var error = reply['error'] as String?;
    var treeJson = (reply['tree'] as Map?)?.cast<String, Object?>();
    var texts = (reply['texts'] as List?)?.cast<String>();
    var logs = (reply['logs'] as List?)?.cast<Map>();
    var guestErrors = (reply['errors'] as List?)?.cast<Map>();
    var framesEnabled = settle?['framesEnabled'] as bool?;
    var human = (reply['human'] as List?)?.cast<Map>();

    String? shotPath;
    String? treePath;
    String? textsPath;
    if (journalArtifactsDirFor(handle) case var dir?) {
      var stem = p.join(dir, '${started.millisecondsSinceEpoch}-$pid');
      File? write(String path, List<int> bytes) {
        var file = File(path);
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        return file;
      }

      if ((reply['screenshot'] as Map?)?['base64'] case String data) {
        shotPath = write('$stem.png', base64Decode(data))?.absolute.path;
      }
      if (treeJson != null) {
        treePath = write(
          '$stem.tree.json',
          utf8.encode(jsonEncode(treeJson)),
        )?.absolute.path;
      }
      if (texts != null) {
        textsPath = write(
          '$stem.texts.json',
          utf8.encode(jsonEncode(texts)),
        )?.absolute.path;
      }
    }

    // What the human did on the way here, ahead of the step that saw it —
    // the guest buffers between transactions, so these precede this step in
    // wall time and must precede it in the story too.
    for (var action in human ?? const <Map>[]) {
      appendJournal(
        handle,
        JournalEntry(
          at: action['at'] as String? ?? started.toUtc().toIso8601String(),
          verb: action['verb'] as String? ?? 'tap',
          actor: 'human',
          target: action['target'] as String?,
        ),
      );
    }

    appendJournal(
      handle,
      JournalEntry(
        at: started.toUtc().toIso8601String(),
        verb: (step?['verb'] as String?) ?? verb,
        actor: actor,
        target:
            step?['target'] as String? ??
            arguments['target'] as String? ??
            arguments['route'] as String?,
        error: error,
        failure: reply['failure'] as String?,
        attempts: step?['attempts'] as int?,
        elapsedMs: step?['elapsedMs'] as int?,
        settled: settle?['settled'] as bool?,
        settleMs: settle?['elapsedMs'] as int?,
        lifecycle: reply['lifecycle'] as String?,
        screenshot: shotPath,
        tree: treePath,
        texts: textsPath,
        logLines: logs?.length,
        errorCount: guestErrors?.length,
      ),
    );

    return RunActResult(
      device: handle.device,
      entrypoint: handle.entrypoint,
      worktree: handle.worktreeName,
      verb: (step?['verb'] as String?) ?? verb,
      target: step?['target'] as String? ?? arguments['target'] as String?,
      screenshotArtifact: shotPath == null
          ? null
          : Artifact(
              kind: Artifact.png,
              address: Address(
                worktree: host.worktree.name,
                plugin: runPluginId,
                segments: [handle.key, 'steps'],
              ),
              path: shotPath,
              meta: {
                'verb': (step?['verb'] as String?) ?? verb,
                if (step?['target'] case String target) 'target': target,
                if (settle?['settled'] == false) 'settled': false,
              },
            ),
      ok: error == null,
      error: error,
      failure: reply['failure'] as String?,
      attempts: step?['attempts'] as int?,
      elapsedMs: step?['elapsedMs'] as int?,
      settled: settle?['settled'] as bool?,
      settleMs: settle?['elapsedMs'] as int?,
      frames: settle?['frames'] as int?,
      framesEnabled: framesEnabled,
      lifecycle: reply['lifecycle'] as String?,
      human: human == null
          ? null
          : [for (var action in human) '${action['verb']} ${action['target']}'],
      texts: texts,
      tree: wantsTree ? treeJson : null,
      nodes: treeJson == null ? null : _countNodes(treeJson['root']),
      screenshot: shotPath,
      logs: logs == null
          ? null
          : [
              for (var line in logs)
                RunLogEntry(source: 'app', text: line['text'] as String? ?? ''),
            ],
      errors: guestErrors == null
          ? null
          : [
              for (var guestError in guestErrors)
                RunLogEntry(
                  source: 'app',
                  text: [
                    guestError['exception'] as String? ?? '',
                    if (guestError['context'] case String context) '($context)',
                    if (guestError['count'] case int count when count > 1)
                      '×$count',
                  ].join(' '),
                  error: true,
                ),
            ],
      journal: journalPathFor(handle),
      note: framesEnabled == false
          ? 'The window is hidden or occluded; every frame this step saw was '
                'forced. What a human sees on screen may lag this reply.'
          : null,
    );
  }

  static int? _countNodes(Object? node) {
    if (node is! Map) return null;
    var count = 1;
    for (var child in (node['children'] as List?) ?? const []) {
      count += _countNodes(child) ?? 0;
    }
    return count;
  }

  static String? _inspectNote({required bool up, required bool wanted}) {
    if (up) return null;
    return wanted
        ? 'The app is not answering, so there is no tree and no picture. It is '
              'either still building or it died — the logs say which.'
        : 'The app is not answering yet.';
  }

  /// The canonical paths of this repository's worktrees, from git.
  ///
  /// What bounds the `worktree` argument: a worktree's *name* is unique only
  /// within its repository — every repository's main checkout is `~` — so a
  /// name matched against the machine-wide ledger could silently pick an
  /// unrelated project's run. Cached for the core's lifetime; a worktree
  /// added since shows up on the next session, and selection itself goes by
  /// the paths the handles carry.
  late final Future<Set<String>> _repoWorktreePaths = () async {
    var own = p.canonicalize(host.worktree.path);
    try {
      var worktrees = await WorktreeDiscovery().discover(host.worktree.path);
      return {own, for (var w in worktrees) p.canonicalize(w.path)};
    } on Object {
      // No git, or not a repository. Own runs remain reachable.
      return {own};
    }
  }();

  /// Test seam: the repository's worktrees without a git call, the same seam
  /// [debugAct] and [debugRead] are.
  @visibleForTesting
  Future<Set<String>>? debugRepoWorktrees;

  Future<Set<String>> get _repoWorktrees =>
      debugRepoWorktrees ?? _repoWorktreePaths;

  RunHandle _selectApp(
    Map<String, Object?> arguments,
    Set<String> repoWorktrees,
  ) {
    var device = arguments['device'] as String?;
    var entrypoint = arguments['entrypoint'] as String?;
    var worktree = arguments['worktree'] as String?;
    var run = arguments['run'] as String?;
    // Own runs by default, like the rail: the owner's Studio in another
    // worktree is the same device/entrypoint pair as this one's, and neither
    // argument could tell them apart. Naming a worktree is the explicit
    // opt-in — it widens the pool to this *repository's* runs, never the
    // machine's: a sibling checkout is something a session can mean, another
    // project's app is not.
    var repoHandles = [
      for (var handle in _handles)
        if (repoWorktrees.contains(p.canonicalize(handle.worktree))) handle,
    ];
    // A key is as explicit as a worktree name and as unique as a run gets, so
    // it opts into the repository's pool the same way — and then it is the
    // whole selection: nothing else can narrow one run further.
    var pool = worktree == null && run == null
        ? ownHandles
        : [
            for (var handle in repoHandles)
              if (worktree == null ||
                  handle.worktreeName == worktree ||
                  p.canonicalize(handle.worktree) == p.canonicalize(worktree))
                handle,
          ];
    var matches = [
      for (var handle in pool)
        if (run == null || handle.runId == run || handle.key == run)
          if (device == null || handle.device == device)
            if (entrypoint == null ||
                handle.entrypoint == entrypoint ||
                handle.entrypointName == entrypoint)
              handle,
    ];
    if (matches.isEmpty) {
      // The next move rides in the refusal: this is an agent's first contact
      // with a cold machine, and "what now" should not cost a discovery call.
      var others = [
        for (var handle in repoHandles)
          if (!isMine(handle)) handle,
      ];
      var nothing = run != null
          ? 'No run "$run" — `apps` reports the keys that exist.'
          : worktree != null
          ? 'Nothing is running from worktree "$worktree".'
          : device != null
          ? 'Nothing is running on "$device".'
          : 'Nothing is running${others.isEmpty ? '' : ' from this worktree'}.';
      var elsewhere = others.isEmpty
          ? ''
          : ' Other worktrees are: '
                '${others.map((h) => '${h.worktreeName} (${h.device}/${h.entrypoint})').join(', ')}'
                ' — pass `worktree` to drive one.';
      throw StateError(
        '$nothing$elsewhere '
        '`launch` starts an app; `status` lists devices and declared entry '
        'points.',
      );
    }
    if (matches.length > 1) {
      // Every match named by its key, because the ones this refusal exists for
      // are the ones a worktree, a device and an entry point cannot separate:
      // two Studios launched from one checkout onto one device printed the
      // same string twice and left no argument that could pick either.
      throw StateError(
        'More than one app matches. Pass `run` with one of: '
        '${matches.map((h) => '${h.runId} (${h.worktreeName}: ${h.device}/${h.entrypoint}, ${_startedAgo(h.startedAt)})').join(', ')}',
      );
    }
    return matches.single;
  }

  RunAppEntry _appEntry(RunHandle handle, RunProbe? probe) => RunAppEntry(
    run: handle.runId,
    device: handle.device,
    deviceName: handle.deviceName,
    worktree: handle.worktreeName,
    mine: isMine(handle),
    package: handle.package,
    entrypoint: handle.entrypoint,
    entrypointName: handle.entrypointName,
    defines: handle.defines,
    since: handle.startedAt.toUtc().toIso8601String(),
    app: probe?.app ?? false,
    launcher: probe?.launcher ?? false,
    // Own runs only. The URI carries the VM service's auth token — the whole
    // of what gates connecting — and handing it out for another worktree's
    // run is handing out reload/restart/exit on an app this session does not
    // own, past every check `_selectApp` makes. Occupancy needs the row, not
    // the connect string.
    vmService: isMine(handle) ? handle.vmService : null,
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

    _handles = _scanHandles();
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
    _handles = _scanHandles();
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
    for (var session in _driveSessions.values) {
      unawaited(session.close());
    }
    _driveSessions.clear();
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
