import 'dart:io';

import 'package:path/path.dart' as p;

import '../plugins/native/previews_core.dart';
import '../plugins/native/previews_results.dart';
import '../plugins/native/scenarios_core.dart';
import '../session/session.dart';
import '../utils/run_dir.dart';
import 'artifact.dart';
import 'base_checkout.dart';
import 'base_ref.dart';
import 'channels.dart';
import 'scenario_comparison.dart';
import 'pr_report.dart';
import 'previews_side.dart';
import 'runner.dart';
import 'scenarios_runner.dart';
import 'scenarios_side.dart';
import 'shot_cache.dart';
import 'skip.dart';
import 'web_export.dart';

/// Why a comparison could not run at all — no previews, no base, a refusal.
///
/// One type for every surface: `fw compare` prints it and exits 64, the
/// `compare` action reports it as the failure, and neither invents its own
/// wording.
class CompareException implements Exception {
  CompareException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What one comparison was asked to do.
class CompareOptions {
  const CompareOptions({
    this.baseRef,
    this.package,
    this.entries = const [],
    this.export = false,
    this.exportDir,
    this.reportDir,
  });

  /// Overrides the base — anything git can name. Null resolves the project's
  /// default branch.
  final String? baseRef;

  /// Which previews package, worktree-relative. Null takes the first declared.
  final String? package;

  /// Narrow to these entry or scenario ids. Empty compares everything.
  final List<String> entries;

  /// Write the browsable page.
  final bool export;

  /// Where the page goes. Null and [export] picks
  /// `build/comparison/web` at the repository top level — or `<report>/web`
  /// when a report is being written, so a comment and the page it links are
  /// hosted together.
  final String? exportDir;

  /// Write `comment.md` + `mosaic.png` here. Implies the page under
  /// `<reportDir>/web`.
  final String? reportDir;
}

/// Everything one comparison concluded, with where it was written.
class CompareOutcome {
  const CompareOutcome({
    required this.artifact,
    required this.indexPath,
    required this.base,
    this.exported,
    this.report,
  });

