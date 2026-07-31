import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../utils/daemon/commands.dart';
import '../utils/daemon/device.dart';
import '../utils/daemon/events.dart';
import '../utils/daemon/protocol.dart';
import '../utils/flutter_sdk.dart';

final _logger = Logger('run_inventory');

/// The device list, as somebody last saw it.
///
/// A cache with a timestamp rather than a value that expires. A `flutter
/// daemon` takes seconds to start and there is no version of this tool where
/// paying that on every `fw devices` is acceptable, so the honest shape is the
/// one the architecture doc already settled for runs: **it gets old, it does
/// not become wrong.** Every surface that renders this says how old it is, and
/// `--refresh` is what a caller reaches for when the age matters.
class DeviceCache {
  const DeviceCache({required this.updatedAt, required this.devices});

  final DateTime updatedAt;
  final List<DaemonDevice> devices;

  Duration get age => DateTime.now().difference(updatedAt);

  /// `just now`, `2 minutes ago`, `3 hours ago` — the phrase every surface
  /// puts beside the list, computed once so they agree.
  String get ageDescription {
    var seconds = age.inSeconds;
    if (seconds < 10) return 'just now';
    if (seconds < 90) return '${seconds}s ago';
    var minutes = age.inMinutes;
    if (minutes < 90) return '${minutes}m ago';
    var hours = age.inHours;
    if (hours < 48) return '${hours}h ago';
    return '${age.inDays}d ago';
  }

  static String pathIn(String runDir) => p.join(runDir, 'devices.json');

  /// Null when nothing has ever written one, or what is there cannot be read.
  static DeviceCache? read(String runDir) {
    try {
      var file = File(pathIn(runDir));
      if (!file.existsSync()) return null;
      var json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return null;
      var map = json.cast<String, Object?>();
      return DeviceCache(
        updatedAt: DateTime.parse(map['updatedAt']! as String),
        devices: [
          for (var entry in (map['devices'] as List? ?? const []))
            if (entry is Map)
              ?DaemonDevice.tryRead(entry.cast<String, Object?>()),
        ],
      );
    } on Object {
      return null;
    }
  }

  /// Publishes [devices] for every other process to read.
  ///
  /// Written through a temporary file and renamed, because the reader is a
  /// cold `fw` in another checkout that will happily parse half a document and
  /// conclude the machine has no devices.
  static void write(String runDir, List<DaemonDevice> devices) {
    var target = pathIn(runDir);
    var temporary = '$target.${pid}tmp';
    try {
      Directory(runDir).createSync(recursive: true);
      File(temporary).writeAsStringSync(
        jsonEncode({
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'devices': [for (var device in devices) device.toJson()],
        }),
      );
      File(temporary).renameSync(target);
    } on Object catch (e) {
      _logger.fine('Could not write the device cache: $e');
      try {
        File(temporary).deleteSync();
      } on Object {
        // Nothing to clean up, or somebody else did.
      }
    }
  }
}

/// A live `flutter daemon`, held open for as long as something is watching
/// devices.
///
/// One per SDK per process, because starting one costs seconds and the answer
/// it gives is about the machine, not about a worktree — two open worktrees
/// asking the same question should not pay for two daemons or disagree about
/// what is plugged in.
///
/// Everything it learns goes into [DeviceCache], so a `fw` that never starts
/// one still gets an answer, with an age attached.
class DeviceDaemon {
  DeviceDaemon._(this._process, this._protocol, this._runDir, this._key);

  static final _instances = <String, _Shared>{};

  final Process _process;
  final DaemonProtocol _protocol;
  final String _runDir;

  /// The SDK root this daemon is shared under — what [release] looks itself up
  /// by.
  final String _key;
  final _devices = <String, DaemonDevice>{};
  final _changes = StreamController<void>.broadcast();
  var _stopped = false;

  /// Everything currently plugged in, ordered so the list does not shuffle
  /// between polls: physical devices first — they are what the cockpit is
  /// for — then by name.
  List<DaemonDevice> get devices =>
      _devices.values.toList()..sort(compareDevices);

