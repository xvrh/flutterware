import 'package:flutter/foundation.dart';

import 'artifact.dart';
import 'channels.dart';
import 'runner.dart';
import 'scenario_comparison.dart';
import 'shot_cache.dart';

/// Which half of a comparison, where both are spelled the same way.
enum ComparisonHalfKind {
  previews,
  scenarios;

  String get label => name;
}

/// Where one half of a comparison has got to.
///
/// Declared in the order a half moves through them, which is also the order a
/// tab reads: it can only go forward, and [refused] is the one exit.
enum HalfStage {
  /// The plugin is not declared here, so the tab does not exist.
  undeclared,

  /// Waiting on the base checkout, which both halves share.
  preparing,

  /// The base is ready and the estimate is known. Nothing has run.
  ready,

  /// Rendering or replaying. Rows arrive as they are decided.
  running,

  /// Everything this half has to say.
  done,

  /// It cannot run, and the reason is worth more than a spinner.
  refused,
}

/// One half of a comparison, as a tab draws it.
class ComparisonHalf extends ChangeNotifier {
  ComparisonHalf(this.kind, {HalfStage stage = HalfStage.preparing})
    // ignore: prefer_initializing_formals
    : _stage = stage;

  final ComparisonHalfKind kind;

  HalfStage _stage;
  HalfStage get stage => _stage;

  /// *14 of 213*, once known. Null while the base is still being prepared —
  /// and never faked, because a tab that guesses is a tab you stop reading.
  String? estimate;

  /// Why it cannot run: an SDK mismatch, a base whose harness will not build.
  String? refusal;

  /// Rows as they land, worst first. Filled while [stage] is [running], so a
  /// list has something to draw before the slowest entry is answered.
  final rows = <ComparedItem>[];

  /// The scenario half's rows, which are trees rather than entries.
  final scenarios = <ScenarioComparison>[];

  /// What the run concluded, once it has.
  ComparisonResult? previewsResult;
  ScenarioResults? scenarioResults;

  bool get isRunning => _stage == HalfStage.running;

  /// True once this half has run at least once — a re-entry joins rather than
  /// restarts.
  bool get hasRun => previewsResult != null || scenarioResults != null;

  void moveTo(HalfStage stage) {
    if (_stage == stage) return;
    _stage = stage;
    notifyListeners();
  }

  void refuse(String reason) {
    refusal = reason;
    moveTo(HalfStage.refused);
    // moveTo returns early when the stage already matches, and a second
    // refusal with a new reason has to reach the panel.
    notifyListeners();
  }

  void add(ComparedItem row) {
    rows
      ..add(row)
      ..sort(_bySeverity);
    notifyListeners();
  }

  void addScenario(ScenarioComparison scenario) {
    scenarios
      ..add(scenario)
      ..sort(
        (a, b) => a.state.index == b.state.index
            ? a.scenario.compareTo(b.scenario)
            : a.state.index.compareTo(b.state.index),
      );
    notifyListeners();
  }

  static int _bySeverity(ComparedItem a, ComparedItem b) =>
      a.state.index == b.state.index
      ? a.id.compareTo(b.id)
      : a.state.index.compareTo(b.state.index);
}

/// Everything a comparison needs from the world, as one seam.
///
/// **A seam rather than a session, for the reason the runners already have
/// one**: none of the sequencing here — when the base is prepared, what a tab
/// says before it is, what happens when a half refuses — needs a compiler, a
/// guest or a git worktree to be wrong. A fake environment makes the whole
/// controller testable in milliseconds.
abstract interface class ComparisonEnvironment {
  /// The checkout's top level, which is what both halves compare from. Not the
  /// package directory: a base checkout mirrors the whole worktree.
  String get headRoot;

  /// What is being compared against, for the header.
  String get baseLabel;

  /// Materialises the base and returns its path. Called once; both halves wait
  /// on the same future.
  Future<String> prepareBase();

  bool get hasPreviews;
  bool get hasScenarios;

  /// Where the frames a comparison rendered are filed.
  ///
  /// Exposed because a verdict is not a picture: `ComparedItem.shots` names two
  /// keys, and something has to be able to open them.
  ShotCache get shots;

  /// *14 of 213* for the previews half, or null when it cannot be worked out.
  Future<String?> previewsEstimate(String baseRoot);

  /// The same for scenarios, worked out by parsing rather than by compiling —
  /// see `ScenariosEstimate`.
  Future<String?> scenariosEstimate(String baseRoot);

  Future<ComparisonResult> runPreviews(
    String baseRoot, {
    required void Function(ComparedItem row) onRow,
  });

  Future<ScenarioResults> runScenarios(
    String baseRoot, {
    required void Function(ScenarioComparison scenario) onScenario,
  });
}

/// Owns one worktree's comparison: prepares the base once, and runs a half
/// when its tab is opened.
///
/// **The base is prepared on the panel, the halves run on their tabs.** Both
/// halves need the base checkout before they can say anything at all — even
/// how much they would cost — so preparing it on arrival is what lets a tab
/// carry its estimate. Rendering and replaying stay behind the tab, because
/// opening a panel must not spawn two compilers and a `flutter_tester` for a
/// half nobody asked for. That is §13.11 narrowed, not reversed: there is
/// still no Run button.
class ComparisonController extends ChangeNotifier {
  ComparisonController(this.environment)
    : previews = ComparisonHalf(
        ComparisonHalfKind.previews,
        stage: environment.hasPreviews
            ? HalfStage.preparing
            : HalfStage.undeclared,
      ),
      scenarios = ComparisonHalf(
        ComparisonHalfKind.scenarios,
        stage: environment.hasScenarios
            ? HalfStage.preparing
            : HalfStage.undeclared,
      ) {
    previews.addListener(notifyListeners);
    scenarios.addListener(notifyListeners);
  }

