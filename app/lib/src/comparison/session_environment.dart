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
import 'cancel.dart';
import 'channels.dart';
import 'comparison_controller.dart';
import 'last_run.dart';
import 'last_run_store.dart';
import 'previews_side.dart';
import 'runner.dart';
import 'scenario_comparison.dart';
import 'scenarios_runner.dart';
import 'scenarios_side.dart';
import 'shot_cache.dart';
import 'skip.dart';

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
    this.headCommit,
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
    String? headCommit;
    try {
      topLevel = await BaseRef.topLevelOf(session.worktree.path);
      base = await BaseRef.resolve(topLevel, ref: baseRef);
      headCommit = await BaseRef.headOf(topLevel);
    } on Object {
      return null;
    }
    return SessionComparisonEnvironment(
      session: session,
      flutterSdk: flutterSdk,
      appToolDirectory: appToolDirectory,
      topLevel: topLevel,
      base: base,
      headCommit: headCommit,
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

  @override
  String get baseSha => base.sha;

  /// Where HEAD sat when this environment was built — the head half of the
  /// "has anything moved since" check against a kept run.
  @override
  final String? headCommit;

  @override
  bool get baseCheckoutReady => BaseCheckout.isReady(base.sha);

  late final LastRunStore _lastRuns = LastRunStore(
    comparisonDirFor(cacheRoot, session.worktree),
  );

  @override
  Future<LastComparison?> lastRun(ComparisonHalfKind kind) async =>
      _lastRuns.read(kind);

  @override
  Future<void> saveLastRun(ComparisonHalfKind kind, LastComparison last) async {
    _lastRuns.write(kind, last);
  }

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

  @override
  late final ShotCache shots = ShotCache(p.join(cacheRoot, 'shots'));

  ShotCache get _cache => shots;

  @override
  Future<String> prepareBase({void Function(String phase)? onProgress}) async {
    var sha7 = base.sha.length > 7 ? base.sha.substring(0, 7) : base.sha;
    onProgress?.call(
      baseCheckoutReady
          ? 'reusing the base checkout of $sha7'
          : 'checking out $sha7',
    );
    var checkout = await BaseCheckout.ensure(
      repoRoot: topLevel,
      sha: base.sha,
      cacheRoot: BaseCheckout.defaultRoot,
      resolve: (path) async {
        // SDK links are machine-made and `.gitignore` hides them, so a fresh
        // checkout has none. The base is given the SDK this session runs
        // under, which is the only SDK flutterware has: the one the invocation
        // named.
        //
        // Nothing checks whether the base commit wanted a different one — see
        // the note on the cache key in `ComparisonRunner.plan`.
        var link = Link(p.join(path, '.fvm', 'flutter_sdk'));
        if (!link.existsSync()) {
          Directory(p.dirname(link.path)).createSync(recursive: true);
          link.createSync(flutterSdk.root);
        }
        onProgress?.call(
          'resolving dependencies in the base checkout (flutter pub get)',
        );
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
  Future<ComparisonResult> runPreviews(
    String baseRoot, {
    required void Function(ComparedItem row) onRow,
    void Function(int total, List<String> toAnswer)? onPlan,
    void Function(String phase)? onProgress,
    CancelToken? cancel,
  }) async {
    var runner = _previewsRunner(
      baseRoot,
      onItem: onRow,
      onPlan: onPlan == null
          ? null
          : (plan) => onPlan(plan.total, plan.toRender),
      onProgress: onProgress,
      cancel: cancel,
    );
    if (runner == null) {
      throw StateError('no package declares previews');
    }
    return runner.run();
  }

  @override
  Future<ScenarioResults> runScenarios(
    String baseRoot, {
    required void Function(ScenarioComparison scenario) onScenario,
    void Function(int total, List<String> toAnswer)? onPlan,
    void Function(String phase)? onProgress,
    CancelToken? cancel,
  }) async {
    var side = _scenariosSide();
    if (side == null) throw StateError('no package declares scenarios');
    onProgress?.call('building a scenario harness for each side');
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
        pixels: PixelInputs.of(
          packagePath: side.packagePath,
          roots: [topLevel, baseRoot],
        ),
        onScenario: onScenario,
        onPlan: onPlan == null
            ? null
            : (plan) => onPlan(plan.total, plan.toRun),
        onProgress: onProgress,
        cancel: cancel,
      ).run(
        outDir: p.join(
          comparisonDirFor(cacheRoot, session.worktree),
          'scenarios',
        ),
      );
    } finally {
      // Two `flutter_tester` processes and a build directory each. A panel
      // that navigated away mid-run would leak both without this.
      await source.dispose();
    }
  }

  ComparisonRunner? _previewsRunner(
    String baseRoot, {
    void Function(ComparedItem)? onItem,
    void Function(ComparisonPlan)? onPlan,
    void Function(String)? onProgress,
    CancelToken? cancel,
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
      onPlan: onPlan,
      onProgress: onProgress,
      cancel: cancel,
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
    p.join(comparisonDirFor(cacheRoot, session.worktree), 'index.json'),
  );
}
