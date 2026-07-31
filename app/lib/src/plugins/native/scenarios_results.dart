import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

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
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunResult
    implements PluginResult, ReportsFailure, ProducesArtifacts {
  ScenarioRunResult({required this.packages, this.axes});

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

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunPackage {
  ScenarioRunPackage({
    required this.path,
    required this.output,
    this.ms = 0,
    this.scenarios = const [],
    this.error,
  });

  final String path;

  /// Where this run's artifacts were written.
  final String output;

  /// Whole-run wall time inside the harness.
  final int ms;

  final List<ScenarioRunOutcome> scenarios;

  /// Set when the package could not be run at all — the harness did not
  /// compile, the tester did not start — in which case [scenarios] is empty.
  final String? error;

  Map<String, Object?> toJson() => _$ScenarioRunPackageToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunOutcome {
  ScenarioRunOutcome({
    required this.file,
    required this.name,
    required this.ok,
    this.ms = 0,
    this.steps = const [],
    this.errors = const [],
  });

  final String file;
  final String name;
  final bool ok;
  final int ms;
  final List<ScenarioRunStep> steps;

  /// The failure, when [ok] is false. The last captured step is the frame
  /// just before it.
  final List<ScenarioRunError> errors;

  Map<String, Object?> toJson() => _$ScenarioRunOutcomeToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunStep {
  ScenarioRunStep({
    required this.index,
    required this.auto,
    required this.image,
    required this.format,
    required this.width,
    required this.height,
    required this.tree,
    required this.texts,
    required this.address,
    required this.root,
    this.parent,
    this.branch,
    this.name,
    this.tags = const [],
    this.statusBrightness,
    this.navBrightness,
  });

  /// 1-based position in the scenario's capture sequence.
  final int index;

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

  /// The worktree the two paths above are relative to.
  ///
  /// Not on the wire: a reader on another machine has its own checkout, and a
  /// path naming this one is the thing being avoided. It is here so the panel,
  /// which is in-process and does need to open the files, does not have to be
  /// handed the root separately at four call sites.
  @JsonKey(includeToJson: false)
  final String root;

  @JsonKey(includeToJson: false)
  File get imageFile => File(p.join(root, image));

  @JsonKey(includeToJson: false)
  File get treeFile => File(p.join(root, tree));

  /// The visible texts — the projection an agent reads next to the pixels.
  final List<String> texts;

  /// The step's `fw://` address.
  final String address;

  /// The `SystemUiOverlayStyle` icon brightness the app had declared at
  /// capture time (`light`/`dark`), if any — what the fake status bar and
  /// home indicator tint themselves with.
  final String? statusBrightness;
  final String? navBrightness;

  Map<String, Object?> toJson() => _$ScenarioRunStepToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunError {
  ScenarioRunError({required this.error, this.stack});

  final String error;
  final String? stack;

  Map<String, Object?> toJson() => _$ScenarioRunErrorToJson(this);
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
