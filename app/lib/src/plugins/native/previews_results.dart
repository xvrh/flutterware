import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'previews_results.g.dart';

/// What the Previews actions hand back.
///
/// Classes rather than hand-built maps, for three reasons that all showed up in
/// this plugin: the compiler checks a field name and does not check `'entires'`;
/// `toJson` is generated from the fields, so the wire form cannot drift from
/// the type; and the *shape* of each class is extracted statically into
/// `docs/capabilities.md`, so a field added here is documented without anyone
/// remembering to.
///
/// Nullability is load-bearing. A shape derived from sample output can only say
/// which fields happened to be present; these say which are optional, which is
/// the difference between "this package has no error" and "this package cannot
/// have one".

/// `entries` — every catalog entry, per declared package.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogEntriesResult implements PluginResult {
  CatalogEntriesResult({required this.packages});

  final List<CatalogPackageEntries> packages;

  @override
  Map<String, Object?> toJson() => _$CatalogEntriesResultToJson(this);
}

/// One package's entries, or why they could not be read.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogPackageEntries {
  CatalogPackageEntries({
    required this.path,
    required this.directory,
    this.entries = const [],
    this.diagnostics = const [],
    this.error,
    this.authoring,
  });

  /// Package path as declared in `tool/flutterware.dart`.
  final String path;

  /// Where this package's demos were looked for, relative to the package.
  ///
  /// Reported on every answer, not only the empty one: an entry list that does
  /// not say where it came from cannot be told apart from one that came from
  /// the wrong place, and "there are no demos" and "we looked in the wrong
  /// directory" are the same sentence until this is present.
  final String directory;

  final List<CatalogEntrySummary> entries;

  /// Discovery's complaints — a duplicate id, an uncallable target.
  final List<String> diagnostics;

  /// Set when the scan failed, in which case [entries] is empty and means
  /// nothing.
  final String? error;

  /// How to write the first demo. Set **only** when there are none, which is
  /// the one moment the reader is certainly asking.
  final String? authoring;

  Map<String, Object?> toJson() => _$CatalogPackageEntriesToJson(this);
}

/// `new` — the first demo, written for somebody who has none.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogNewResult implements PluginResult {
  CatalogNewResult({
    required this.package,
    required this.file,
    required this.name,
    required this.id,
    required this.next,
  });

  final String package;

  /// The written file, package-relative.
  final String file;

  final String name;

  /// What `screenshot --entry` and `describe --entry` take for it, so the next
  /// call needs no translation.
  final String id;

  /// The command that renders what was just written. A scaffold that does not
  /// say how to look at itself sends the reader back to `actions`.
  final String next;

  @override
  Map<String, Object?> toJson() => _$CatalogNewResultToJson(this);
}

/// One entry, as every surface identifies it.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogEntrySummary {
  CatalogEntrySummary({
    required this.id,
    required this.name,
    required this.address,
    this.group,
  });

  /// What `screenshot --entry` and `describe --entry` take.
  final String id;

  final String name;

  /// The `Address`, rendered — hand it back to `screenshot`, or later `show`.
  final String address;

  /// One tree level between the directory and the leaf, when the entry
  /// declares or derives one.
  final String? group;

  /// `mobile`, `desktop`, `all` — what the demo says it is *for*, when it says.

  Map<String, Object?> toJson() => _$CatalogEntrySummaryToJson(this);
}

/// `check` — what the compiler can and cannot build.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogCheckResult implements PluginResult {
  CatalogCheckResult({required this.packages});

  final List<CatalogPackageCheck> packages;

  @override
  Map<String, Object?> toJson() => _$CatalogCheckResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogPackageCheck {
  CatalogPackageCheck({
    required this.path,
    this.ok = false,
    this.servable = const [],
    this.broken = const [],
    this.error,
  });

  final String path;

  /// True when nothing is quarantined.
  final bool ok;

  /// Entry ids the compiler built.
  final List<String> servable;

  final List<CatalogBrokenEntry> broken;

  /// Set when the daemon could not be reached at all, which is not the same as
  /// "everything failed to compile".
  final String? error;

  Map<String, Object?> toJson() => _$CatalogPackageCheckToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogBrokenEntry {
  CatalogBrokenEntry({required this.id, required this.error});

  final String id;

  /// The compiler's diagnostics, verbatim.
  final String error;

  Map<String, Object?> toJson() => _$CatalogBrokenEntryToJson(this);
}

/// `describe` — one entry, and optionally the knobs it declares.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogEntryDescription implements PluginResult {
  CatalogEntryDescription({
    required this.id,
    required this.name,
    required this.package,
    required this.file,
    required this.symbol,
    required this.annotation,
    required this.address,
    this.group,
    this.knobs,
    this.axes,
    this.shell,
  });

  final String id;
  final String name;

  /// Which declared package holds it.
  final String package;

  /// Project-relative path of the declaring file.
  final String file;

  /// The annotated top-level function.
  final String symbol;

  /// The annotation's source text, verbatim — `Preview(name: 'Counter')`.
  final String annotation;

  final String address;
  final String? group;

  /// Present only when `--knobs` asked for them: reading a knob costs a
  /// compile and a frame, so absent means "not looked at" while an empty list
  /// means "this entry declares none".
  final List<CatalogKnob>? knobs;

  /// What the shell around the entry offers — theme, locale. Same nullability
  /// rule as [knobs], and the same cost.
  ///
  /// An axis is a knob with a different lifetime: a knob belongs to the entry
  /// and goes with it, an axis belongs to the shell and does not.
  final List<CatalogKnob>? axes;

  /// Which shell declared [axes]. Null when the entry's wrapper is not a shell,
  /// which is an answer rather than a failure.
  final String? shell;

  @override
  Map<String, Object?> toJson() => _$CatalogEntryDescriptionToJson(this);
}

