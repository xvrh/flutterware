/// What a scenario run writes down, typed — the model behind `run.json`.
///
/// One vocabulary, three careers. The harness records each step in this shape
/// as it captures; `fw run scenarios run` writes the whole run to `run.json`
/// beside its artifacts; and whoever reads that file back — the studio's own
/// panels, an exported web page, or a consumer's `tool/` script — parses it
/// into these same classes. A shape with fewer careers than that was the old
/// state of affairs: three hand-kept copies that could drift one field apart.
///
/// **This is published API.** A field renamed here breaks somebody's script,
/// which is why [scenarioRunReportVersion] exists and why [ScenarioRunResult.fromJson]
/// refuses a major it does not know rather than handing back a half-decoded
/// object. Added fields do not bump the version — an older reader ignoring a
/// new key is the behaviour that makes adding one cheap.
///
/// Plain Dart on purpose — nothing here may import `package:flutter`, and
/// nothing here may import `dart:io`: a consumer's script runs under a bare
/// `dart run`, and the exported scenario page parses this very model in a
/// browser. The disk-facing reader lives in `report_io.dart`.
library;

import '../plugins/address.dart';
import '../plugins/artifact.dart';
import '../plugins/plugin_result.dart';
// The one thing near this model that needs a filesystem, behind the one seam
// that lets the rest of it compile for the web. The exported scenario page
// renders these very classes in a browser, where there is no `dart:io` to
// import — see `2026-08-11-scenario-web-export-design.md`.
import 'notification.dart';
import 'report_events_web.dart' if (dart.library.io) 'report_events_io.dart';

/// The format `run.json` (and the matrix's `index.json`) is written in.
///
/// Bumped only when a reader of the previous version would get something
/// wrong. Added fields do not bump it — an older reader ignoring a new key is
/// the behaviour that makes adding one cheap.
const scenarioRunReportVersion = 1;

/// What a run writes beside its artifacts: itself, whole, in this shape.
///
/// Named next to the model rather than next to the writer, because reading it
/// back is the point — [ScenarioRunResult.fromJson] on this file is the other
/// half of an answer that summarised.
const scenarioRunReportFile = 'run.json';

/// What a matrix run writes at the root of its output tree: one line per
/// point, each naming the directory whose `run.json` holds the rest.
///
/// A matrix's artifacts are a tree a CI job has to *find* things in; the
/// result of the call says the same thing, but the call is gone by the time
/// the upload step runs.
const scenarioRunIndexFile = 'index.json';

