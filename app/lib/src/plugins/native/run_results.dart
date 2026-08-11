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
    this.flavor,
    this.flavorSource,
    this.platforms = const [],
    this.devices = const [],
    this.defines = const [],
  });

  /// Package-relative — what `launch` takes as its `entrypoint`.
  final String path;

  final String name;

  /// What it is, in a line, when the config said. `Kiosk` and `Onboarding`
  /// cannot be told apart by their file names, and this is the field that
  /// tells them apart — for a picker and for an agent alike.
  final String? description;

  /// The `--flavor` this entry point will be built with when nobody overrides
  /// it — its own declaration, or the package's `flutter: default-flavor:`.
  ///
  /// Reported because a flavoured project **cannot be launched without one** —
  /// it is not a preference the caller may skip, and an agent that does not
  /// pass it gets a build failure rather than a default.
  final String? flavor;

  /// `entrypoint` or `pubspec` — which of the two put [flavor] there.
  ///
  /// Absent when nothing declared one. Worth a field because the two are
  /// overridden with different confidence: a pubspec default is the project's
  /// blanket answer, while an entry point's is a pairing somebody wrote down.
  final String? flavorSource;

  /// What this entry point declares it can run on, as the config wrote it —
  /// `mobile` stays `mobile`. Empty means anything.
  final List<String> platforms;

  /// The ids of the devices currently connected that [platforms] allows.
  ///
  /// The expansion done for you, against the desk as it is right now: a caller
  /// picking an entry point and a device in one go should not have to know
  /// that `desktop` means three platforms, nor which of them is plugged in.
  final List<String> devices;

  final List<DartDefineEntry> defines;

  Map<String, Object?> toJson() => _$RunEntrypointEntryToJson(this);
}

/// One `--dart-define` an entry point declares, with whatever values the tool
/// can offer for it.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class DartDefineEntry {
  DartDefineEntry({
    required this.name,
    this.label,
    this.description,
    this.defaultValue,
    this.options = const [],
    this.kind,
    this.readAt,
    this.problem,
  });

  /// The name `String.fromEnvironment` reads.
  @JsonKey(name: 'define')
  final String name;

  final String? label;
  final String? description;

  @JsonKey(name: 'default')
  final String? defaultValue;

  /// Everything worth offering — what the config listed, plus whatever its
  /// `from:` resolved to right now, such as this machine's addresses on the
  /// local network or a list a script in the project printed.
  final List<String> options;

  /// `String`, `int`, `bool` or `double` — how the app's own source reads this
  /// define. Absent when nothing reads it.
  ///
  /// Found by parsing, not by building. It is the difference between a text
  /// field and a checkbox, and it catches a config offering two string options
  /// for a `bool.fromEnvironment`, where both of them mean false.
  final String? kind;

  /// The package-relative file the read is in. Absent when nothing reads it.
  final String? readAt;

  /// What is wrong with this define, when something is.
  ///
  /// Two things are worth saying, and they are both the expensive kind — the
  /// kind that compiles, launches, and looks exactly like working:
  ///
  /// - **A script source that could not answer.** The value it was supposed to
  ///   compute is baked into the build, so falling back would produce an app
  ///   that is wrong in a way nothing on screen shows. A launch that does not
  ///   set the define explicitly is refused while this says something.
  /// - **A declared define the app never reads.** The control appears in the
  ///   cockpit and turning it does nothing at all, which is indistinguishable
  ///   from a feature that does not work.
  final String? problem;

  Map<String, Object?> toJson() => _$DartDefineEntryToJson(this);
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
    this.headline,
    this.logPath,
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

  /// Why it failed, in the launcher's own words and in full.
  ///
  /// Multi-line on purpose. A build failure is a block — the fault, the file
  /// it is in, and usually the steps that fix it — and the one line the tool
  /// ends on (`App failed to start`) is the only part of it that says nothing.
  final String? error;

  /// [error]'s first line that names a fault, for a row with no room for the
  /// rest.
  final String? headline;

  /// Where the whole thing is, since [error] is bounded and a launcher that
  /// died in an unusual way may have put the interesting part above the cut.
  ///
  /// Present only on a failure — the handle is deleted when a launch fails, so
  /// this path is the last thing pointing at what happened.
  final String? logPath;

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
    this.defines = const {},
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
  /// point with different defines are not the same thing.
  final Map<String, String> defines;

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

