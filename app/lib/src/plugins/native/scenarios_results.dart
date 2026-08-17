import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart' show InspectStyle;
// ignore: implementation_imports
import 'package:flutterware/src/inspect/screen.dart';
import 'package:json_annotation/json_annotation.dart';

// The one thing in this file that needs a filesystem, behind the one seam that
// lets the rest of it compile for the web. The exported scenario page renders
// these very classes in a browser, where there is no `dart:io` to import — see
// `2026-08-11-scenario-web-export-design.md`.
import 'scenario_step_events_web.dart'
    if (dart.library.io) 'scenario_step_events_io.dart';

part 'scenarios_results.g.dart';

/// `list` — every scenario of every requested package, from the syntactic
/// scan.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioListResult implements PluginResult {
  ScenarioListResult({required this.packages});

  final List<ScenarioListPackage> packages;

  @override
  Map<String, Object?> toJson() => _$ScenarioListResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioListPackage {
  ScenarioListPackage({
    required this.path,
    required this.directory,
    this.scenarios = const [],
    this.diagnostics = const [],
    this.error,
    this.authoring,
  });

  final String path;

  /// The scanned directory, relative to the package.
  final String directory;

  final List<ScenarioListEntry> scenarios;

  /// What the scan noticed but could not act on — non-literal names,
  /// duplicates. Empty is the healthy case.
  final List<String> diagnostics;

  /// Set when the package could not be scanned, in which case [scenarios]
  /// means nothing.
  final String? error;

  /// How to write one — present only when this package has none, which is
  /// exactly when the reader needs it and never when it would be noise. The
  /// answer to "an agent can run scenarios but cannot find out how to write
  /// one".
  final String? authoring;

  Map<String, Object?> toJson() => _$ScenarioListPackageToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioListEntry {
  ScenarioListEntry({
    required this.name,
    required this.file,
    required this.line,
  });

  final String name;

  /// Package-relative source file.
  final String file;

  final int line;

  Map<String, Object?> toJson() => _$ScenarioListEntryToJson(this);
}

/// `run` — scenarios executed in the runner's `flutter_tester`, with one
/// artifact triple (PNG, widget tree, texts) per captured step.
///
/// Readable back, unlike most results here: the web export writes one of these
/// beside the page as `report.json` and the viewer parses it into the same
/// widgets the panel draws. A result shape with only one direction would have
/// meant a second model to keep in step with this one.
/// What a run writes beside its artifacts: itself, whole, in this shape.
///
/// Named next to the model rather than next to the writer, because reading it
/// back is the point — `ScenarioRunResult.fromJson` on this file is the other
/// half of an answer that summarised.
const scenarioRunReportFile = 'run.json';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ScenarioRunResult
    implements PluginResult, ReportsFailure, ProducesArtifacts {
  ScenarioRunResult({required this.packages, this.axes});

  factory ScenarioRunResult.fromJson(Map<String, dynamic> json) =>
      _$ScenarioRunResultFromJson(json);

  final List<ScenarioRunPackage> packages;

  /// False when any package failed to run at all, or any scenario it ran came
  /// back red — what makes `fw run scenarios run` exit 1.
  @override
  bool get ok => packages.every(
    (p) => p.error == null && p.scenarios.every((scenario) => scenario.ok),
  );

  /// The frame just before each failure, and nothing else.
  ///
  /// Every step's PNG is on the wire as a path already; the reader that can
  /// open files opens them. This is for the reader that cannot — an MCP client
  /// with no filesystem — and for the one that can but should not have to
  /// guess which of fifty pictures matters. A green run offers none: there is
  /// nothing to look at.
  @override
  @JsonKey(includeToJson: false)
  List<Artifact> get artifacts => [
    for (var package in packages)
      for (var scenario in package.scenarios)
        if (!scenario.ok && scenario.steps.isNotEmpty)
          if (scenario.steps.last case var step when step.format == 'png')
            Artifact(
              kind: Artifact.png,
              address: Address.parse(step.address),
              path: step.image,
              meta: {
                'scenario': scenario.name,
                'file': scenario.file,
                'step': step.index,
                'name': ?step.name,
                'texts': step.texts,
                // The failing transition in full, `system` and all — the
                // digest every step carries is capped and filtered, and this
                // is the one step where the thing that broke it may be the
                // twentieth line. Same reasoning as the frame itself: the
                // reader should not have to make a second call for the answer.
                if (readStepEvents(step) case var events when events.isNotEmpty)
                  'events': events,
                if (scenario.errors.firstOrNull case var error?)
                  'error': error.error,
              },
            ),
  ];

  /// The axis assignment the whole request ran under —
  /// `{device: iphone-se, language: fr}` — or null for the test defaults.
  /// Recorded because a screenshot is under-specified without it; the same
  /// values ride every step's address as query parameters.
  final Map<String, String>? axes;

  @override
  Map<String, Object?> toJson() => _$ScenarioRunResultToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ScenarioRunPackage {
  factory ScenarioRunPackage.fromJson(Map<String, dynamic> json) =>
      _$ScenarioRunPackageFromJson(json);

  ScenarioRunPackage({
    required this.path,
    required this.output,
    this.axes,
    this.ms = 0,
    this.scenarios = const [],
    this.report,
    this.error,
  });

  final String path;

  /// Where this run's artifacts were written.
  final String output;

  /// The whole run, on disk, in this same shape — every step of every
  /// scenario, whatever this copy carries.
  ///
  /// **Because the whole thing does not fit in an answer.** A full suite across
  /// a 2×2 matrix is 160 steps and 60k tokens of paths, past anything a client
  /// hands a model, and most of it is about scenarios that passed. So the
  /// answer summarises and the file keeps everything: one read when a reader
  /// wants a step it was not given, and no read at all in the ordinary case
  /// where the answer is "20 scenarios, all green".
  final String? report;

  /// The assignment **this** entry ran under, when the request asked for a
  /// matrix (`devices=` / `languages=`): one entry per package per point of
  /// it, each with its own [output]. Null for a single-assignment run, where
  /// `ScenarioRunResult.axes` already says it once.
  final Map<String, String>? axes;

  /// Whole-run wall time inside the harness.
  final int ms;

  final List<ScenarioRunOutcome> scenarios;

  /// Set when the package could not be run at all — the harness did not
  /// compile, the tester did not start — in which case [scenarios] is empty.
  final String? error;

  Map<String, Object?> toJson() => _$ScenarioRunPackageToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ScenarioRunOutcome {
  factory ScenarioRunOutcome.fromJson(Map<String, dynamic> json) =>
      _$ScenarioRunOutcomeFromJson(json);

  ScenarioRunOutcome({
    required this.file,
    required this.name,
    required this.ok,
    this.device,
    this.ms = 0,
    this.steps = const [],
    this.stepCount = 0,
    this.errors = const [],
  });

  final String file;
  final String name;
  final bool ok;

  /// The device it actually ran as. Worth saying because a run that named no
  /// device gets one per folder — whatever profile the scenario's
  /// `flutter_test_config.dart` declares — so two scenarios of the same run
  /// can differ here.
  final String? device;

  final int ms;
  final List<ScenarioRunStep> steps;

  /// How many steps the scenario captured — which is [steps]`.length` unless
  /// they were left out of this copy.
  ///
  /// Carried separately so a trimmed answer cannot be read as an empty one: a
  /// green scenario whose steps went to the file on disk still says it took
  /// five pictures. See `ScenarioRunPackage.report`.
  final int stepCount;

  /// The failure, when [ok] is false. The last captured step is the frame
  /// just before it.
  final List<ScenarioRunError> errors;

  /// This outcome with [keep] of its steps; the rest are on disk.
  ScenarioRunOutcome carrying(List<ScenarioRunStep> keep) => ScenarioRunOutcome(
    file: file,
    name: name,
    ok: ok,
    device: device,
    ms: ms,
    steps: keep,
    stepCount: stepCount,
    errors: errors,
  );

  /// This outcome with its steps left on disk.
  ScenarioRunOutcome withoutSteps() => carrying(const []);

  /// This outcome carrying only the frame the failure was captured at — the
  /// last one, per [errors]. The trail that led there is in the file.
  ScenarioRunOutcome withFailingStepOnly() =>
      steps.isEmpty ? this : carrying([steps.last]);

  Map<String, Object?> toJson() => _$ScenarioRunOutcomeToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ScenarioRunStep {
  factory ScenarioRunStep.fromJson(Map<String, dynamic> json) =>
      _$ScenarioRunStepFromJson(json);

  ScenarioRunStep({
    required this.index,
    required this.position,
    required this.auto,
    required this.image,
    required this.format,
    required this.width,
    required this.height,
    required this.tree,
    required this.texts,
    required this.address,
    this.root = '',
    this.semantics,
    this.parent,
    this.branch,
    this.name,
    this.action,
    this.tags = const [],
    this.statusBrightness,
    this.navBrightness,
    this.verb,
    this.target,
    this.events,
    this.eventCount,
    this.eventChannels,
    this.eventTitles,
    this.eventsDropped,
    this.frames,
    this.frameCount,
    this.frameWidth,
    this.frameHeight,
    this.frameIntervalMs,
    this.framesDropped,
    this.settled = true,
    this.landed = true,
    this.strayFrames = 0,
    this.failure,
    this.attachments = const [],
  });

  /// 1-based position in the scenario's capture sequence.
  final int index;

  /// Where the step sits in the scenario's *shape* — the `split` choices
  /// taken to reach it by index, then the count since the last one: `'#2'` on
  /// the trunk, `'0.1#3'` two splits deep. Unlike [index] it shifts only
  /// within its own branch when a step is inserted.
  final String position;

  /// The [index] of the step this one follows; null for the scenario's
  /// first. `split` gives one parent several children — these are the flow
  /// graph's edges.
  final int? parent;

  /// The `split` branch label when this step is a branch's first capture.
  final String? branch;

  /// The `Shot`'s name; null for an automatic capture.
  final String? name;

  /// True when nothing named this capture — a collapsible detail step.
  final bool auto;

  /// The verb that produced this capture. What an unnamed step is labelled
  /// with, in place of its index.
  final ScenarioStepAction? action;

  final List<String> tags;

  /// The captured image, in [format], **relative to the worktree root** — the
  /// same convention the catalog's artifacts follow, so the value survives
  /// being read on another machine and an agent whose tools are scoped to the
  /// repo can open it. [imageFile] is the local absolute path.
  final String image;

  /// `png`, or `raw` — bare rgba8888 rows, [width]×[height]×4 bytes. Raw is
  /// the fast capture (~5× at 1×, ~25× at device resolution) for hosts that
  /// can display pixels directly; `png` is the portable default the `run`
  /// action serves.
  final String format;

  final int width;
  final int height;

  /// The widget-tree JSON captured at the same moment, relative like [image].
  final String tree;

  /// The semantics-tree JSON — what a screen reader gets — relative like
  /// [image]. Null on artifacts from before the capture existed, and when the
  /// run had no semantics tree to read; the tab states the absence rather
  /// than inventing an empty screen.
  final String? semantics;

  /// The worktree the paths above are relative to, on **this** machine.
  ///
  /// On neither wire: a reader elsewhere has its own checkout, and a path
  /// naming this one is the thing being avoided. It is here so the in-process
  /// panel, which does open the files, is not handed the root separately at
  /// four call sites — and it is empty on a step parsed back out of a report,
  /// where the artifacts are beside the page rather than in a worktree.
  @JsonKey(includeToJson: false, includeFromJson: false)
  final String root;

  /// The visible texts — the projection an agent reads next to the pixels.
  final List<String> texts;

  /// The verb that produced this step and what it was aimed at — `tap`,
  /// `"Pay"`. Together they name the transition *into* this step, which is
  /// what the events below happened during. Null on artifacts from before the
  /// capture existed, and on a step captured at a failure.
  final String? verb;
  final String? target;

  /// What the app did on the way here — logs, prints, platform channel
  /// messages, and whatever the project's fakes reported through
  /// `recordScenarioEvent`. Relative like [image]; null when this transition
  /// was quiet, which is distinct from a run too old to have captured any.
  final String? events;

  /// How many, and on which channels — `{platform: 3, print: 1}`. The badge on
  /// the flow's arrow, and the part of the digest that survives filtering.
  ///
  /// Null — not zero, not `{}` — on a transition where nothing happened, which
  /// is most of them: four keys saying "none" on every step of a fifty-step
  /// run is noise an agent pays for. [hasEvents] is the question worth asking.
  final int? eventCount;
  final Map<String, int>? eventChannels;

  /// The one-line summaries, capped, `system` excluded — what a reader gets
  /// without opening [events]. `POST /login → 401` is the part an agent
  /// reasons about; the payloads are what it fetches when it cares.
  final List<String>? eventTitles;

  /// Events dropped to stay inside the per-step or per-run cap. Reported
  /// rather than swallowed: a truncated transition that said nothing would
  /// read as an app that did nothing.
  final int? eventsDropped;

  /// Whether anything happened on the way to this step.
  @JsonKey(includeToJson: false)
  bool get hasEvents => (eventCount ?? 0) > 0;

  /// The directory of numbered frames recorded on the way to this step —
  /// what the transition *looked like*, where the events say what it did.
  /// Relative like [image]; null on every run that did not record, which is
  /// every CLI run and every run older than the capture.
  ///
  /// The frames are in [format], at [frameWidth]×[frameHeight] — their own
  /// size, not the step's: a recording runs at half scale and the shot beside
  /// it does not.
  final String? frames;
  final int? frameCount;
  final int? frameWidth;
  final int? frameHeight;

  /// Fake milliseconds between two frames — the speed a player runs at to
  /// show the animation as the app would have played it.
  final int? frameIntervalMs;

  /// Frames refused by the recorder's cap: the transition went on longer than
  /// the recording does, and the last frame is not where the app stopped.
  final int? framesDropped;

  /// Whether there is motion here to play. Two frames is the floor — one is
  /// the still the transition started from.
  @JsonKey(includeToJson: false)
  bool get hasMotion => frames != null && (frameCount ?? 0) > 1;

  /// The recorded frames in order, spelled the way [image] is — so whoever
  /// reads them resolves them the same way, off a worktree's disk in the panel
  /// or over HTTP on an exported page.
  ///
  /// Built from the count rather than listed: the harness numbers them from
  /// zero and a directory listing would sort `10` before `2` unless it were
  /// re-sorted anyway — and on a page there is no directory to list.
  @JsonKey(includeToJson: false)
  List<String> get framePaths => [
    if (frames case var directory?)
      for (var index = 0; index < (frameCount ?? 0); index++)
        // `p.url`, not `p`: this is a path in a report, and the one that has
        // to keep working after the report crosses a machine.
        '$directory/${index.toString().padLeft(4, '0')}.$format',
  ];

  /// The events a reader will actually be shown — everything but `system`.
  ///
  /// What the flow's arrows and the tab's label count. The framework talks to
  /// `flutter/textinput` on any step with a text field, so counting the whole
  /// buffer would put "4 events" on every arrow of every flow and lead every
  /// reader to a tab filtered down to nothing. The `system` chip still carries
  /// its own count, for the reader who wants it.
  @JsonKey(includeToJson: false)
  int get notableEventCount =>
      (eventCount ?? 0) - (eventChannels?['system'] ?? 0);

  /// The step's `fw://` address.
  final String address;

  /// The `SystemUiOverlayStyle` icon brightness the app had declared at
  /// capture time (`light`/`dark`), if any — what the fake status bar and
  /// home indicator tint themselves with.
  final String? statusBrightness;
  final String? navBrightness;

  /// False when the verb's settle policy gave up with frames still scheduled:
  /// something on this screen animates indefinitely — a spinner, a shimmer —
  /// and the capture is of a moving picture. Not a failure.
  final bool settled;

  /// False when the shutter fell with an image decode or an asset read still
  /// in flight: the picture is of a screen that was still filling in, and the
  /// artwork it is missing turns up on the next step. Not a failure, and not
  /// the same thing as [settled] — a screen can be perfectly still and still
  /// be waiting for its illustration.
  final bool landed;

  /// Frames drawn before this step that none of the scenario's verbs drew —
  /// the scenario reached for the raw `tester`, and whatever the app did in
  /// those frames is not in the flow. Zero is the healthy case.
  final int strayFrames;

  /// The error, when this is the step a scenario broke on. The frame is the
  /// state at the failure, and the message carries the `split` branch that
  /// reached it.
  final String? failure;

  /// What the flow produced on the way to this step that is not a widget —
  /// what `s.attach` handed over. Empty on almost every step.
  final List<ScenarioRunAttachment> attachments;

  Map<String, Object?> toJson() => _$ScenarioRunStepToJson(this);
}

/// A file a step carries beside its screenshot — a PDF, a payload, an email
/// body.
///
/// A path rather than the bytes, like the tree and the events beside it: a
/// run's report stays readable, and the thing a reader wants to do with a
/// document is open it.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ScenarioRunAttachment {
  factory ScenarioRunAttachment.fromJson(Map<String, dynamic> json) =>
      _$ScenarioRunAttachmentFromJson(json);

  ScenarioRunAttachment({
    required this.name,
    required this.file,
    required this.bytes,
    this.mimeType,
  });

  /// What the scenario called it — `'report'`.
  final String name;

  /// The file, **relative to the worktree root**, like the step's own image.
  final String file;

  /// What it is, when the scenario said — `application/pdf`. A viewer
  /// switches on this; absent means "offer it as a download".
  final String? mimeType;

  /// How big it is, so a reader knows before opening it.
  final int bytes;

  Map<String, Object?> toJson() => _$ScenarioRunAttachmentToJson(this);
}

/// What a step's verb did — `tap`, and what it acted on.
///
/// [target] is already decorated for reading (`#pay`, `"Buy"`); [kind] says
/// how it was named, which is how much the name can be trusted to stay put —
/// a key is the author's own word, visible text is translated.
/// Readable back with the step that carries it — an exported page draws the
/// verb on the arrow into a step, so a report that could not parse this would
/// be a page of unlabelled arrows.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ScenarioStepAction {
  factory ScenarioStepAction.fromJson(Map<String, dynamic> json) =>
      _$ScenarioStepActionFromJson(json);

  ScenarioStepAction({required this.verb, this.target, this.kind});

  final String verb;
  final String? target;
  final String? kind;

  /// `tap #pay`, `back`.
  @JsonKey(includeToJson: false)
  String get label => target == null ? verb : '$verb $target';

  Map<String, Object?> toJson() => _$ScenarioStepActionToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ScenarioRunError {
  factory ScenarioRunError.fromJson(Map<String, dynamic> json) =>
      _$ScenarioRunErrorFromJson(json);

  ScenarioRunError({required this.error, this.stack});

  final String error;
  final String? stack;

  Map<String, Object?> toJson() => _$ScenarioRunErrorToJson(this);
}

/// `export` — the run, written out as a page you can serve.
///
/// Reports the run's own verdict, not the build's: the scenarios really ran to
/// produce this, and a page of red flows is still a failure worth an exit code.
/// The page exists either way — showing what broke is most of what it is for.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioWebExportResult implements PluginResult, ReportsFailure {
  ScenarioWebExportResult({
    required this.output,
    required this.indexHtml,
    required this.scenarios,
    required this.steps,
    required this.artifacts,
    required this.durationMs,
    this.failed = 0,
    required this.serve,
  });

  /// The directory to serve, worktree-relative where it sits inside one.
  final String output;

  final String indexHtml;

  final int scenarios;
  final int steps;

  /// Files copied in beside the page — screenshots, trees, semantics, events.
  final int artifacts;

  final int durationMs;

  /// Scenarios that came back red. Their flows are on the page, which is the
  /// point.
  final int failed;

  /// How to look at it. A page nobody can open is a directory, and the one
  /// thing every reader of this result needs to know is that a `file://` open
  /// will not do.
  final String serve;

  @override
  bool get ok => failed == 0;

  @override
  Map<String, Object?> toJson() => _$ScenarioWebExportResultToJson(this);
}

/// `new` — a runnable scenario file written where the package keeps them.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioNewResult implements PluginResult {
  ScenarioNewResult({
    required this.package,
    required this.file,
    required this.name,
    required this.next,
  });

  final String package;

  /// The written file, package-relative — the same spelling `list` reports and
  /// `run --file=` takes, so the next call needs no translation.
  final String file;

  final String name;

  /// The command that runs what was just written. A scaffold that does not say
  /// how to run itself sends the reader back to `actions`.
  final String next;

  @override
  Map<String, Object?> toJson() => _$ScenarioNewResultToJson(this);
}

/// `restart` — the warm harness dropped, so the next run cold-starts from
/// nothing: fresh asset bundle, fresh kernel, fresh tester process.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRestartResult implements PluginResult {
  ScenarioRestartResult({required this.restarted});

  /// The package paths whose harness was dropped.
  final List<String> restarted;

  @override
  Map<String, Object?> toJson() => _$ScenarioRestartResultToJson(this);
}

