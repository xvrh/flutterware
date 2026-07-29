import 'live_region.dart';

/// One thing the first run has to do before there is a window.
class LaunchStage {
  LaunchStage(this.label, {required this.budget});

  /// What it is, in the imperative and short enough to sit in a column.
  final String label;

  /// Roughly how long it takes when it is behaving.
  final Duration budget;

  var state = LaunchStageState.waiting;

  /// When it started, measured on the plan's clock rather than its own, so a
  /// stage that runs beside another can be timed without a second stopwatch.
  Duration began = Duration.zero;
  Duration elapsed = Duration.zero;
}

enum LaunchStageState { waiting, running, done, failed }

/// The first run, narrated as a plan rather than as a sequence of surprises.
///
/// The difference from [Step] is one claim. A step says *this is taking 18
/// seconds and about 25 was expected*, which answers "is it stuck". Only a plan
/// answers "how much is left" — and at second 20 of a 34-second first run, that
/// is the question. Listing the stages before any of them runs costs nothing
/// and is the entire feature.
///
/// Off a terminal it prints exactly what a sequence of [Step]s printed: one
/// line per stage, when the stage starts. A CI log is unchanged by this class
/// existing, which is the only way it was allowed to exist.
class LaunchPlan {
  LaunchPlan(
    this.stages, {
    required this.out,
    required this.interactive,
    this.title,
    this.subtitle,
  });

  /// Every stage that is going to run, in the order they were planned. Stages
  /// that run concurrently are still listed once each.
  final List<LaunchStage> stages;

  final StringSink out;

  /// Whether to draw. See `outputIsInteractive`; passed in rather than read so
  /// a test writing to a [StringBuffer] gets the non-drawing rendering.
  final bool interactive;

  final String? title;
  final String? subtitle;

  final _watch = Stopwatch();
  LiveRegion? _region;
  var _finished = false;

  Duration get elapsed => _watch.elapsed;

  Duration get _budget =>
      stages.fold(Duration.zero, (total, stage) => total + stage.budget);

  int get _labelWidth =>
      stages.map((s) => s.label.length).fold(0, (a, b) => a > b ? a : b);

  void start() {
    _watch.start();
    if (!interactive) return;
    _region = LiveRegion(out: out, rows: _rows)..start();
  }

  /// Narrates [body] as [stage], and keeps narrating whatever else is running.
  ///
  /// Several of these may be in flight at once — that is the point of the class
  /// and the reason a stage carries its own [LaunchStage.began] rather than
  /// borrowing the plan's elapsed time.
  ///
  /// [ok] decides which ending is drawn, because the failures here are exit
  /// codes rather than exceptions, and passing it is what makes a stage
  /// impossible to leave marked as running.
  Future<T> run<T>(
    LaunchStage stage,
    Future<T> Function() body, {
    bool Function(T result) ok = _alwaysOk,
  }) async {
    stage
      ..state = LaunchStageState.running
      ..began = _watch.elapsed;
    if (!interactive) {
      out.writeln('${stage.label}… (~${_seconds(stage.budget)})');
    }
    var succeeded = false;
    try {
      var result = await body();
      succeeded = ok(result);
      return result;
    } finally {
      stage
        ..elapsed = _watch.elapsed - stage.began
        ..state = succeeded ? LaunchStageState.done : LaunchStageState.failed;
    }
  }

  /// Stops the plan, keeping the finished rows on screen.
  ///
  /// Kept rather than erased in both endings: on success the row timings are
  /// the answer to "what took so long", and on failure the ✗ says which stage
  /// the error below it came from.
  void finish({String? closing}) {
    _watch.stop();
    _finished = true;
    // The blank line the footer used to occupy: without it the closing line
    // reads as a fourth stage rather than as the end of the list.
    _region?.settle(
      trailing: [
        if (closing != null) ...['', '  $closing'],
        '',
      ],
    );
    _region = null;
  }

  List<String> _rows() => [
    '',
    if (title case var title?) '  ${Ansi.style(title, Ansi.bold)}',
    if (subtitle case var subtitle?) '  ${Ansi.style(subtitle, Ansi.dim)}',
    '',
    for (var stage in stages) _stageRow(stage),
    // The footer is a projection, and a projection outlives its usefulness the
    // moment the thing it was projecting has happened. Kept in the last frame
    // it would sit above the closing line saying how much is left of a run
    // that is over.
    if (!_finished) ...['', '  ${Ansi.style(_footer(), Ansi.dim)}'],
  ];

  String _stageRow(LaunchStage stage) {
    var label = stage.label.padRight(_labelWidth);
    return switch (stage.state) {
      LaunchStageState.waiting => Ansi.style(
        '  ·  $label  ${_seconds(stage.budget).padLeft(10)}',
        Ansi.dim,
      ),
      LaunchStageState.running =>
        '  ${Ansi.style(Ansi.spinner(_watch.elapsed), Ansi.busy)}  $label  '
            '${'${_seconds(_watch.elapsed - stage.began)} / '
                '${_seconds(stage.budget)}'.padLeft(10)}',
      LaunchStageState.done =>
        '  ${Ansi.style('✓', Ansi.ok)}  ${Ansi.style(label, Ansi.dim)}  '
            '${_seconds(stage.elapsed).padLeft(10)}',
      LaunchStageState.failed =>
        '  ${Ansi.style('✗', Ansi.bad)}  $label  '
            '${_seconds(stage.elapsed).padLeft(10)}',
    };
  }

  /// Elapsed against what is left, which is the number the stage rows cannot
  /// give on their own.
  ///
  /// Budgets rather than a projection: a stage that has not started has no
  /// evidence to project from, and a remaining time that jumps around as each
  /// stage finishes is worse than one that is merely approximate.
  String _footer() {
    var left = _budget - _watch.elapsed;
    if (left < Duration.zero) left = Duration.zero;
    return '${_seconds(_watch.elapsed)} elapsed · about ${_seconds(left)} left';
  }

  static bool _alwaysOk(Object? result) => true;

  static String _seconds(Duration duration) => '${duration.inSeconds}s';
}