/// One control an entry offers, flattened for the wire.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogKnob {
  CatalogKnob({
    required this.name,
    required this.kind,
    this.value,
    this.defaultValue,
    this.min,
    this.max,
    this.options = const [],
  });

  final String name;

  /// `string`, `boolean`, `integer`, `number`, `picker`.
  final String kind;

  /// What it is currently set to.
  final Object? value;

  /// What the demo renders with when nothing is set — also what it shows
  /// outside the catalog.
  @JsonKey(name: 'default')
  final Object? defaultValue;

  /// Bounds, when the demo gave any. Both present is a slider.
  final num? min;
  final num? max;

  /// A picker's labels, in declaration order.
  final List<String> options;

  Map<String, Object?> toJson() => _$CatalogKnobToJson(this);
}

/// One widget in the tree.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogTreeNode {
  CatalogTreeNode({
    required this.id,
    required this.type,
    required this.depth,
    this.description,
    this.source,
    this.local = false,
    this.offstage,
    this.rect,
    this.constraints,
    this.flex,
    this.flexChild,
  });

  /// The child-index path from the demo's root — `''`, `0`, `0/1`.
  ///
  /// Derived from the tree's shape and never assigned, because every `fw`
  /// invocation and every MCP call is a fresh process: an id minted by one of
  /// them means nothing to the next. Pass it back to `screenshot --node` or
  /// `tree --node`.
  final String id;

  /// The widget's runtime type.
  final String type;

  /// How deep below the demo's root, so a flat list still reads as a tree.
  final int depth;

  /// The framework's one-line description when it says more than [type] does
  /// — `Text("Save")` rather than `Text`.
  final String? description;

  /// `path/to/file.dart:12:5`, project-relative.
  ///
  /// Absent for a widget the compiler did not stamp. That is the whole of what
  /// `DaemonConfig.trackWidgetCreation` buys, and why it is on.
  final String? source;

  /// Whether the framework counts this as the user's code rather than
  /// `package:flutter`'s.
  final bool local;

  /// Present and true when this widget is in the tree but not on the screen —
  /// a route kept alive under the current one, `Offstage`, a hidden
  /// `IndexedStack` child.
  ///
  /// In `tree` it is the top of a subtree that was folded away (pass its id
  /// to `--node` to read inside); in `matches` it is a warning that the found
  /// widget is not on any screenshot, and its [rect] is where it *was*.
  final bool? offstage;

  /// Where it ended up: `x,y w×h`.
  ///
  /// Absent for a widget with no box of its own — a provider, a builder —
  /// which is most of a summary tree. Absent and "zero-sized" are different
  /// answers and only one of them is a bug, which is why this is nullable
  /// rather than zero-filled.
  final String? rect;

  /// What the parent allowed: `w 0.0..900.0, h 0.0..∞`.
  ///
  /// The other half of every layout question. A box that is 0 wide because it
  /// was handed `maxWidth: 0` is a different bug from one that chose to be,
  /// and the size alone cannot tell them apart.
  final String? constraints;

  /// For a `Row`, `Column` or `Flex`: `horizontal, start, center, max`.
  final String? flex;

  /// For a *child* of one: `flex 2 (tight)`, read off the parent data.
  final String? flexChild;

  Map<String, Object?> toJson() => _$CatalogTreeNodeToJson(this);
}

/// One thing the framework reported.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogRenderError {
  CatalogRenderError({
    required this.exception,
    this.library,
    this.context,
    this.count = 1,
  });

  final String exception;

  /// `widgets library`, `rendering library` — which tells a layout overflow
  /// from a failed image load without reading the message.
  final String? library;

  /// What the framework was doing: `during layout`, `while painting`.
  final String? context;

  /// How many times this exact error was reported. An error thrown from
  /// `paint` fires once per frame.
  final int count;

  Map<String, Object?> toJson() => _$CatalogRenderErrorToJson(this);
}