/// `shots` — the store/documentation lane: named shots only, at the device's
/// own pixel ratio, laid out by language and device.
///
/// A separate action rather than five flags on `run`, and rather than a
/// profile: store shots come from the same scenarios a `mobile` profile
/// already governs, so a `store` profile would overlap it and profiles would
/// stop partitioning. What differs is every default — native resolution, a
/// tag filter, an ordered naming scheme and its own output tree — which is
/// what an action is for.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioShotsResult implements PluginResult {
  ScenarioShotsResult({required this.packages, this.count = 0});

  final List<ScenarioShotsPackage> packages;

  /// How many images were written, over every package and assignment.
  final int count;

  @override
  Map<String, Object?> toJson() => _$ScenarioShotsResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioShotsPackage {
  ScenarioShotsPackage({
    required this.path,
    required this.output,
    this.sets = const [],
    this.error,
  });

  final String path;

  /// The root of the tree — `<language>/<device>/` beneath it.
  final String output;

  final List<ScenarioShotSet> sets;

  /// Set when the package could not be run at all.
  final String? error;

  Map<String, Object?> toJson() => _$ScenarioShotsPackageToJson(this);
}

/// One point of the matrix, and the images it produced.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioShotSet {
  ScenarioShotSet({
    required this.directory,
    this.axes = const {},
    this.images = const [],
    this.failed = 0,
  });

  /// Relative to `ScenarioShotsPackage.output`, so the whole tree can be
  /// moved or uploaded as it stands.
  final String directory;

  final Map<String, String> axes;

  /// File names, in the order they were captured — which is the order they
  /// were numbered with.
  final List<String> images;

  /// Scenarios that failed while producing this set. Their shots up to the
  /// failure are still here; a store run that silently shipped a half suite
  /// would be worse than one that says so.
  final int failed;

  Map<String, Object?> toJson() => _$ScenarioShotSetToJson(this);
}

