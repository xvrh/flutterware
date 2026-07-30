import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import 'catalog_entry.dart';
import 'package_config_locator.dart';

part 'protocol.g.dart';

/// The wire format between a catalog client and the compiler daemon.
///
/// Line-delimited JSON over a unix socket, one connection per client. The
/// daemon serves several at once — a GUI panel and an agent taking screenshots
/// are two clients of one compiler — so every request carries an id and every
/// reply echoes it. Without that, one client's `select` would be answered to
/// whoever happened to be listening.
///
/// Every message is a typed class with a generated codec — the discriminator is
/// read once, in [DaemonRequest.decode] / [DaemonResponse.decode], and nothing
/// downstream touches a raw map.

/// Anything that can go on the wire as one line.
abstract interface class ProtocolMessage {
  /// The discriminator [DaemonRequest.decode] and [DaemonResponse.decode]
  /// dispatch on.
  String get type;

  Map<String, dynamic> toJson();
}

/// Milliseconds on the wire, a [Duration] in Dart.
class _DurationMillis implements JsonConverter<Duration, int> {
  const _DurationMillis();

  @override
  Duration fromJson(int json) => Duration(milliseconds: json);

  @override
  int toJson(Duration object) => object.inMilliseconds;
}

const _millis = _DurationMillis();

/// client → daemon.
sealed class DaemonRequest implements ProtocolMessage {
  const DaemonRequest();

  static DaemonRequest decode(Map<String, dynamic> json) =>
      switch (json['type']) {
        SelectRequest.wireName => SelectRequest.fromJson(json),
        RefreshRequest.wireName => const RefreshRequest(),
        StopDaemonRequest.wireName => const StopDaemonRequest(),
        var unknown => throw FormatException('unknown request "$unknown"'),
      };
}

/// Make [id] the active entry and compile it into the entrypoint.
@JsonSerializable()
class SelectRequest extends DaemonRequest {
  const SelectRequest(
    this.requestId,
    this.id, {
    this.full = false,
    this.ifChanged = false,
  });

  factory SelectRequest.fromJson(Map<String, dynamic> json) =>
      _$SelectRequestFromJson(json);

  static const wireName = 'select';

  /// Unique within a connection; echoed on [DaemonCompiled] so a client can
  /// tell its own reply from another client's.
  final int requestId;

  /// A [CatalogEntry.id].
  final String id;

  /// Produce a **full** kernel rather than an incremental delta.
  ///
  /// A delta only means something to an isolate that is already running, so a
  /// guest spawned from scratch — which loads the kernel out of the asset
  /// directory — needs the whole thing. Costs a cold compile; only
  /// screenshotting asks for it.
  final bool full;

  /// Do nothing unless something on disk moved.
  ///
  /// For triggers the user did not press — coming back to the window, or to
  /// the panel. A reload is not free of consequence even when it compiles to
  /// the same bytes: it reassembles the guest and resets whatever state the
  /// demo was holding. Answering "unchanged" is how a reflex stays invisible.
  final bool ifChanged;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$SelectRequestToJson(this);
}

/// Look for entries that appeared or disappeared, and tell everyone if any
/// did. Compiles nothing and reloads nothing.
///
/// What a panel asks on a timer while you are looking at it. A [SelectRequest]
/// would rescan too, but it would also compile and hand back a kernel — and a
/// catalog that quietly reloaded itself every few seconds while you were
/// mid-refactor would be its own kind of annoying.
class RefreshRequest extends DaemonRequest {
  const RefreshRequest();

  static const wireName = 'refresh';

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => const {};
}

/// Stop the daemon itself, disconnecting everyone.
///
/// Closing the socket is how a client *leaves*; this is for tooling that wants
/// the process gone. Rare on purpose — a shared daemon that any client can kill
/// is not shared.
class StopDaemonRequest extends DaemonRequest {
  const StopDaemonRequest();

  static const wireName = 'stop-daemon';

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => const {};
}

/// daemon → GUI.
sealed class DaemonResponse implements ProtocolMessage {
  const DaemonResponse();

  static DaemonResponse decode(Map<String, dynamic> json) =>
      switch (json['type']) {
        DaemonReady.wireName => DaemonReady.fromJson(json),
        DaemonCompiled.wireName => DaemonCompiled.fromJson(json),
        CatalogChanged.wireName => CatalogChanged.fromJson(json),
        AssetsChanged.wireName => AssetsChanged.fromJson(json),
        DaemonFailed.wireName => DaemonFailed.fromJson(json),
        var unknown => throw FormatException('unknown response "$unknown"'),
      };
}