  final ComparisonArtifact artifact;
  final String indexPath;
  final BaseRef base;
  final ComparisonWebExport? exported;
  final PrReport? report;
}

/// Runs a whole comparison — both halves, the artifact, and whatever outputs
/// [options] asked for.
///
/// **The one orchestration, however it is reached.** `fw compare`, the
/// `compare` action an agent invokes, and anything later all call this; the
/// order inside is the design and it is visible in the progress: the SDK check
/// refuses before anything is checked out, the skip rule decides before
/// anything is rendered, and only then does a guest start.
///
/// Refusals throw [CompareException]. Progress lines go to [onProgress]; the
/// halves land in [onPreviews] and [onScenarios] as they complete, because the
/// previews half is the fast one and a caller that waits for both shows a
/// report where it could have shown a wait.
Future<CompareOutcome> runComparison({
  required Session session,
  CompareOptions options = const CompareOptions(),
  void Function(String line)? onProgress,
  void Function(ComparisonResult result)? onPreviews,
  void Function(ScenarioResults results)? onScenarios,
}) async {
  PreviewsCore core;
  try {
    core = session.requireCore(uiCatalogPluginId) as PreviewsCore;
  } on SessionException catch (e) {
    throw CompareException('$e');
  }
  var packageInWorktree = options.package ?? core.packages.firstOrNull;
  if (packageInWorktree == null) {
    throw CompareException(
      'no package declares previews, so there is nothing to compare.',
    );
  }

  // The two sides are two *checkouts*, not two package directories: a base
  // checkout mirrors the whole worktree, so the package has to be named
  // relative to its top level. Running this from inside `examples/example`
  // reported every entry as added until it did.
  var top = await BaseRef.topLevelOf(session.worktree.path);
  var package = p.relative(
    p.normalize(p.join(session.worktree.path, packageInWorktree)),
    from: top,
  );
  BaseRef base;
  try {
    base = await BaseRef.resolve(top, ref: options.baseRef);
  } on BaseRefError catch (e) {
    throw CompareException('$e');
  }

  var sdk = session.workspace.flutterSdk;
  onProgress?.call(
    'Comparing against ${base.against} (${abbreviatedSha(base.sha)})…',
  );
  var checkout = await BaseCheckout.ensure(
    repoRoot: top,
    sha: base.sha,
    cacheRoot: BaseCheckout.defaultRoot,
    resolve: (path) async {
      // `.fvm/flutter_sdk` is a link some tool made and `.gitignore` hides,
      // so a fresh checkout has none and would resolve to whatever SDK
      // happens to be running this. The base is given the head's, and what
      // makes that legitimate rather than a fudge is that `.fvmrc` *is*
      // versioned — `SdkIdentity.pinned` compares the two commits' own
      // claims before it looks at any link.
      var link = Link(p.join(path, '.fvm', 'flutter_sdk'));
      if (!link.existsSync()) {
        Directory(p.dirname(link.path)).createSync(recursive: true);
        link.createSync(sdk.root);
      }
      // The base is the same resolution as the head, but it is a *different
      // directory*, and pub resolves per directory.
      onProgress?.call('Resolving the base checkout…');
      var result = await Process.run(sdk.flutter, [
        'pub',
        'get',
      ], workingDirectory: path);
      if (result.exitCode != 0) {
        throw StateError(
          'pub get failed in the base checkout:\n${result.stderr}',
        );
      }
    },
  );

  var shotCache = ShotCache(p.join(flutterwareDir(), 'shots'));
  var runner = ComparisonRunner(
    headRoot: top,
    baseRoot: checkout.path,
    baseSha: base.sha,
    cache: shotCache,
    only: options.entries.isEmpty ? null : options.entries,
    side: PreviewsSide(
      dartExecutable: p.join(sdk.root, 'bin', 'dart'),
      flutterSdkRoot: sdk.root,
      appToolDirectory: session.workspace.appContext.appToolDirectory.path,
      packagePath: package,
      root: core.rootFor(packageInWorktree),
      previewAnnotations: core.previewAnnotationsFor(packageInWorktree),
    ),
  );

  ComparisonResult result;
  try {
    result = await runner.run();
  } on ComparisonRefused catch (e) {
    throw CompareException('$e');
  }
  onPreviews?.call(result);

  var scenarios = await _compareScenarios(
    session: session,
    top: top,
    baseRoot: checkout.path,
    sdkRoot: sdk.root,
    only: options.entries,
    cache: shotCache,
    onProgress: onProgress,
  );
  if (scenarios != null) onScenarios?.call(scenarios);

  // Written once both halves are in. The artifact is the whole verdict, so a
  // file holding only the previews would be a file that answers "did this
  // branch break anything" wrongly.
  var artifact = ComparisonArtifact(previews: result, scenarios: scenarios);
  var index = artifact.writeTo(
    p.join(comparisonDirFor(flutterwareDir(), session.worktree), 'index.json'),
  );

  // The page rides inside the report when both are asked for: a comment that
  // links a viewer wants them hosted together.
  ComparisonWebExport? exported;
  if (options.export || options.reportDir != null) {
    var exporter = ComparisonWebExporter(
      flutterExecutable: sdk.flutter,
      appToolRoot: session.workspace.appContext.appToolDirectory.path,
    );
    exported = await exporter.export(
      index: artifact.toJson(),
      cache: shotCache,
      against: base.against,
      output:
          options.exportDir ??
          (options.reportDir != null
              ? p.join(options.reportDir!, 'web')
              : p.join(top, 'build', 'comparison', 'web')),
      onOutput: onProgress,
    );
  }
  PrReport? report;
  if (options.reportDir != null) {
    report = writePrReport(
      artifact: artifact,
      cache: shotCache,
      against: base.against,
      directory: options.reportDir!,
    );
  }

  return CompareOutcome(
    artifact: artifact,
    indexPath: index.path,
    base: base,
    exported: exported,
    report: report,
  );
}

String abbreviatedSha(String sha) => sha.length > 8 ? sha.substring(0, 8) : sha;

/// The `compare` action, as the previews core invokes it.
///
/// The core cannot run this itself — a comparison spans the previews and
/// scenarios plugins, and a core cannot see its siblings — so the session
/// installs this closure on construction. One orchestration behind every
/// surface: `fw compare`, `fw run previews compare`, and the MCP invoke are
/// all [runComparison].
Future<ComparisonCompareResult> runCompareAction({
  required Session session,
  required Map<String, Object?> arguments,
}) async {
  var entry = arguments['entry'] as String?;
  var export = arguments['export'];
  var outcome = await runComparison(
    session: session,
    options: CompareOptions(
      baseRef: arguments['base'] as String?,
      package: arguments['package'] as String?,
      entries: [?entry],
      export: export == true || export == 'true',
      reportDir: arguments['report'] as String?,
    ),
  );

  var artifact = outcome.artifact;
  // Worst first across both halves, the way every list on this surface ranks.
  var ranked =
      <(ComparedState, ComparisonFinding)>[
        for (var item in artifact.previews.items)
          if (_isFinding(item.state))
            (
              item.state,
              ComparisonFinding(
                id: item.id,
                half: 'previews',
                state: item.state.name,
                note: item.note,
                delta: _pixelsDelta(item),
              ),
            ),
        for (var scenario
            in artifact.scenarios?.items ?? const <ScenarioComparison>[])
          if (_isFinding(scenario.state))
            (
              scenario.state,
              ComparisonFinding(
                id: scenario.scenario,
                half: 'scenarios',
                state: scenario.state.name,
                delta: _scenarioDelta(scenario),
              ),
            ),
      ]..sort(
        (a, b) => a.$1.index == b.$1.index
            ? a.$2.id.compareTo(b.$2.id)
            : a.$1.index.compareTo(b.$1.index),
      );

  var report = outcome.report;
  return ComparisonCompareResult(
    against: outcome.base.against,
    baseSha: outcome.base.sha,
    counts: {
      for (var entry in artifact.counts.entries) entry.key.name: entry.value,
    },
    findings: [for (var (_, finding) in ranked) finding],
    index: outcome.indexPath,
    export: outcome.exported?.output,
    report: report == null ? null : p.dirname(report.commentPath),
    scenariosNote: artifact.scenarios?.note,
  );
}

bool _isFinding(ComparedState state) =>
    state != ComparedState.same && state != ComparedState.skipped;

String? _pixelsDelta(ComparedItem item) {
  var pixels = item.pixels?.diff;
  if (pixels == null || !pixels.changed) return null;
  return '${(pixels.fraction * 100).toStringAsFixed(2)}% · '
      '${pixels.clusters.length} '
      'region${pixels.clusters.length == 1 ? '' : 's'}';
}

String? _scenarioDelta(ScenarioComparison scenario) {
  for (var step in scenario.items) {
    if (_isFinding(step.state)) return 'step `${step.id}`';
  }
  if (scenario.branches.isNotEmpty) {
    return '${scenario.branches.length} '
        'branch${scenario.branches.length == 1 ? '' : 'es'}';
  }
  return null;
}

/// The scenario half of a comparison.
///
/// Separate from the previews half rather than folded into the same runner,
/// and the design doc argues why at length: a preview is one picture and a
/// scenario is a *tree* of them. What they share is the kernel — the same
/// pixel, tree and text channels — and the skip rule, which asks the same
/// question of a scenario's closure that it asks of an entry's.
Future<ScenarioResults?> _compareScenarios({
  required Session session,
  required String top,
  required String baseRoot,
  required String sdkRoot,
  required List<String> only,
  required ShotCache cache,
  void Function(String line)? onProgress,
}) async {
  var watch = Stopwatch()..start();
  ScenariosCore core;
  try {
    core = session.requireCore(scenariosPluginId) as ScenariosCore;
  } on SessionException {
    // No scenarios plugin at all: the artifact says nothing about scenarios
    // rather than saying there are none, which are different claims.
    return null;
  }
  var package = core.packages.firstOrNull;
  if (package == null) return null;

  var side = ScenariosSide(
    flutterSdkRoot: sdkRoot,
    packagePath: p.relative(
      p.normalize(p.join(session.worktree.path, package)),
      from: top,
    ),
    directory: core.scanRootFor(package),
  );
  var source = LiveScenarioSource(
    side: side,
    headRoot: top,
    baseRoot: baseRoot,
  );
  try {
    try {
      return await ScenariosRunner(
        headRoot: top,
        baseRoot: baseRoot,
        source: source,
        cache: cache,
        extraPaths: pixelInputsOf(
          packagePath: side.packagePath,
          roots: [top, baseRoot],
        ),
        only: only.isEmpty ? null : only,
      ).run(
        outDir: p.join(
          comparisonDirFor(flutterwareDir(), session.worktree),
          'scenarios',
        ),
      );
    } on Object catch (error) {
      // A side whose harness will not build is a side, not a crash — the same
      // rule the previews half follows, and the same skew causes it. It goes
      // into the artifact too: an empty list is what a project with no
      // scenarios leaves behind, and a reader has to be able to tell the two
      // apart.
      var note = '$error'.split('\n').first;
      onProgress?.call('scenarios: $note');
      return ScenarioResults.of(
        items: const [],
        ran: 0,
        skipped: 0,
        elapsed: watch.elapsed,
        note: note,
      );
    }
  } finally {
    await source.dispose();
  }
}
