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
    this.kind = 'physical',
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

  /// `physical`, `virtual` or `host` — the distinction [physical] cannot make
  /// on its own.
  ///
  /// `physical: false` covers both this Mac and a booted simulator, and they
  /// are nothing alike: one cannot be taken from you and stops when the run
  /// stops, the other is a contended slot somebody had to boot. A caller
  /// choosing words for a row needs to know which.
  final String kind;

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

/// `entrypoints` — the `main()`s each package can be launched from.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunEntrypointsResult implements PluginResult {
  RunEntrypointsResult({required this.packages, this.note});

  final List<RunEntrypointPackage> packages;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunEntrypointsResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunEntrypointPackage {
  RunEntrypointPackage({
    required this.path,
    required this.declared,
    this.entrypoints = const [],
  });

  /// Package path, relative to the worktree.
  final String path;

  /// True when `tool/flutterware.dart` listed these, false when they came from
  /// scanning `lib/`. Worth carrying: a scanned list is a guess that happens to
  /// be right most of the time, and a caller choosing from it should know.
  final bool declared;

  final List<RunEntrypointEntry> entrypoints;

  Map<String, Object?> toJson() => _$RunEntrypointPackageToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunEntrypointEntry {
  RunEntrypointEntry({
    required this.path,
    required this.name,
    this.description,
    this.knobs = const [],
  });

  /// Package-relative — what `launch` takes as its `entrypoint`.
  final String path;

  final String name;

  /// What it is, in a line, when the config said. `Kiosk` and `Onboarding`
  /// cannot be told apart by their file names, and this is the field that
  /// tells them apart — for a picker and for an agent alike.
  final String? description;

  final List<RunKnobEntry> knobs;

  Map<String, Object?> toJson() => _$RunEntrypointEntryToJson(this);
}

/// One `--dart-define` an entry point declares, with whatever values the tool
/// can offer for it.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunKnobEntry {
  RunKnobEntry({
    required this.define,
    this.label,
    this.description,
    this.defaultValue,
    this.options = const [],
  });

  /// The define's name, as `String.fromEnvironment` reads it.
  final String define;

  final String? label;
  final String? description;

  @JsonKey(name: 'default')
  final String? defaultValue;

  /// Everything worth offering — what the config listed, plus whatever its
  /// `from:` resolved to right now: the base URLs of the servers currently
  /// running, or this machine's addresses on the local network.
  final List<String> options;

  Map<String, Object?> toJson() => _$RunKnobEntryToJson(this);
}

/// `launch` — one run started, and how far it got.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunLaunchResult implements PluginResult {
  RunLaunchResult({
    required this.app,
    required this.status,
    required this.waited,
    this.progress,
    this.error,
    this.note,
  });

  /// The run as the ledger now holds it — the same shape `apps` reports.
  final RunAppEntry app;

  /// `running`, `starting`, `stopped`, or `failed`.
  final String status;

  /// False when the call returned without waiting for the app to come up, so
  /// [status] is what was true a moment after spawning and nothing more.
  final bool waited;

  /// The launcher's most recent narration — `Installing and launching…`. On a
  /// wireless device this can sit still for a long time while an OS permission
  /// dialog waits for somebody to notice it.
  final String? progress;

  final String? error;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunLaunchResultToJson(this);
}

/// `reload` / `restart` / `stop` — one thing done to one running app.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunControlResult implements PluginResult {
  RunControlResult({
    required this.action,
    required this.device,
    required this.entrypoint,
    required this.ok,
    this.ms = 0,
    this.error,
    this.note,
  });

  /// `reload`, `restart` or `stop`.
  final String action;

  final String device;
  final String entrypoint;

  final bool ok;

  /// Wall time, which is the number that decides whether this is worth doing
  /// instead of relaunching: a hot restart is about a second where a warm
  /// relaunch is ten on Android and twenty-three on a cabled iPhone.
  final int ms;

  final String? error;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunControlResultToJson(this);
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

/// `tree` — the widget tree of one running app.
///
/// Read through the framework's own inspector, which needs nothing in the
/// user's app. Every node carries where its widget was constructed, so a caller
/// can go from "this is wrong" to the line that built it without a second
/// lookup.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunTreeResult implements PluginResult {
  RunTreeResult({
    required this.device,
    required this.entrypoint,
    required this.nodes,
    required this.summary,
    this.root,
    this.note,
  });

  final String device;
  final String entrypoint;

  /// How many nodes the tree has, so a caller can tell an empty answer from a
  /// small one without walking it.
  final int nodes;

  /// False when the whole tree was asked for.
  ///
  /// Worth reporting because the difference is three orders of magnitude: a
  /// one-screen demo is 25 summary nodes and 517 full ones, and the full read
  /// was six megabytes.
  final bool summary;

  /// The tree itself, or null when the app has not built a frame yet.
  final Map<String, Object?>? root;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunTreeResultToJson(this);
}

/// `screenshot` — a picture of one running app.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunScreenshotResult implements PluginResult {
  RunScreenshotResult({
    required this.device,
    required this.entrypoint,
    required this.path,
    required this.bytes,
    required this.ms,
    this.note,
  });

  final String device;
  final String entrypoint;

  /// Where the PNG was written.
  ///
  /// A path rather than the bytes: a screenshot is tens of kilobytes of base64
  /// on a wire that also carries the rest of the answer, and every consumer —
  /// a terminal, an MCP client, the panel — wants a file in the end anyway.
  final String path;

  final int bytes;
  final int ms;

  /// Said out loud when the picture may not be the whole story — a run with
  /// platform views in it, which Flutter's layer tree cannot photograph.
  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunScreenshotResultToJson(this);
}

/// `logs` — what one run's launcher has written.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunLogsResult implements PluginResult {
  RunLogsResult({
    required this.device,
    required this.entrypoint,
    required this.lines,
    required this.total,
    this.path,
    this.note,
  });

  final String device;
  final String entrypoint;

  final List<RunLogEntry> lines;

  /// How many lines matched before [lines] was cut to the tail, so a caller can
  /// tell "that is all of it" from "that is the end of it".
  final int total;

  /// The log file, for anyone who would rather tail it themselves.
  final String? path;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunLogsResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunLogEntry {
  RunLogEntry({required this.source, required this.text, this.error = false});

  /// `app` for what the app printed, `tool` for what `flutter run` said about
  /// itself. A launcher log interleaves them and they answer different
  /// questions.
  final String source;

  final String text;

  /// The launcher marked it as an error. Never inferred from the text.
  final bool error;

  Map<String, Object?> toJson() => _$RunLogEntryToJson(this);
}