/// The daemon finished the slow one-time work; the guest can be launched.
@JsonSerializable(explicitToJson: true)
class DaemonReady extends DaemonResponse {
  const DaemonReady({
    required this.sessionId,
    required this.hostPath,
    required this.assetsDir,
    required this.icuData,
    required this.coldCompile,
    required this.entries,
    this.quarantined = const [],
    this.reused = false,
    this.timings = const {},
    this.diagnostics = const [],
  });

  factory DaemonReady.fromJson(Map<String, dynamic> json) =>
      _$DaemonReadyFromJson(json);

  static const wireName = 'ready';

  /// Identifies this connection's session for the life of the daemon.
  final String sessionId;

  final String hostPath;

  /// This session's asset directory: the shared bundle by symlink, plus a
  /// `kernel_blob.bin` only this client's guest reads. Sessions do not share it
  /// because a guest launch reads that file by name, and another client's
  /// compile would otherwise decide what it finds there.
  final String assetsDir;

  final String icuData;

  @_millis
  final Duration coldCompile;

  /// True when this client attached to a daemon that was already up, and so
  /// paid for none of the work reported in [timings].
  final bool reused;

  /// What the one-time work cost, by phase. Reported rather than logged so the
  /// GUI and `fw` can show it without scraping a log.
  final Map<String, int> timings;

  /// Everything discovery found *and* the compiler can build, in tree order.
  /// The daemon owns the scan so the GUI and the CLI read one list rather than
  /// each building their own.
  final List<CatalogEntry> entries;

  /// Entries discovery found but the compiler could not build. [CatalogChanged]
  /// is how a client hears about later changes to either list.
  final List<QuarantinedEntry> quarantined;

  /// What the scan noticed but did not act on. Errors never reach here — the
  /// daemon refuses to start on those.
  final List<String> diagnostics;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$DaemonReadyToJson(this);
}

/// An entry the daemon is not serving because it does not compile.
///
/// Reported rather than dropped silently: the entrypoint imports every entry,
/// so one demo mid-edit would otherwise take the whole catalog down, and a
/// catalog that quietly shrinks is worse than one that says what broke.
@JsonSerializable(explicitToJson: true)
class QuarantinedEntry {
  const QuarantinedEntry({required this.entry, required this.error});

  factory QuarantinedEntry.fromJson(Map<String, dynamic> json) =>
      _$QuarantinedEntryFromJson(json);

  final CatalogEntry entry;

  /// The compiler's diagnostics, verbatim — what a renderer shows the user.
  final String error;

  Map<String, dynamic> toJson() => _$QuarantinedEntryToJson(this);
}

/// The set of servable entries changed.
///
/// Broadcast to every client, not just the one whose compile caused it: a panel
/// sitting idle while someone edits a demo would otherwise keep offering an
/// entry the daemon can no longer build, or keep hiding one that now works.
@JsonSerializable(explicitToJson: true)
class CatalogChanged extends DaemonResponse {
  const CatalogChanged({required this.entries, this.quarantined = const []});

  factory CatalogChanged.fromJson(Map<String, dynamic> json) =>
      _$CatalogChangedFromJson(json);

  static const wireName = 'catalog-changed';

  final List<CatalogEntry> entries;
  final List<QuarantinedEntry> quarantined;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$CatalogChangedToJson(this);
}

/// The shared asset bundle was rebuilt and something actually differed.
///
/// Broadcast like [CatalogChanged], and for the same reason: assets belong to
/// the project, not to the client whose refresh noticed them move. A session
/// hearing this evicts its guest's cached `AssetManifest.bin` and
/// reassembles, which is all an added or removed asset needs. [fontsChanged]
/// is the exception a client must treat differently: the engine registers
/// fonts once at startup, so no eviction reaches a running guest — only a
/// relaunch does.
@JsonSerializable()
class AssetsChanged extends DaemonResponse {
  const AssetsChanged({required this.fontsChanged});

  factory AssetsChanged.fromJson(Map<String, dynamic> json) =>
      _$AssetsChangedFromJson(json);

  static const wireName = 'assets-changed';

  final bool fontsChanged;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$AssetsChangedToJson(this);
}