/// `emulators` — everything this machine could boot, booted or not.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunEmulatorsResult implements PluginResult {
  RunEmulatorsResult({required this.emulators, this.note});

  final List<RunEmulatorEntry> emulators;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunEmulatorsResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunEmulatorEntry {
  RunEmulatorEntry({
    required this.id,
    required this.name,
    this.booted,
    this.platform,
  });

  /// What `bootEmulator` takes.
  final String id;

  final String name;

  /// `ios` or `android`.
  final String? platform;

  /// True when it is already up, false when it is not — and **null when the
  /// question has no answer for this row**.
  ///
  /// Null is the iOS case, and it is not a gap in the lookup. The daemon lists
  /// exactly one iOS entry, `apple_ios_simulator`, which is not a machine but a
  /// door: booting it opens the Simulator, which can already be running several
  /// devices under names of their own (`iPhone 16e`). Nothing links the two, so
  /// "is it booted" is a question about a thing that does not exist. Measured —
  /// reporting `false` there meant claiming an offline simulator while
  /// `devices` listed a booted one two lines away.
  ///
  /// Android does answer it: a device carries the `emulatorId` it was booted
  /// from.
  final bool? booted;

  Map<String, Object?> toJson() => _$RunEmulatorEntryToJson(this);
}

/// `bootEmulator` — starting one, and what came up.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunBootResult implements PluginResult {
  RunBootResult({
    required this.emulator,
    required this.started,
    required this.ms,
    this.device,
    this.deviceName,
    this.note,
  });

  final String emulator;

  /// The daemon accepted the launch. Says nothing about whether it came up.
  final bool started;

  /// The device id it appeared as, once it did. Null when the wait ran out —
  /// which is not the same as a failure, and [note] says so.
  final String? device;
  final String? deviceName;

  final int ms;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunBootResultToJson(this);
}

/// `inspect` — one reading of one run.
///
/// **One action rather than three, and the reason is the app moves.** A tree
/// read by one call and a picture taken by the next are two moments of a live
/// app — two readings that happen to agree, or quietly do not. Everything here
/// comes off a single connection, and the tree and the picture off a single
/// inspector group. The catalog reached the same conclusion first; see
/// `ui_catalog_core.dart`'s `inspect`.
///
/// **Answers something even when the app is not up.** A cold build is minutes
/// during which nothing can be asked of the app — and is exactly when the logs
/// are the only thing worth reading. So [up] is a field rather than an error.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunInspectResult implements PluginResult {
  RunInspectResult({
    required this.device,
    required this.entrypoint,
    required this.up,
    required this.reloadable,
    this.worktree,
    this.mine,
    this.tree,
    this.nodes,
    this.summary,
    this.screenshot,
    this.logs,
    this.logLines,
    this.errors,
    this.progress,
    this.log,
    this.note,
  });

  final String device;
  final String entrypoint;

  /// The worktree holding it, and whether that is the one asking. A run from
  /// another checkout is readable and not drivable.
  final String? worktree;
  final bool? mine;

  /// The app answered its VM service, so the tree and the picture are
  /// available. False during a build, and after a crash.
  final bool up;

  /// The `flutter run` that launched it is alive, so it can still be reloaded.
  /// Independent of [up]: an app outlives its launcher and keeps everything
  /// except reload.
  final bool reloadable;

  /// The launcher's most recent progress line, when it is still building —
  /// the only narration a ninety-second build has.
  final String? progress;

  /// The widget tree, when asked for.
  final Map<String, Object?>? tree;

  /// How many nodes it has, so a caller can tell an empty answer from a small
  /// one without walking it.
  final int? nodes;

  /// False when the whole tree was asked for rather than the summary. Worth
  /// reporting: a one-screen app is 25 summary nodes and 517 full ones.
  final bool? summary;

  /// Where the PNG was written, when one was asked for.
  ///
  /// A path rather than the bytes: a picture is tens of kilobytes of base64 on
  /// a wire carrying the rest of this answer, and every consumer wants a file
  /// in the end.
  final String? screenshot;

  /// Log lines, when asked for.
  final List<RunLogEntry>? logs;

  /// How many lines matched before [logs] was cut to the tail.
  final int? logLines;

  /// Lines the launcher marked as errors. Reported by default, because with no
  /// other flag "did it break" is the question worth asking first.
  final List<RunLogEntry>? errors;

  /// The launcher's log file, for anyone who would rather tail it themselves.
  final String? log;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunInspectResultToJson(this);
}

