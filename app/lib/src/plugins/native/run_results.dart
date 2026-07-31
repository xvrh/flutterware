import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'run_results.g.dart';

/// `devices` — everything this machine can run an app on, and who is already
/// running one on it.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunDevicesResult implements PluginResult {
  RunDevicesResult({
    required this.devices,
    required this.live,
    this.updatedAt,
    this.age,
    this.note,
  });

  final List<RunDeviceEntry> devices;

  /// True when a `flutter daemon` is running in this process, so the list is
  /// what it saw rather than what somebody wrote down earlier.
  final bool live;

  /// When the list was taken, ISO-8601. Absent only when nothing has ever
  /// taken one.
  final String? updatedAt;

  /// [updatedAt] as a phrase — `just now`, `12m ago`. Present for the same
  /// reason the field above is: a device list without an age is a claim, and
  /// this one is a reading.
  final String? age;

  /// Said out loud when the list is empty or stale enough to explain, rather
  /// than left for the caller to infer from an empty array.
  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunDevicesResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunDeviceEntry {
  RunDeviceEntry({
    required this.id,
    required this.name,
    required this.connected,
    this.platform,
    this.sdk,
    this.emulator = false,
    this.physical = true,
    this.connection,
    this.running = const [],
  });

  /// What `flutter run -d` takes.
  final String id;

  final String name;

  /// `ios`, `android`, `macos`, `web` — the family, not the architecture.
  final String? platform;

  /// `iOS 18.5`, `Android 12 (API 31)`.
  final String? sdk;

  final bool emulator;

  /// False for the always-there targets — this desktop, the browser — which
  /// cannot be unplugged and are never contended for in the way a phone is.
  final bool physical;

  /// Known but not reachable right now. A wireless phone that went to sleep
  /// stays in the list and stops being launchable.
  final bool connected;

  /// `attached` for a cable or a built-in target, `wireless` over the network.
  /// Worth knowing before launching: on the same phone a hot reload measured
  /// 289ms over a cable and 1571ms over wifi.
  final String? connection;

  /// The runs currently holding this device, from any worktree. Empty means
  /// free.
  ///
  /// More than one is possible and is not an error — two apps can share a
  /// phone. It is reported rather than prevented, because launching onto a
  /// busy device is sometimes exactly what was meant.
  final List<RunHolder> running;

  Map<String, Object?> toJson() => _$RunDeviceEntryToJson(this);
}

/// One run's claim on a device, as another worktree sees it.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunHolder {
  RunHolder({
    required this.worktree,
    required this.entrypoint,
    required this.since,
    this.package,
    this.entrypointName,
    this.canReload = false,
    this.canInspect = false,
  });

  /// The worktree name — `~` for the main checkout.
  final String worktree;

  /// Package-relative entry point, `lib/main.dart`.
  final String entrypoint;

  /// Its declared name, when it has one.
  final String? entrypointName;

  /// The package, relative to the worktree.
  final String? package;

  /// When the run started, ISO-8601.
  final String since;

  /// Reload and restart are still on offer — meaning both the app and the
  /// `flutter run` that launched it are alive.
  final bool canReload;

  /// The app answers on its VM service: it can be inspected and driven even
  /// if its launcher is gone.
  final bool canInspect;

  Map<String, Object?> toJson() => _$RunHolderToJson(this);
}

/// `apps` — every run announcing itself under the run dir, probed.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunAppsResult implements PluginResult {
  RunAppsResult({required this.apps, this.swept = 0, this.note});

  final List<RunAppEntry> apps;

  /// Handles deleted during this call because nothing answered them. Reported
  /// rather than done quietly: a run vanishing is a thing that happened, and a
  /// list that silently shrinks is how a phone appears to free itself.
  final int swept;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunAppsResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunAppEntry {
  RunAppEntry({
    required this.device,
    required this.worktree,
    required this.entrypoint,
    required this.since,
    required this.app,
    required this.launcher,
    this.deviceName,
    this.package,
    this.entrypointName,
    this.knobs = const {},
    this.vmService,
    this.log,
    this.error,
    this.mine = false,
  });

  final String device;
  final String? deviceName;

  /// The worktree name — `~` for the main checkout.
  final String worktree;

  /// True when that worktree is the one this call was made from. The cockpit
  /// shows other people's runs on purpose, so which are yours has to be a
  /// field rather than an assumption.
  final bool mine;

  final String? package;
  final String entrypoint;
  final String? entrypointName;

  /// The dart-defines it was built with. Part of the identity of what is
  /// running: changing one costs a rebuild, so two runs of the same entry
  /// point with different knobs are not the same thing.
  final Map<String, String> knobs;

  /// When it started, ISO-8601.
  final String since;

  /// The app answered on its VM service — it can be inspected and driven.
  final bool app;

  /// The `flutter run` that launched it is still alive, which is what makes
  /// reload and restart available: those are registered by the tool, not by
  /// the app, and they go away with it.
  final bool launcher;

  final String? vmService;

  /// Where the launcher's output is being written, for a client that arrived
  /// after the interesting part scrolled past.
  final String? log;

  /// Why the app did not answer, when it did not — a live launcher with a
  /// silent app is a real state, and the reason is the only lead.
  final String? error;

  Map<String, Object?> toJson() => _$RunAppEntryToJson(this);
}