/// A whole `run` — scenarios executed in the runner's `flutter_tester`, with
/// one artifact triple (PNG, widget tree, texts) per captured step.
class ScenarioRunResult
    implements PluginResult, ReportsFailure, ProducesArtifacts {
  ScenarioRunResult({
    this.version = scenarioRunReportVersion,
    required this.packages,
    this.axes,
  });

  /// Decodes a `run.json`.
  ///
  /// Throws [FormatException] on a version this reader does not know: the
  /// reader of that message is looking at somebody else's build output, so it
  /// names what was found and what would work.
  factory ScenarioRunResult.fromJson(Map<String, Object?> json) {
    var version = _int(json['version'], 1);
    if (version > scenarioRunReportVersion) {
      throw FormatException(
        'This run report is version $version and this is a reader for '
        '$scenarioRunReportVersion. Upgrade the flutterware dependency of '
        'whatever reads it.',
      );
    }
    return ScenarioRunResult(
      version: version,
      packages: _listOf(json['packages'], ScenarioRunPackage.fromJson),
      axes: _stringsOrNull(json['axes']),
    );
  }

  final int version;

  final List<ScenarioRunPackage> packages;

  /// The axis assignment the whole request ran under —
  /// `{device: iphone-se, language: fr}` — or null for the test defaults.
  /// Recorded because a screenshot is under-specified without it; the same
  /// values ride every step's address as query parameters.
  final Map<String, String>? axes;

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
  List<Artifact> get artifacts => [
    for (var package in packages)
      for (var scenario in package.scenarios)
        if (!scenario.ok && scenario.steps.isNotEmpty)
          if (scenario.steps.last case var step
              when step.format == 'png' && step.image != null)
            Artifact(
              kind: Artifact.png,
              address: Address.parse(step.address),
              path: step.image!,
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

  @override
  Map<String, Object?> toJson() => {
    'version': version,
    // Derivable from the packages, and said anyway: `ok` is what a CI step
    // greps a report for, and what the action's exit code is read against.
    'ok': ok,
    if (axes != null) 'axes': axes,
    'packages': packages,
  };
}

/// One package's run: where its artifacts went, and how each scenario fared.
class ScenarioRunPackage {
  ScenarioRunPackage({
    required this.path,
    required this.output,
    this.axes,
    this.ms = 0,
    this.scenarios = const [],
    this.report,
    this.log,
    this.error,
  });

  factory ScenarioRunPackage.fromJson(Map<String, Object?> json) =>
      ScenarioRunPackage(
        path: json['path'] as String? ?? '',
        output: json['output'] as String? ?? '',
        axes: _stringsOrNull(json['axes']),
        ms: _int(json['ms'], 0),
        scenarios: _listOf(json['scenarios'], ScenarioRunOutcome.fromJson),
        report: json['report'] as String?,
        log: json['log'] as String?,
        error: json['error'] as String?,
      );

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

  /// The harness process's console, whole, on disk — engine noise, and
  /// anything printed outside a test zone. Not where a scenario's own prints
  /// or exceptions go: those ride the steps' events and the outcome's
  /// `errors`. This file is for the failure mode nothing structured has a
  /// slot for yet. One file per harness process, truncated when it starts.
  final String? log;

  /// The assignment **this** entry ran under, when the request asked for a
  /// matrix (`devices=` / `languages=`): one entry per package per point of
  /// it, each with its own [output]. Null for a single-assignment run, where
  /// [ScenarioRunResult.axes] already says it once.
  final Map<String, String>? axes;

  /// Whole-run wall time inside the harness.
  final int ms;

  final List<ScenarioRunOutcome> scenarios;

  /// Set when the package could not be run at all — the harness did not
  /// compile, the tester did not start — in which case [scenarios] is empty.
  final String? error;

  Map<String, Object?> toJson() => {
    'path': path,
    'output': output,
    if (axes != null) 'axes': axes,
    'ms': ms,
    'scenarios': scenarios,
    if (report != null) 'report': report,
    if (log != null) 'log': log,
    if (error != null) 'error': error,
  };
}

/// One scenario's verdict, and the steps it captured on the way to it.
class ScenarioRunOutcome {
  factory ScenarioRunOutcome.fromJson(Map<String, Object?> json) {
    var steps = _listOf(json['steps'], ScenarioRunStep.fromJson);
    return ScenarioRunOutcome(
      file: json['file'] as String? ?? '',
      name: json['name'] as String? ?? '',
      ok: json['ok'] == true,
      skipped: json['skipped'] == true,
      skipReason: json['skipReason'] as String?,
      device: json['device'] as String?,
      ms: _int(json['ms'], 0),
      steps: steps,
      // Absent on the harness's own record, where the steps are all present
      // and the counts are theirs to state.
      stepCount: _int(json['stepCount'], steps.length),
      unchangedCount: _int(
        json['unchangedCount'],
        steps.where((step) => step.unchanged).length,
      ),
      errors: _listOf(json['errors'], ScenarioRunError.fromJson),
      translations: _translationsOrNull(json['translations']),
    );
  }

  ScenarioRunOutcome({
    required this.file,
    required this.name,
    required this.ok,
    this.skipped = false,
    this.skipReason,
    this.device,
    this.ms = 0,
    this.steps = const [],
    this.stepCount = 0,
    this.unchangedCount = 0,
    this.errors = const [],
    this.translations,
  });

  final String file;
  final String name;
  final bool ok;

  /// True when the scenario declared `skip: true` and its body never ran —
  /// the same answer `flutter test` gives the same file. [ok] is true, so a
  /// skipped scenario does not fail the run, but green it is not: zero
  /// steps, zero milliseconds, and this flag saying why.
  final bool skipped;

  /// The reason the declaration gave, when it gave one.
  final String? skipReason;

  /// The device it actually ran as. Worth saying because a run that named no
  /// device gets one per folder — whatever profile the scenario's
  /// `flutter_test_config.dart` declares — so two scenarios of the same run
  /// can differ here.
  final String? device;

  final int ms;

  /// Trimmed in an action's answer per its `steps=` mode; whole in the file
  /// `ScenarioRunPackage.report` names. Count them with [stepCount], never
  /// with this list's length.
  final List<ScenarioRunStep> steps;

  /// How many steps the scenario captured — which is [steps]`.length` unless
  /// they were left out of this copy.
  ///
  /// Carried separately so a trimmed answer cannot be read as an empty one: a
  /// green scenario whose steps went to the file on disk still says it took
  /// five pictures. See [ScenarioRunPackage.report].
  final int stepCount;

  /// How many of those steps a verb acted for nothing on — captured trees
  /// byte-identical to their parent's. A green run with most of its steps
  /// here is the signature of a stalled walk: a loop tapping `Continue` on a
  /// page that never completed passes every assertion and photographs the
  /// same screen until its bound. Carried beside [stepCount] for the same
  /// reason: the summary is the copy a reader gets, and this is the number
  /// that makes a stall visible in it.
  final int unchangedCount;

  /// The failure, when [ok] is false. The last captured step is the frame
  /// just before it.
  final List<ScenarioRunError> errors;

  /// Every key each catalog was asked for on the way through this scenario,
  /// and what it answered: `catalog -> key -> value`.
  ///
  /// **Per scenario, and that is load-bearing.** A scenario runs under one
  /// assignment, so this belongs to one locale — which is what lets the
  /// falling-back report compare a rendered string against the file that was
  /// supposed to supply it. Carried across a whole run it would hold whichever
  /// locale ran last.
  ///
  /// Wider than the steps: a key read and never rendered is here and in no
  /// step, which is the difference between "not on this screen" and "this
  /// product never asks for it".
  final Map<String, Map<String, String>>? translations;

  /// This outcome with [keep] of its steps; the rest are on disk.
  ScenarioRunOutcome carrying(List<ScenarioRunStep> keep) => ScenarioRunOutcome(
    file: file,
    name: name,
    ok: ok,
    skipped: skipped,
    skipReason: skipReason,
    device: device,
    ms: ms,
    steps: keep,
    stepCount: stepCount,
    unchangedCount: unchangedCount,
    errors: errors,
    translations: translations,
  );

  /// This outcome with its steps left on disk.
  ScenarioRunOutcome withoutSteps() => carrying(const []);

  /// This outcome carrying only the frame the failure was captured at — the
  /// last one, per [errors]. The trail that led there is in the file.
  ScenarioRunOutcome withFailingStepOnly() =>
      steps.isEmpty ? this : carrying([steps.last]);

  Map<String, Object?> toJson() => {
    'file': file,
    'name': name,
    'ok': ok,
    // The field itself rather than a `true` literal, here and on every flag
    // below: the shape extractor reads a hand-written literal's values, and a
    // value that names its field carries the field's type and doc into
    // `docs/capabilities.md`.
    if (skipped) 'skipped': skipped,
    if (skipReason != null) 'skipReason': skipReason,
    if (device != null) 'device': device,
    'ms': ms,
    'steps': steps,
    'stepCount': stepCount,
    'unchangedCount': unchangedCount,
    if (errors.isNotEmpty) 'errors': errors,
    if (translations != null) 'translations': translations,
  };
}

/// What a step is a picture *of*.
///
/// A flow produces beats, and most of them are screens — but not all. A run
/// that exports a receipt has a moment where the receipt is the thing on
/// stage, and a run whose backend pushes a notification has a moment that is
/// the push. Those are steps like any other: named, positioned, parented,
/// carrying the events that led to them. What differs is what a viewer draws.
enum ScenarioStepKind {
  /// A rendered frame of the app — every automatic capture, and `screen()`.
  screen,

  /// Something the flow produced that is not a screen: a PDF, an email body,
  /// a payload. Bytes with a name and a type, drawn as itself. It has no
  /// frame, because there was no screen showing it.
  document,

  /// A push the flow's backend would have sent. No frame of its own either —
  /// a viewer draws it the way the recipient's phone would, as a banner over
  /// the nearest screen before it.
  notification,
}

/// One captured step: what it is a picture of, its sibling legs on disk, and
/// what the app did on the way to it.
class ScenarioRunStep {
  factory ScenarioRunStep.fromJson(Map<String, Object?> json) =>
      ScenarioRunStep(
        index: _int(json['index'], 0),
        position: json['position'] as String? ?? '',
        parent: json['parent'] as int?,
        branch: json['branch'] as String?,
        name: json['name'] as String?,
        auto: json['auto'] == true,
        tags: _stringList(json['tags']),
        // Absent means `screen`, which is what every report written before
        // there was anything else to be holds — and what almost every step of
        // every report since holds too.
        kind: switch (json['kind']) {
          'document' => ScenarioStepKind.document,
          'notification' => ScenarioStepKind.notification,
          _ => ScenarioStepKind.screen,
        },
        image: json['image'] as String?,
        format: json['format'] as String?,
        width: json['width'] as int?,
        height: json['height'] as int?,
        tree: json['tree'] as String?,
        file: json['file'] as String?,
        mimeType: json['mimeType'] as String?,
        bytes: json['bytes'] as int?,
        notification: switch (json['notification']) {
          Map notification => ScenarioNotification(
            body: '${notification['body'] ?? ''}',
            title: notification['title'] as String?,
            appName: notification['appName'] as String?,
          ),
          _ => null,
        },
        keys: json['keys'] as String?,
        semantics: json['semantics'] as String?,
        texts: _stringList(json['texts']),
        address: json['address'] as String? ?? '',
        statusBrightness: json['statusBrightness'] as String?,
        navBrightness: json['navBrightness'] as String?,
        verb: json['verb'] as String?,
        target: json['target'] as String?,
        events: json['events'] as String?,
        eventCount: json['eventCount'] as int?,
        eventChannels: switch (json['eventChannels']) {
          Map channels => {
            for (var entry in channels.entries)
              '${entry.key}': _int(entry.value, 0),
          },
          _ => null,
        },
        eventTitles: switch (json['eventTitles']) {
          List titles => [for (var title in titles) '$title'],
          _ => null,
        },
        eventsDropped: json['eventsDropped'] as int?,
        frames: json['frames'] as String?,
        frameCount: json['frameCount'] as int?,
        frameWidth: json['frameWidth'] as int?,
        frameHeight: json['frameHeight'] as int?,
        frameIntervalMs: json['frameIntervalMs'] as int?,
        framesDropped: json['framesDropped'] as int?,
        settled: json['settled'] as bool? ?? true,
        landed: json['landed'] as bool? ?? true,
        strayFrames: _int(json['strayFrames'], 0),
        unchanged: json['unchanged'] == true,
        failure: json['failure'] as String?,
      );

  ScenarioRunStep({
    required this.index,
    required this.position,
    required this.auto,
    this.kind = ScenarioStepKind.screen,
    this.image,
    this.format,
    this.width,
    this.height,
    this.tree,
    this.file,
    this.mimeType,
    this.bytes,
    this.notification,
    this.keys,
    this.texts = const [],
    this.address = '',
    this.root = '',
    this.semantics,
    this.parent,
    this.branch,
    this.name,
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
    this.unchanged = false,
    this.failure,
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

  final List<String> tags;

  /// What this step is a picture of. See [ScenarioStepKind].
  final ScenarioStepKind kind;

  /// The captured image, in [format], **relative to the worktree root** — the
  /// same convention the catalog's artifacts follow, so the value survives
  /// being read on another machine and an agent whose tools are scoped to the
  /// repo can open it.
  ///
  /// Null on a step that is not a screen. A [ScenarioStepKind.document] has no
  /// frame at all; a [ScenarioStepKind.notification] is drawn over the nearest
  /// screen before it rather than over one of its own, so neither stores
  /// pixels and neither invents any.
  final String? image;

  /// `png`, or `raw` — bare rgba8888 rows, [width]×[height]×4 bytes. Raw is
  /// the fast capture (~5× at 1×, ~25× at device resolution) for hosts that
  /// can display pixels directly; `png` is the portable default the `run`
  /// action serves. Null wherever [image] is.
  final String? format;

  final int? width;
  final int? height;

  /// The widget-tree JSON captured at the same moment, relative like [image].
  /// Null wherever [image] is — there was no tree to read.
  final String? tree;

  /// The payload of a [ScenarioStepKind.document], **relative to the worktree
  /// root** like [image] — a path rather than the bytes, for the reason the
  /// tree and the events beside it are: a run's report stays readable, and
  /// what a reader wants to do with a document is open it.
  final String? file;

  /// What the document is, when the scenario said — `application/pdf`. A
  /// viewer switches on this; absent means "offer it as a download".
  final String? mimeType;

  /// How big [file] is, so a reader knows before opening it.
  final int? bytes;

  /// The push a [ScenarioStepKind.notification] step is.
  ///
  /// Inline rather than a file: it is three short strings, and it is typed on
  /// both ends of the wire — a viewer supplies what it leaves out (the app's
  /// own icon, the banner's "now", the brightness the run was in).
  final ScenarioNotification? notification;

  /// The translation keys on this screen, and the words that belonged to no
  /// catalog — relative like [image]. Null when no catalog was wired up,
  /// which is every project that has not asked for this.
  ///
  /// A file rather than an inlined list, like [tree] and for the same reason:
  /// a run's response stays readable, and the export fetches it per step.
  final String? keys;

  /// The semantics-tree JSON — what a screen reader gets — relative like
  /// [image]. Null on artifacts from before the capture existed, and when the
  /// run had no semantics tree to read; a reader states the absence rather
  /// than inventing an empty screen.
  final String? semantics;

  /// The worktree the paths above are relative to, on **this** machine.
  ///
  /// On neither wire: a reader elsewhere has its own checkout, and a path
  /// naming this one is the thing being avoided. It is here so an in-process
  /// panel, which does open the files, is not handed the root separately at
  /// four call sites — and it is empty on a step parsed back out of a report,
  /// where the artifacts are beside the page rather than in a worktree.
  final String root;

  /// The visible texts — the projection an agent reads next to the pixels.
  final List<String> texts;

  /// The verb that produced this step and what it was aimed at — `tap`,
  /// `"Pay"`. Together they name the transition *into* this step, which is
  /// what the events below happened during. Null on artifacts from before the
  /// capture existed, and on a step captured at a failure.
  final String? verb;
  final String? target;

  /// The verb and its target as one label — `tap "Pay"` — or null where
  /// nothing acted. What an unnamed step is labelled with, in place of its
  /// index.
  String? get action {
    var did = [?verb, ?target].join(' ');
    return did.isEmpty ? null : did;
  }

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
  bool get hasMotion => frames != null && (frameCount ?? 0) > 1;

  /// The recorded frames in order, spelled the way [image] is — so whoever
  /// reads them resolves them the same way, off a worktree's disk in the panel
  /// or over HTTP on an exported page.
  ///
  /// Built from the count rather than listed: the harness numbers them from
  /// zero and a directory listing would sort `10` before `2` unless it were
  /// re-sorted anyway — and on a page there is no directory to list.
  List<String> get framePaths => [
    if (frames case var directory?)
      for (var index = 0; index < (frameCount ?? 0); index++)
        // A path in a report — the URL spelling, which is the one that has to
        // keep working after the report crosses a machine.
        '$directory/${index.toString().padLeft(4, '0')}.$format',
  ];

  /// The events a reader will actually be shown — everything but `system`.
  ///
  /// What the flow's arrows and the tab's label count. The framework talks to
  /// `flutter/textinput` on any step with a text field, so counting the whole
  /// buffer would put "4 events" on every arrow of every flow and lead every
  /// reader to a tab filtered down to nothing. The `system` chip still carries
  /// its own count, for the reader who wants it.
  int get notableEventCount =>
      (eventCount ?? 0) - (eventChannels?['system'] ?? 0);

  /// The step's `fw://` address. Empty on the harness's own record; the host
  /// that knows the worktree fills it in via [locate].
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

  /// True when this step's captured tree is byte-identical to its parent's:
  /// the verb acted and nothing on screen changed. A fact, not a verdict — a
  /// capture parked mid-flight with `Settle.none` is legitimately unchanged —
  /// but a run of these in a walking scenario is a stalled flow passing
  /// quietly, which is what the flag exists to make visible. Never set on the
  /// step a scenario failed at, nor on one that is not a screen — a document
  /// has no tree to be identical to anything.
  final bool unchanged;

  /// The error, when this is the step a scenario broke on. The frame is the
  /// state at the failure, and the message carries the `split` branch that
  /// reached it.
  final String? failure;

  /// This step, published: its artifact paths rewritten through [path], its
  /// [address] assigned, its [root] recorded.
  ///
  /// How a host that knows the worktree turns the harness's own record —
  /// absolute paths, no address — into the one every surface reports. Lives
  /// beside the fields it copies so a new field cannot be forgotten in a
  /// parser three files away.
  ScenarioRunStep locate({
    required String root,
    required String address,
    required String Function(String) path,
  }) => ScenarioRunStep(
    index: index,
    position: position,
    parent: parent,
    branch: branch,
    name: name,
    auto: auto,
    tags: tags,
    kind: kind,
    image: switch (image) {
      var image? => path(image),
      null => null,
    },
    format: format,
    width: width,
    height: height,
    tree: switch (tree) {
      var tree? => path(tree),
      null => null,
    },
    file: switch (file) {
      var file? => path(file),
      null => null,
    },
    mimeType: mimeType,
    bytes: bytes,
    notification: notification,
    keys: switch (keys) {
      var keys? => path(keys),
      null => null,
    },
    semantics: switch (semantics) {
      var semantics? => path(semantics),
      null => null,
    },
    texts: texts,
    address: address,
    root: root,
    statusBrightness: statusBrightness,
    navBrightness: navBrightness,
    verb: verb,
    target: target,
    events: switch (events) {
      var events? => path(events),
      null => null,
    },
    eventCount: eventCount,
    eventChannels: eventChannels,
    eventTitles: eventTitles,
    eventsDropped: eventsDropped,
    frames: switch (frames) {
      var frames? => path(frames),
      null => null,
    },
    frameCount: frameCount,
    frameWidth: frameWidth,
    frameHeight: frameHeight,
    frameIntervalMs: frameIntervalMs,
    framesDropped: framesDropped,
    settled: settled,
    landed: landed,
    strayFrames: strayFrames,
    unchanged: unchanged,
    failure: failure,
  );

  Map<String, Object?> toJson() => {
    'index': index,
    'position': position,
    if (parent != null) 'parent': parent,
    if (branch != null) 'branch': branch,
    if (name != null) 'name': name,
    'auto': auto,
    if (tags.isNotEmpty) 'tags': tags,
    // Omitted for a screen, so the overwhelmingly common step's record stays
    // the size it has always been — and so a reader written before there was
    // anything but screens reads one correctly by ignoring the key.
    if (kind != ScenarioStepKind.screen) 'kind': kind.name,
    if (image != null) 'image': image,
    if (format != null) 'format': format,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (tree != null) 'tree': tree,
    if (file != null) 'file': file,
    if (mimeType != null) 'mimeType': mimeType,
    if (bytes != null) 'bytes': bytes,
    if (notification case var notification?)
      'notification': {
        'body': notification.body,
        if (notification.title != null) 'title': notification.title,
        if (notification.appName != null) 'appName': notification.appName,
      },
    if (keys != null) 'keys': keys,
    if (semantics != null) 'semantics': semantics,
    'texts': texts,
    if (address.isNotEmpty) 'address': address,
    if (statusBrightness != null) 'statusBrightness': statusBrightness,
    if (navBrightness != null) 'navBrightness': navBrightness,
    if (verb != null) 'verb': verb,
    if (target != null) 'target': target,
    if (events != null) 'events': events,
    if (eventCount != null) 'eventCount': eventCount,
    if (eventChannels != null) 'eventChannels': eventChannels,
    if (eventTitles != null) 'eventTitles': eventTitles,
    if (eventsDropped != null) 'eventsDropped': eventsDropped,
    if (frames != null) 'frames': frames,
    if (frameCount != null) 'frameCount': frameCount,
    if (frameWidth != null) 'frameWidth': frameWidth,
    if (frameHeight != null) 'frameHeight': frameHeight,
    if (frameIntervalMs != null) 'frameIntervalMs': frameIntervalMs,
    if (framesDropped != null) 'framesDropped': framesDropped,
    // All omitted in the healthy case, so a normal step's record stays the
    // size it was. Each writes its field rather than a literal so the shape
    // extractor carries the field's doc into `docs/capabilities.md`.
    if (!settled) 'settled': settled,
    if (!landed) 'landed': landed,
    if (strayFrames > 0) 'strayFrames': strayFrames,
    if (unchanged) 'unchanged': unchanged,
    if (failure != null) 'failure': failure,
  };
}

class ScenarioRunError {
  factory ScenarioRunError.fromJson(Map<String, Object?> json) =>
      ScenarioRunError(
        error: json['error'] as String? ?? '',
        stack: json['stack'] as String?,
      );

  ScenarioRunError({required this.error, this.stack});

  final String error;
  final String? stack;

  Map<String, Object?> toJson() => {
    'error': error,
    if (stack != null) 'stack': stack,
  };
}

/// A matrix run's `index.json`: one entry per point, each naming the
/// directory whose own `run.json` holds the rest.
class ScenarioRunIndex {
  ScenarioRunIndex({
    this.version = scenarioRunReportVersion,
    this.runs = const [],
  });

  /// Decodes an `index.json`.
  ///
  /// Throws [FormatException] on a version this reader does not know, like
  /// [ScenarioRunResult.fromJson] and for the same reason.
  factory ScenarioRunIndex.fromJson(Map<String, Object?> json) {
    var version = _int(json['version'], 1);
    if (version > scenarioRunReportVersion) {
      throw FormatException(
        'This run index is version $version and this is a reader for '
        '$scenarioRunReportVersion. Upgrade the flutterware dependency of '
        'whatever reads it.',
      );
    }
    return ScenarioRunIndex(
      version: version,
      runs: _listOf(json['runs'], ScenarioRunIndexEntry.fromJson),
    );
  }

  final int version;

  final List<ScenarioRunIndexEntry> runs;

  Map<String, Object?> toJson() => {'version': version, 'runs': runs};
}

/// One point of the matrix, as the index lists it.
class ScenarioRunIndexEntry {
  ScenarioRunIndexEntry({
    required this.package,
    this.axes,
    required this.output,
    required this.ok,
    this.scenarios = 0,
    this.failed = 0,
    this.skipped = 0,
    this.error,
  });

  factory ScenarioRunIndexEntry.fromJson(Map<String, Object?> json) =>
      ScenarioRunIndexEntry(
        package: json['package'] as String? ?? '',
        axes: _stringsOrNull(json['axes']),
        output: json['output'] as String? ?? '',
        ok: json['ok'] == true,
        scenarios: _int(json['scenarios'], 0),
        failed: _int(json['failed'], 0),
        skipped: _int(json['skipped'], 0),
        error: json['error'] as String?,
      );

  final String package;

  /// The assignment this point ran under — `{device: iphone-se, language: fr}`.
  final Map<String, String>? axes;

  /// This point's output directory, **relative to the index** — which is what
  /// makes the whole tree movable.
  final String output;

  final bool ok;

  /// How many scenarios ran, and how many of them came back red.
  final int scenarios;
  final int failed;

  /// How many declared `skip: true` and never ran — counted into [scenarios],
  /// not into [failed]: a skip is not a failure, and not silently green.
  final int skipped;

  /// Set when this point could not run at all.
  final String? error;

  Map<String, Object?> toJson() => {
    'package': package,
    if (axes != null) 'axes': axes,
    'output': output,
    'ok': ok,
    'scenarios': scenarios,
    'failed': failed,
    if (skipped > 0) 'skipped': skipped,
    if (error != null) 'error': error,
  };
}

int _int(Object? value, int orElse) => switch (value) {
  int value => value,
  num value => value.round(),
  _ => orElse,
};

List<String> _stringList(Object? value) => switch (value) {
  List value => [for (var entry in value) '$entry'],
  _ => const [],
};

Map<String, String>? _stringsOrNull(Object? value) => switch (value) {
  Map value => {
    for (var entry in value.entries) '${entry.key}': '${entry.value}',
  },
  _ => null,
};

Map<String, Map<String, String>>? _translationsOrNull(Object? value) =>
    switch (value) {
      Map read => {
        for (var entry in read.entries)
          '${entry.key}': switch (entry.value) {
            Map values => {
              for (var value in values.entries)
                '${value.key}': '${value.value}',
            },
            _ => <String, String>{},
          },
      },
      _ => null,
    };

List<T> _listOf<T>(Object? value, T Function(Map<String, Object?>) decode) => [
  for (var entry in value as List? ?? const [])
    if (entry is Map) decode(entry.cast<String, Object?>()),
];