/// `read` — one archived step, answered.
///
/// The other half of what a run leaves on disk. A run writes four legs per
/// step and hands back paths; this reads them and answers the same questions
/// the live surfaces answer — the screen, `find`, `at`, `styles`, the tree —
/// in the same shape, so a `find` against a scenario step and a `find` against
/// a running app differ in which file was opened and in nothing an agent has
/// to learn twice.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioReadResult implements PluginResult, ProducesArtifacts {
  ScenarioReadResult({
    required this.step,
    required this.lens,
    this.scenario,
    this.file,
    this.index,
    this.failure,
    this.image,
    this.screen,
    this.texts,
    this.tree,
    this.nodes,
    this.find,
    this.at,
    this.styles,
    this.note,
    this.next,
    this.steps = const [],
    this.picture,
  });

  /// The capture this answers about, worktree-relative — the value to pass
  /// back as `step` to ask it something else.
  final String step;

  /// The lens the reply was produced under. Said on every reply, because a
  /// caller who does not know a picture was available cannot ask for one.
  final String lens;

  final String? scenario;
  final String? file;

  /// The step's 1-based position in its scenario's capture sequence.
  final int? index;

  /// The error this step died on, when it is a failing step. The reason most
  /// reads of an archive happen at all.
  final String? failure;

  /// The archived PNG, worktree-relative. Always named; inlined as an
  /// artifact only when a picture was asked for.
  final String? image;

  /// What is on the screen, what can be acted on, and how it is laid out.
  final Screen? screen;

  /// Every Text and text field of the step, as the capture recorded them.
  final List<String>? texts;

  /// The whole widget tree, compact. The heaviest thing here by an order of
  /// magnitude — `find`, `at` and `styles` answer most of what anyone reads a
  /// tree for, at a fiftieth of the tokens.
  final Map<String, Object?>? tree;

  /// How many nodes the tree has, whether or not it rode back.
  final int? nodes;

  final List<Map<String, Object?>>? find;
  final List<Map<String, Object?>>? at;
  final List<InspectStyle>? styles;

  /// A query that could not be answered, said so the caller can fix it. The
  /// read still happened; this is not an error.
  final String? note;

  /// One line naming what else this capture can be asked.
  final String? next;

  /// The other captures of the same scenario, as bare file names beside
  /// [step] — what makes walking a failing flow backwards one call each.
  ///
  /// Names rather than paths because they share a directory with [step] and
  /// repeating it is most of the list: measured at 137 of the 365 tokens of a
  /// default reply, for the same eighty characters five times over.
  final List<String> steps;

  /// The archived PNG as a thing to *look at*, set only when a picture was
  /// asked for. [image] names it either way; this is what makes a client that
  /// can show an image show it, and it is opt-in because a picture is ~810
  /// tokens and the screen answers most questions without one.
  @JsonKey(includeToJson: false)
  final Artifact? picture;

  @override
  @JsonKey(includeToJson: false)
  List<Artifact> get artifacts => [?picture];

  @override
  Map<String, Object?> toJson() => _$ScenarioReadResultToJson(this);
}
