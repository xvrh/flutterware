import 'dart:io';

import 'package:path/path.dart' as p;

import '../plugins/native/previews_core.dart';
import '../plugins/native/scenarios_core.dart';
import '../plugins/worktree_session.dart';
import '../utils/flutter_sdk.dart';
import '../utils/run_dir.dart';
import 'artifact.dart';
import 'base_checkout.dart';
import 'base_ref.dart';
import 'channels.dart';
import 'comparison_controller.dart';
import 'previews_side.dart';
import 'runner.dart';
import 'scenario_comparison.dart';
import 'scenarios_estimate.dart';
import 'scenarios_runner.dart';
import 'scenarios_side.dart';
import 'shot_cache.dart';

/// A comparison's world, built from an open worktree.
///
/// **The same runners `fw compare` drives, wired to a session instead of a
/// command line.** Nothing here decides anything: which entries are new, what
/// nothing touched, what order rows rank in are all the runners' business, and
/// this is the adapter that hands them a checkout, an SDK and a cache. A panel
/// that made any of those calls itself would be a second answer to a question
/// the CLI already answers.
class SessionComparisonEnvironment implements ComparisonEnvironment {
  SessionComparisonEnvironment({
    required this.session,
    required this.flutterSdk,
    required this.appToolDirectory,
    required this.topLevel,
    required this.base,
    String? cacheRoot,
  }) : cacheRoot = cacheRoot ?? flutterwareDir();

  /// Builds one for [session], resolving the repository top level and the base
  /// ref. Returns null when the worktree is not in a git repository at all —
  /// there is nothing to compare against, and no screen to draw.
  static Future<SessionComparisonEnvironment?> open({
    required WorktreeSession session,
    required FlutterSdkPath flutterSdk,
    required String appToolDirectory,
    String? baseRef,
  }) async {
    String topLevel;
    BaseRef base;
    try {
      topLevel = await BaseRef.topLevelOf(session.worktree.path);
      base = await BaseRef.resolve(topLevel, ref: baseRef);
    } on Object {
      return null;
    }
    return SessionComparisonEnvironment(
      session: session,
      flutterSdk: flutterSdk,
      appToolDirectory: appToolDirectory,
      topLevel: topLevel,
      base: base,
    );
  }

  final WorktreeSession session;
  final FlutterSdkPath flutterSdk;
  final String appToolDirectory;

  /// The repository top level, which is what a base checkout mirrors. **Not
  /// the package directory**: a comparison run from inside `examples/example`
  /// reported every entry as added until this was the checkout root.
  final String topLevel;

  final BaseRef base;
  final String cacheRoot;

  @override
  String get headRoot => topLevel;

  @override
  String get baseLabel => base.against;

  PreviewsCore? get _previews =>
      session.session.coreById(uiCatalogPluginId) as PreviewsCore?;

  ScenariosCore? get _scenarios =>
      session.session.coreById(scenariosPluginId) as ScenariosCore?;

  @override
  bool get hasPreviews => _previewsPackage != null;

  @override
  bool get hasScenarios => _scenariosPackage != null;

  String? get _previewsPackage => _previews?.packages.firstOrNull;

  String? get _scenariosPackage => _scenarios?.packages.firstOrNull;

  /// A package's path relative to the checkout top level.
  String _relative(String packageInWorktree) => p.relative(
    p.normalize(p.join(session.worktree.path, packageInWorktree)),
    from: topLevel,
  );

  ShotCache get _cache => ShotCache(p.join(cacheRoot, 'shots'));

  @override
  Future<String> prepareBase() async {
    var checkout = await BaseCheckout.ensure(
      repoRoot: topLevel,
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
          link.createSync(flutterSdk.root);
        }
        var result = await Process.run(flutterSdk.flutter, [
          'pub',
          'get',
        ], workingDirectory: path);
        if (result.exitCode != 0) {
          throw StateError('pub get failed in the base checkout');
        }
      },
    );
    return checkout.path;
  }

  @override
  Future<String?> previewsEstimate(String baseRoot) async {
    var runner = _previewsRunner(baseRoot);
    if (runner == null) return null;
    return (await runner.plan()).estimate;
  }

  /// Parsed, never compiled — see [ScenariosEstimate]. The live listing costs a
  /// harness build and a guest on each side, which is the bulk of what running
  /// them costs, so an estimate that used it would be the work.
  @override
  Future<String?> scenariosEstimate(String baseRoot) async {
    var side = _scenariosSide();
    if (side == null) return null;
    return ScenariosEstimate.of(
      headRoot: topLevel,
      baseRoot: baseRoot,
      side: side,
      memo: _cache.memo,
    ).label;
  }

  @override
  Future<ComparisonResult> runPreviews(
    String baseRoot, {
    required void Function(ComparedItem row) onRow,
  }) async {
    var runner = _previewsRunner(baseRoot, onItem: onRow);
    if (runner == null) {
      throw StateError('no package declares previews');
    }
    return runner.run();
  }

  @override
  Future<ScenarioResults> runScenarios(
    String baseRoot, {
    required void Function(ScenarioComparison scenario) onScenario,
  }) async {
    var side = _scenariosSide();
    if (side == null) throw StateError('no package declares scenarios');
    var source = LiveScenarioSource(
      side: side,
      headRoot: topLevel,
      baseRoot: baseRoot,
    );
    try {
      return await ScenariosRunner(
        headRoot: topLevel,
        baseRoot: baseRoot,
        source: source,
        cache: _cache,
        onScenario: onScenario,
      ).run(outDir: p.join(cacheRoot, 'comparisons', 'scenarios'));
    } finally {
      // Two `flutter_tester` processes and a build directory each. A panel
      // that navigated away mid-run would leak both without this.
      await source.dispose();
    }
  }

  ComparisonRunner? _previewsRunner(
    String baseRoot, {
    void Function(ComparedItem)? onItem,
  }) {
    var core = _previews;
    var package = _previewsPackage;
    if (core == null || package == null) return null;
    return ComparisonRunner(
      headRoot: topLevel,
      baseRoot: baseRoot,
      baseSha: base.sha,
      cache: _cache,
      onItem: onItem,
      side: PreviewsSide(
        dartExecutable: p.join(flutterSdk.root, 'bin', 'dart'),
        flutterSdkRoot: flutterSdk.root,
        appToolDirectory: appToolDirectory,
        packagePath: _relative(package),
        root: core.rootFor(package),
        previewAnnotations: core.previewAnnotationsFor(package),
      ),
    );
  }

  ScenariosSide? _scenariosSide() {
    var core = _scenarios;
    var package = _scenariosPackage;
    if (core == null || package == null) return null;
    return ScenariosSide(
      flutterSdkRoot: flutterSdk.root,
      packagePath: _relative(package),
      directory: core.scanRootFor(package),
    );
  }

  /// Writes the artifact where `fw compare` writes it, so the GUI and the CLI
  /// leave one file rather than two.
  File writeIndex(ComparisonArtifact artifact) => artifact.writeTo(
    p.join(cacheRoot, 'comparisons', session.worktree.name, 'index.json'),
  );
}