/// `act` / `observe` / `navigate` — one drive transaction against a running
/// app, and the observation that closes it.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunActResult implements PluginResult, ProducesArtifacts {
  RunActResult({
    required this.device,
    required this.entrypoint,
    required this.verb,
    required this.ok,
    this.screenshotArtifact,
    this.worktree,
    this.target,
    this.error,
    this.failure,
    this.attempts,
    this.elapsedMs,
    this.settled,
    this.settleMs,
    this.frames,
    this.framesEnabled,
    this.lifecycle,
    this.human,
    this.texts,
    this.tree,
    this.nodes,
    this.screenshot,
    this.logs,
    this.errors,
    this.journal,
    this.note,
  });

  final String device;
  final String entrypoint;
  final String? worktree;

  final String verb;

  /// The target as the guest described it — the same spelling the refusal
  /// and the journal use.
  final String? target;

  /// The verb landed. False means it was refused — and the observation
  /// fields below still describe the screen the refusal happened on.
  final bool ok;

  /// The refusal, written to say what to do next.
  final String? error;

  /// Which way it was refused: `notFound`, `multiple`, `covered`,
  /// `offscreen`.
  final String? failure;

  /// Resolve attempts the actionability retry ladder spent; 1 when the first
  /// try reached the target. A route transition costs a handful.
  final int? attempts;

  /// The whole transaction: retries + act + settle.
  final int? elapsedMs;

  /// False means the settle budget ran out with the app still animating — a
  /// spinner, an infinite animation. Reported, never thrown.
  final bool? settled;

  final int? settleMs;
  final int? frames;

  /// False when the platform has the window hidden or occluded: every frame
  /// was forced, and what a human sees on screen may lag what these fields
  /// describe.
  final bool? framesEnabled;

  final String? lifecycle;

  /// What the human did in the app since the previous step — `tap "Pay"`,
  /// oldest first. Recorded by the guest, journaled as `actor: human`; the
  /// co-driving premise made legible instead of a silently moved screen.
  final List<String>? human;

  /// Every Text and text field on screen after the settle — the projection an
  /// agent reasons about next to the picture.
  final List<String>? texts;

  /// The widget tree, when asked for.
  final Map<String, Object?>? tree;
  final int? nodes;

  /// Where the step's PNG was written — under the run's journal directory,
  /// one file per step.
  final String? screenshot;

  /// What the app printed during this step — since the previous act call,
  /// not since launch.
  final List<RunLogEntry>? logs;

  /// Framework errors this step produced or repeated.
  final List<RunLogEntry>? errors;

  /// The run's journal file this step was appended to.
  final String? journal;

  final String? note;

  /// The step's PNG as a job artifact, so a surface that renders images —
  /// MCP first — shows the moment rather than a path. The JSON keeps the
  /// path either way.
  @JsonKey(includeToJson: false)
  final Artifact? screenshotArtifact;

  @override
  @JsonKey(includeToJson: false)
  List<Artifact> get artifacts => [?screenshotArtifact];

  @override
  Map<String, Object?> toJson() => _$RunActResultToJson(this);
}

/// `panels` — what the running app says it offers, from its own devbar
/// plugins.
///
/// **The descriptors travel raw.** They are already published JSON — the same
/// `PanelDescriptor.toJson` the cockpit decodes — and re-modelling them here
/// would be a second model of the app's declaration, kept in step by hand.
/// `panel_client.dart` refuses that for the same reason.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunPanelsResult implements PluginResult {
  RunPanelsResult({
    required this.device,
    required this.entrypoint,
    required this.panels,
    this.events = const {},
    this.note,
  });

  final String device;
  final String entrypoint;

  /// One `PanelDescriptor` per panel: its knobs with their live values, its
  /// actions with their parameters, its states and its feeds.
  final List<Map<String, Object?>> panels;

  /// Recent feed events, keyed `<panel>/<feed>` — the same channel name the
  /// descriptor gives. Oldest first, capped by the `events` argument.
  final Map<String, List<Map<String, Object?>>> events;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunPanelsResultToJson(this);
}

/// One call against one panel: an action run, a knob set, a state read.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RunPanelResult implements PluginResult {
  RunPanelResult({
    required this.device,
    required this.entrypoint,
    required this.panel,
    required this.result,
    this.knobs,
    this.note,
  });

  final String device;
  final String entrypoint;
  final String panel;

  /// What the app answered. For an action, whatever its handler returned; for
  /// a state, the snapshot.
  final Map<String, Object?> result;

  /// The panel's knobs **after** the call — what the app now holds, which is
  /// not always what was asked for: an app may clamp a value or refuse it.
  /// Only on `panelKnob`.
  final List<Map<String, Object?>>? knobs;

  final String? note;

  @override
  Map<String, Object?> toJson() => _$RunPanelResultToJson(this);
}