/// `inspect` — one rendered build, and every projection of it that was asked
/// for.
///
/// **The one result shape that replaced four.** `tree`, `find`, `at` and
/// `errors` were not four capabilities; they were four questions about the same
/// frame, each paying its own compile, guest launch and render to answer one of
/// them. Three questions was three renders, and for an agent in a UI edit loop
/// that was the dominant per-iteration cost.
///
/// Every section is **absent unless it was asked for**, which is what keeps the
/// default answer small. `includeIfNull: false` does that in the JSON;
/// [nodeCount] and friends are nullable for the same reason. Zero nodes and no
/// tree requested are different answers.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogInspectResult implements PluginResult, ProducesArtifacts {
  CatalogInspectResult({
    required this.entry,
    required this.address,
    required this.readFrom,
    required this.ok,
    required this.errors,
    this.tree,
    this.matches,
    this.at,
    this.logs,
    this.logsDropped,
    this.screenshot,
  });

  final String entry;
  final String address;

  /// Where this reading came from: `live` when it was taken from a session
  /// somebody has open — the demo in whatever state they left it, including
  /// anything they reached by clicking — and `render` when this call built and
  /// drew its own copy.
  ///
  /// **Always present, not only on the interesting case.** A caller that gets
  /// two different answers to the same invocation has to be able to see why,
  /// and an absent field is not an answer.
  ///
  /// It reads `render` unless `live: true` was asked for and a session happened
  /// to be open on this entry. Attaching is opt-in precisely because it makes
  /// the same command answer differently depending on what window is open.
  ///
  /// It matters most for the errors and the logs: `live` means these are what
  /// the demo has reported **since somebody opened it**, so a throw reached by
  /// clicking is in the list. No fresh render can produce that one, because no
  /// fresh render ever performs the click.
  final String readFrom;

  /// Whether it rendered without the framework reporting anything.
  ///
  /// **Present on every answer, whatever else was asked**, because it is the
  /// question behind asking at all — and because with no flags at all it *is*
  /// the answer. Stated rather than left to be inferred from an empty list: the
  /// question people ask is "is this one broken", and a caller should not have
  /// to know that zero errors means fine.
  final bool ok;

  final List<CatalogRenderError> errors;

  /// The tree, when `--tree` asked for it. Depth-first, root first.
  final List<CatalogTreeNode>? tree;

  /// The nodes matching `--find`.
  ///
  /// Its own section rather than sharing [tree], because they answer different
  /// questions and a caller that asked both should get both labelled. Merging
  /// them into one list would make "the tree" and "the three nodes I searched
  /// for" indistinguishable in the reply.
  final List<CatalogTreeNode>? matches;

  /// The chain under `--at`, outermost first — the thing under a cursor is
  /// usually a `Text` and the thing meant is the button around it.
  ///
  /// An empty list is an answer: nothing of the demo's is at that point.
  final List<CatalogTreeNode>? at;

  /// What the demo printed, when `--logs` asked.
  final List<String>? logs;

  /// How many earlier lines fell off the guest's buffer, when any did.
  ///
  /// Said rather than silently begun in the middle: a scrollback that quietly
  /// starts partway reads as one that has everything.
  final int? logsDropped;

  /// The picture, when `--screenshot` asked for one.
  ///
  /// An [Artifact] rather than a path, because a PNG produced here is the same
  /// kind of thing `screenshot` produces: it has an identity — the address
  /// records the device, the size, the knobs, the axes, the debug flags, the
  /// crop and whether it was annotated — so asking twice with the same flags
  /// overwrites one file and asking with different flags does not. A bare path
  /// would have made this the one place in the surface where a picture is less
  /// than an artifact.
  final Artifact? screenshot;

  /// [screenshot], where a surface that can render a picture will look for it.
  ///
  /// **Without this the flag quietly did half its job.** `screenshot` returns an
  /// `Artifact` as its whole value, so MCP turns it into an image and the agent
  /// sees the widget; `inspect --screenshot` carries one in a *field*, which
  /// reaches `JobResult.artifacts` only through this interface — so it came back
  /// as a path and nothing else. The caller most likely to hit that is the one
  /// that took the action's own advice and folded the picture into the render it
  /// was already paying for.
  ///
  /// `includeToJson: false` because the artifact is already on the wire under
  /// `screenshot`; this is the same value by the route a renderer looks down.
  @override
  @JsonKey(includeToJson: false)
  List<Artifact> get artifacts => [?screenshot];

  @override
  Map<String, Object?> toJson() => _$CatalogInspectResultToJson(this);
}