/// The result of compiling one entry into the accumulating entrypoint.
@JsonSerializable()
class DaemonCompiled extends DaemonResponse {
  const DaemonCompiled({
    required this.requestId,
    required this.id,
    required this.compile,
    required this.newSourceCount,
    this.editedCount = 0,
    this.unchanged = false,
    this.dill,
    this.error,
  });

  factory DaemonCompiled.fromJson(Map<String, dynamic> json) =>
      _$DaemonCompiledFromJson(json);

  static const wireName = 'compiled';

  /// The [SelectRequest.requestId] this answers.
  final int requestId;

  final String id;

  /// The kernel to hand the VM service as `rootLibUri`. Null when [ok] is
  /// false — the guest keeps rendering whatever it had.
  ///
  /// Written per request rather than to one well-known path: the compiler
  /// always writes its delta to the same file, so a reply that named it would
  /// be overwritten by the next client's compile before this client's guest had
  /// read it.
  final String? dill;

  @_millis
  final Duration compile;

  /// How many libraries this compile added; ~0 when revisiting an entry the
  /// compiler has already seen.
  final int newSourceCount;

  /// How many source files the daemon found edited and invalidated for this
  /// compile.
  ///
  /// Worth showing: a reload of zero edited files is a legitimate outcome —
  /// nothing was saved — but it is also what a broken invalidation sweep looks
  /// like, and the two are indistinguishable from the pixels.
  final int editedCount;

  /// Compiler diagnostics when the entry did not build.
  final String? error;

  /// The daemon did nothing, because a [SelectRequest.ifChanged] found nothing
  /// to do. Neither success nor failure: there is no kernel, and the client
  /// should leave its guest exactly as it is.
  final bool unchanged;

  bool get ok => error == null && dill != null;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$DaemonCompiledToJson(this);
}

/// The daemon could not start. Terminal: it exits after sending this.
@JsonSerializable()
class DaemonFailed extends DaemonResponse {
  const DaemonFailed({required this.message, this.stackTrace});

  factory DaemonFailed.fromJson(Map<String, dynamic> json) =>
      _$DaemonFailedFromJson(json);

  static const wireName = 'failed';

  final String message;
  final String? stackTrace;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$DaemonFailedToJson(this);

  @override
  String toString() => stackTrace == null ? message : '$message\n$stackTrace';
}

/// What the daemon needs to start, handed over as a file rather than argv so
/// the entry list has somewhere to live.
@JsonSerializable(explicitToJson: true)
class DaemonConfig {
  const DaemonConfig({
    required this.appPackageRoot,
    required this.projectRoot,
    required this.packageConfig,
    required this.flutterSdkRoot,
    this.roots = const ['demo'],
    this.previewAnnotations = const ['Preview', 'Demo'],
    this.emitProbe = false,
    this.trackWidgetCreation = true,
    this.daemonRevision = '',
  });

  factory DaemonConfig.fromJson(Map<String, dynamic> json) =>
      _$DaemonConfigFromJson(json);

  /// **The one place a config is built for a declared package.** Every renderer
  /// goes through here — the GUI's [CatalogSession], `fw`'s [HeadlessCatalog],
  /// and an agent over MCP.
  ///
  /// It exists because the alternative was tried and failed. The GUI and `fw`
  /// each built their own config for the same package and disagreed about one
  /// field — the GUI passed the app tool directory as [appPackageRoot], `fw`
  /// passed the package itself — so they hashed to different [DaemonAddress]
  /// keys and *never shared a compiler daemon*, despite that being the whole
  /// reason the daemon is a separate process. Worse, `fw`'s value sent the
  /// launch machinery looking for `tool/catalog/compiler_daemon.dart` inside the
  /// user's project, where it does not exist.
  ///
  /// Nothing about that was catchable by reading either call site: both were
  /// locally reasonable, and the field name reads like the second one. So the
  /// two roots are named apart *here*, once, and the address invariant is a test
  /// rather than a convention — see `test/catalog/daemon_config_test.dart`.
  ///
  /// [appToolDirectory] is flutterware's own `app/` install; [packageRoot] is
  /// the package whose demos are being catalogued. They are the same directory
  /// only when cataloguing flutterware itself.
  factory DaemonConfig.forPackage({
    required String appToolDirectory,
    required String packageRoot,
    required String flutterSdkRoot,
    required List<String> roots,
    bool emitProbe = false,
  }) => DaemonConfig(
    appPackageRoot: appToolDirectory,
    projectRoot: packageRoot,
    // The *project's* config, not the app's: it is the one that resolves the
    // demos' own package as well as flutter and flutterware.
    packageConfig: requirePackageConfig(packageRoot),
    flutterSdkRoot: flutterSdkRoot,
    roots: roots,
    emitProbe: emitProbe,
  );