  final ComparisonEnvironment environment;

  final ComparisonHalf previews;
  final ComparisonHalf scenarios;

  /// The base checkout, once it exists.
  String? baseRoot;

  /// Why nothing can be compared at all — a base that will not check out.
  String? refusal;

  Future<void>? _preparing;
  var _disposed = false;

  ComparisonHalf halfFor(ComparisonHalfKind kind) =>
      kind == ComparisonHalfKind.previews ? previews : scenarios;

  /// Both halves, in tab order, skipping the ones this project does not
  /// declare. A tab that would always say "no previews here" should not exist.
  List<ComparisonHalf> get declared => [
    for (var half in [previews, scenarios])
      if (half.stage != HalfStage.undeclared) half,
  ];

  /// Prepares the base and works out both estimates. Idempotent: arriving a
  /// second time joins the first.
  Future<void> prepare() => _preparing ??= _prepare();

  Future<void> _prepare() async {
    String root;
    try {
      root = await environment.prepareBase();
    } on Object catch (error) {
      var reason = _firstLine(error);
      refusal = reason;
      for (var half in declared) {
        half.refuse(reason);
      }
      notifyListeners();
      return;
    }
    if (_disposed) return;
    baseRoot = root;

    // Each estimate answers for its own half: an SDK mismatch refuses at plan
    // time, and it should stop that tab rather than the panel.
    await Future.wait([
      _estimate(previews, () => environment.previewsEstimate(root)),
      _estimate(scenarios, () => environment.scenariosEstimate(root)),
    ]);
  }

  Future<void> _estimate(
    ComparisonHalf half,
    Future<String?> Function() compute,
  ) async {
    if (half.stage == HalfStage.undeclared) return;
    try {
      var estimate = await compute();
      if (_disposed) return;
      half.estimate = estimate;
      half.moveTo(HalfStage.ready);
    } on Object catch (error) {
      if (_disposed) return;
      half.refuse(_firstLine(error));
    }
  }

  /// Runs [kind] if it has not run and is not running.
  ///
  /// **A run already in flight is joined, never restarted.** Clicking back and
  /// forth between two tabs is a thing people do, and a comparison that
  /// restarted on each visit would never finish one.
  Future<void> open(ComparisonHalfKind kind) async {
    await prepare();
    var half = halfFor(kind);
    var root = baseRoot;
    if (root == null ||
        half.stage == HalfStage.undeclared ||
        half.stage == HalfStage.refused ||
        half.isRunning ||
        half.hasRun) {
      return;
    }

    half
      ..rows.clear()
      ..scenarios.clear()
      ..moveTo(HalfStage.running);
    try {
      switch (kind) {
        case ComparisonHalfKind.previews:
          half.previewsResult = await environment.runPreviews(
            root,
            onRow: (row) {
              if (!_disposed) half.add(row);
            },
          );
        case ComparisonHalfKind.scenarios:
          half.scenarioResults = await environment.runScenarios(
            root,
            onScenario: (scenario) {
              if (!_disposed) half.addScenario(scenario);
            },
          );
      }
      if (_disposed) return;
      half.moveTo(HalfStage.done);
    } on Object catch (error) {
      if (_disposed) return;
      half.refuse(_firstLine(error));
    }
  }

  /// Throws away what a half concluded so the next [open] runs it again.
  ///
  /// The estimate is recomputed with it: the reason you are refreshing is that
  /// the worktree moved, and a stale *14 of 213* beside fresh rows is the one
  /// number nobody would question.
  Future<void> refresh(ComparisonHalfKind kind) async {
    var half = halfFor(kind);
    if (half.stage == HalfStage.undeclared || half.isRunning) return;
    half
      ..previewsResult = null
      ..scenarioResults = null
      ..refusal = null
      ..rows.clear()
      ..scenarios.clear()
      ..estimate = null
      ..moveTo(HalfStage.preparing);
    var root = baseRoot;
    if (root != null) {
      await _estimate(
        half,
        () => switch (kind) {
          ComparisonHalfKind.previews => environment.previewsEstimate(root),
          ComparisonHalfKind.scenarios => environment.scenariosEstimate(root),
        },
      );
    }
    await open(kind);
  }

  /// Both halves as one file, once at least one of them has run.
  ComparisonArtifact? get artifact {
    var result = previews.previewsResult;
    if (result == null) return null;
    return ComparisonArtifact(
      previews: result,
      scenarios: scenarios.scenarioResults,
    );
  }

  /// The readable part of an error, without the stack of nested prefixes.
  ///
  /// **Not always one line.** A daemon failure ends its first line with a colon
  /// and puts what actually went wrong on the next, so a strict first-line rule
  /// renders a sentence that stops mid-thought — which reads as a truncation
  /// bug rather than as the reason it is.
  static String _firstLine(Object error) {
    var lines = [
      for (var line in '$error'.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) return '$error';
    var first = lines.first.replaceFirst(RegExp(r'^\w+: '), '');
    if (!first.endsWith(':') || lines.length < 2) return first;
    return '$first ${lines[1]}';
  }

  @override
  void dispose() {
    _disposed = true;
    previews.dispose();
    scenarios.dispose();
    super.dispose();
  }
}