  /// Fires whenever [devices] would answer differently.
  Stream<void> get changes => _changes.stream;

  /// Takes a lease on the daemon for this SDK, starting one if nobody has.
  ///
  /// Spawns a process, so it belongs behind an action or in live tracking —
  /// never in `report` or `computeAll`.
  ///
  /// **Every caller must [release] eventually.** The child keeps the Dart VM
  /// alive, so a `fw devices --refresh` that forgets prints its answer and then
  /// hangs forever — which is exactly what the first run of this code did, for
  /// ten minutes, until the daemon was killed by hand. Leases rather than an
  /// owner because the GUI shares one across every open worktree and the CLI
  /// has exactly one user: counting is the only rule that serves both.
  static Future<DeviceDaemon> acquire(
    FlutterSdkPath sdk, {
    required String runDir,
  }) async {
    var shared = _instances.putIfAbsent(
      sdk.root,
      () => _Shared(_start(sdk, runDir)),
    );
    shared.leases++;
    try {
      return await shared.daemon;
    } on Object {
      // A failed start must not be remembered as the running daemon, or every
      // later caller inherits one machine's bad minute.
      shared.leases--;
      _instances.remove(sdk.root);
      rethrow;
    }
  }

  /// Gives up one lease. The daemon stops when the last one goes.
  void release() {
    var shared = _instances[_key];
    if (shared == null) return;
    if (--shared.leases > 0) return;
    _instances.remove(_key);
    unawaited(stop());
  }

  static Future<DeviceDaemon> _start(FlutterSdkPath sdk, String runDir) async {
    var process = await Process.start(sdk.flutter, [
      'daemon',
    ], environment: const {});
    var protocol = DaemonProtocol(
      process.stdin,
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_logger.warning);

    var daemon = DeviceDaemon._(process, protocol, runDir, sdk.root);
    protocol.onEvent.listen(daemon._onEvent);
    unawaited(
      process.exitCode.then((code) {
        _logger.fine('flutter daemon exited with $code');
        daemon._stopped = true;
        // It died on its own; the leases are moot and a later acquire should
        // start a fresh one rather than await a corpse.
        _instances.remove(sdk.root);
      }),
    );

    // Discovery is off until asked for: an un-enabled daemon reports an empty
    // list forever, which is indistinguishable from an empty desk.
    await protocol.sendCommand(const DeviceEnableCommand());
    await daemon.refresh();
    return daemon;
  }

  /// Asks the daemon what it can see and republishes the cache.
  Future<List<DaemonDevice>> refresh() async {
    var found = await _protocol.sendCommand(const DeviceGetDevicesCommand());
    _devices
      ..clear()
      ..addEntries([for (var device in found) MapEntry(device.id, device)]);
    _publish();
    return devices;
  }

  void _onEvent(Event event) {
    switch (event) {
      case DeviceAddedEvent(:var device):
        _devices[device.id] = device;
        _publish();
      case DeviceRemovedEvent(:var device):
        _devices.remove(device.id);
        _publish();
      default:
        break;
    }
  }

  void _publish() {
    DeviceCache.write(_runDir, devices);
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _protocol.close();
    _process.kill();
    unawaited(_changes.close());
    await _process.exitCode;
  }
}

/// One shared daemon and the number of holders keeping it up.
class _Shared {
  _Shared(this.daemon);

  final Future<DeviceDaemon> daemon;
  var leases = 0;
}

/// The order every surface lists devices in.
///
/// Physical, connected hardware first, because that is what the cockpit exists
/// for and what a phone unplugged mid-session has to be visibly missing from.
/// Then emulators and simulators, then the always-there desktop and web
/// targets, then by name so the list is stable between polls.
int compareDevices(DaemonDevice a, DaemonDevice b) {
  var rank = _rank(a).compareTo(_rank(b));
  if (rank != 0) return rank;
  return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}

int _rank(DaemonDevice device) {
  if (!device.ephemeral) return 3;
  if (!device.isConnected) return 2;
  return device.emulator ? 1 : 0;
}