  /// flutterware's own `app/` directory — **not** the package being
  /// catalogued.
  ///
  /// It is where the daemon's own machinery lives: the daemon script and its
  /// snapshot, the embedder framework under `.engine/`, the C host sources
  /// under `native/`, and the per-address build directory. A value pointing at
  /// the user's project makes every one of those resolve to a path that does
  /// not exist.
  ///
  /// Build configs through [DaemonConfig.forPackage] rather than naming this
  /// directly; the constructor is public only because the daemon has to decode
  /// the config it is handed.
  final String appPackageRoot;

  final String projectRoot;
  final String packageConfig;

  /// The Flutter checkout the guest is built and compiled against.
  ///
  /// Passed explicitly rather than derived from the running executable: once
  /// the daemon is precompiled, `Platform.resolvedExecutable` is the daemon
  /// binary and knows nothing about any SDK.
  final String flutterSdkRoot;

  /// Directories to scan for entries, relative to [projectRoot].
  final List<String> roots;

  /// Annotation names that mark an entry. Recognition is by registration.
  final List<String> previewAnnotations;

  /// Makes the generated guest print a periodic `FW-PROBE:` line naming the
  /// live entry and the text it renders. Used by the headless check.
  final bool emitProbe;

  /// Compiles with `--track-widget-creation`, which stamps every widget with
  /// the source location that built it.
  ///
  /// On by default. Without it the inspector's *summary* tree is not a smaller
  /// tree — it is byte-for-byte the full one, because "created by user code" is
  /// exactly the creation location it has no way to read. Measured on this
  /// repo's demos: `dashboard` is 695 nodes either way with it off, and 51 with
  /// it on, ~82% of them resolving into the demo's own source.
  ///
  /// The cost was measured before this defaulted to true: +4% on a cold
  /// compile, +0.7% on the kernel, and **no measurable change to a hot reload**
  /// — the first-pass median was identical to the millisecond over 19 entry
  /// switches. See `2026-07-29-ui-catalog-inspection-design.md`.
  ///
  /// It is a field rather than a constant so the daemon address forks on it: a
  /// kernel compiled one way must never prime a compiler running the other.
  final bool trackWidgetCreation;

  /// Identifies the daemon *build*. Set by the client, never by a caller.
  ///
  /// A daemon outlives the session that started it, and nothing restarts one
  /// when its own code changes — so without this, editing the daemon and
  /// re-running silently reuses the old behaviour. That is not a
  /// developer-only annoyance: the daemon decides what goes into a hot-reload
  /// delta, and an older one can hand a guest a delta missing a library the
  /// guest never had, which surfaces as `lookup Failed: <name> in ...` from
  /// the VM.
  ///
  /// It lives here rather than beside the config so that *both* sides derive
  /// the same [DaemonAddress] from the same bytes — the daemon computes its
  /// own address from the config file it is handed, and anything the client
  /// keeps to itself would put them on different sockets.
  final String daemonRevision;

  DaemonConfig withDaemonRevision(String revision) => DaemonConfig(
    appPackageRoot: appPackageRoot,
    projectRoot: projectRoot,
    packageConfig: packageConfig,
    flutterSdkRoot: flutterSdkRoot,
    roots: roots,
    previewAnnotations: previewAnnotations,
    emitProbe: emitProbe,
    trackWidgetCreation: trackWidgetCreation,
    daemonRevision: revision,
  );

  Map<String, dynamic> toJson() => _$DaemonConfigToJson(this);
}

/// Encodes one message as a protocol line, discriminator included.
String encodeLine(ProtocolMessage message) =>
    jsonEncode({'type': message.type, ...message.toJson()});

/// Decodes a protocol line, or null when it is not JSON at all — a daemon that
/// prints something unexpected should not take the session down with it.
Map<String, dynamic>? tryDecodeLine(String line) {
  if (line.trim().isEmpty) return null;
  try {
    var decoded = jsonDecode(line);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