/// `audit` — every entry, and whether it compiles and renders.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogAuditResult implements PluginResult {
  CatalogAuditResult({
    required this.checked,
    required this.broken,
    required this.entries,
    this.unreachable = const [],
  });

  /// How many entries were looked at.
  final int checked;

  /// How many of them are broken — the number the whole thing exists to
  /// produce, so that a caller has an answer before it has read a list.
  final int broken;

  /// Only the ones with something to say.
  ///
  /// A passing entry contributes to [checked] and nothing else: an audit of a
  /// healthy repo should be a line, not a page, or nobody runs it twice.
  final List<CatalogAuditEntry> entries;

  /// Packages that could not be audited at all, which is not the same as a
  /// package whose entries are fine.
  ///
  /// Kept separate from [entries] and out of [checked] deliberately: an audit
  /// that quietly counted an unreachable package as clean would report a green
  /// repo on the strength of not having looked.
  final List<CatalogAuditFailure> unreachable;

  @override
  Map<String, Object?> toJson() => _$CatalogAuditResultToJson(this);
}

/// One entry that did not come through clean.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogAuditEntry {
  CatalogAuditEntry({
    required this.id,
    required this.address,
    required this.compiles,
    this.compileError,
    this.errors = const [],
  });

  final String id;
  final String address;

  /// False when the compiler quarantined it. A quarantined entry has no
  /// [errors] — it never ran, and inventing an empty list would read as
  /// "rendered fine".
  final bool compiles;

  /// The compiler's diagnostics, verbatim.
  final String? compileError;

  final List<CatalogRenderError> errors;

  Map<String, Object?> toJson() => _$CatalogAuditEntryToJson(this);
}

/// A package the audit could not reach.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogAuditFailure {
  CatalogAuditFailure({required this.package, required this.error});

  final String package;
  final String error;

  Map<String, Object?> toJson() => _$CatalogAuditFailureToJson(this);
}

/// `build-web` — where the browsable page was written.
///
/// A directory rather than an [Artifact]: an artifact carries one file and a
/// MIME type, and a Flutter web build is a tree whose entry point happens to be
/// `index.html`. Naming both is what lets a caller serve the first and open the
/// second without guessing the relationship.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class CatalogWebBuildResult implements PluginResult {
  CatalogWebBuildResult({
    required this.package,
    required this.output,
    required this.indexHtml,
    required this.entries,
    required this.durationMs,
  });

  final String package;

  /// The directory to serve, worktree-relative where it is inside the worktree
  /// — a path that survives being read on another machine.
  final String output;

  /// The page to open, relative to the same root as [output].
  final String indexHtml;

  /// How many entries the page can show.
  final int entries;

  final int durationMs;

  @override
  Map<String, Object?> toJson() => _$CatalogWebBuildResultToJson(this);
}

/// `compare` — the verdict of one comparison run, both halves.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ComparisonCompareResult implements PluginResult {
  ComparisonCompareResult({
    required this.against,
    required this.baseSha,
    required this.counts,
    required this.findings,
    required this.index,
    this.export,
    this.report,
    this.scenariosNote,
  });

  /// What the comparison was against — the ref's name, as a header shows it.
  final String against;

  /// The merge base it resolved to.
  final String baseSha;

  /// Every row by state, both halves merged: `{"changed": 2, "skipped": 9}`.
  /// One preview that broke and one scenario that broke is two broken things;
  /// which half they came from is the second question, and the findings below
  /// answer it.
  final Map<String, int> counts;

  /// The rows worth attention, worst first. The `same` and `skipped` rows are
  /// in the artifact at [index], where a reader who needs proof of coverage
  /// finds them.
  final List<ComparisonFinding> findings;

  /// The whole verdict as a file — every row, every channel, the shot keys.
  final String index;

  /// The browsable page, when `export` asked for one. Serve it over HTTP.
  final String? export;

  /// The PR report directory, when `report` asked for one: `comment.md`,
  /// `mosaic.png`, the page under `web/`.
  final String? report;

  /// Why the scenario half has nothing to say, when it has nothing to say —
  /// a base harness that would not build reads differently from a project
  /// with no scenarios.
  final String? scenariosNote;

  @override
  Map<String, Object?> toJson() => _$ComparisonCompareResultToJson(this);
}

/// One row that came out worth looking at.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ComparisonFinding {
  ComparisonFinding({
    required this.id,
    required this.half,
    required this.state,
    this.note,
    this.delta,
  });

  /// The entry id, or the scenario id for a flow.
  final String id;

  /// `previews` or `scenarios`.
  final String half;

  /// `broke`, `failed`, `wasBroken`, `added`, `removed` or `changed` —
  /// declared worst-first, and the list is sorted by it.
  final String state;

  /// Why it is in the state it is, when the state alone does not say.
  final String? note;

  /// The size of the change: `0.38% · 2 regions` for pixels, the step that
  /// moved for a flow.
  final String? delta;

  Map<String, Object?> toJson() => _$ComparisonFindingToJson(this);
}
