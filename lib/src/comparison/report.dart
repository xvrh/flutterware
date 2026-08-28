import 'channels.dart';
import 'scenario_comparison.dart';

/// The format `index.json` is written in.
///
/// Bumped only when a reader of the previous version would get something
/// wrong. Added fields do not bump it — an older reader ignoring a new key is
/// the behaviour that makes adding one cheap, and every field below was added
/// to a file that shipped without it.
const comparisonReportVersion = 1;

/// What a comparison writes its whole verdict to, in the cache and inside an
/// export alike.
const comparisonReportFile = 'index.json';

/// Which half a row came from.
///
/// The halves are named rather than merged because they are compared by
/// different machinery and a row from one is not interchangeable with a row
/// from the other — but the *counts* merge, because "did this branch break
/// anything" is a question about the branch.
enum ComparedHalfKind { previews, scenarios }

/// Where the frames a report names actually are.
///
/// The one thing that separates the two files both called `index.json`, and
/// the reason it is written down rather than guessed at from whether a path
/// looks absolute. A reader that guesses wrong hands back paths that do not
/// exist, which is worse than refusing.
enum ComparisonFrames {
  /// Relative to the directory holding the `index.json` — what `--export` and
  /// `--report=` write, and the only portable form: the frames beside it are
  /// PNGs, and the whole directory can be uploaded and read anywhere.
  ///
  /// Says how the frames it *did* write are named, not that it wrote one for
  /// every reference. An export encodes what the shot cache still held, and a
  /// frame evicted before it ran keeps its original reference — which is why
  /// `ComparisonReport.frame` answers with null rather than a path.
  relative,

  /// This machine only. A preview's frames are `ShotCache` keys, computed
  /// from a closure fingerprint nothing outside the runner reproduces; a
  /// scenario step's are absolute paths to headerless raw frames under
  /// `~/.flutterware`. Neither survives leaving the machine, so
  /// `ComparisonReport.frame` refuses rather than pretending.
  local,
}

/// What one half of a comparison did.
///
/// Not the writer's `ComparisonResult`/`ScenarioResults`, deliberately: those
/// exist to *conclude* a run and carry things a file cannot — the elapsed
/// stopwatch, a live item list. This holds what the file says and nothing it
/// would have to invent.
class ComparedHalf {
  const ComparedHalf({
    this.worked = 0,
    this.skipped = 0,
    this.ms = 0,
    this.counts = const {},
    this.because = const {},
    this.note,
  });

  /// What the half actually did, in its own unit — the previews half counts
  /// *renders*, up to two per entry because a row has two sides; the scenario
  /// half counts whole scenarios replayed. Named per half in the file
  /// (`rendered` and `ran`) and read into one field here, because the question
  /// the two numbers answer is the same one: did the skip rule earn its keep.
  final int worked;

  /// Rows the skip rule answered without looking at a picture.
  final int skipped;

  final int ms;

  final Map<ComparedState, int> counts;

  /// Why the skip rule could not answer what it could not answer — one clause
  /// naming a path, and how many rows carried it.
  ///
  /// The other half of [worked]. That number says the skip rule did not earn
  /// its keep; this one says which path both checkouts disagreed about, which
  /// is the only form of the answer anybody can act on. Empty when there was
  /// nothing to explain.
  final Map<String, int> because;

  /// Why this half has nothing to say, when it has nothing to say.
  ///
  /// A harness that would not build leaves the same empty list as a project
  /// with no scenarios at all, and the same counts. This is the only thing
  /// separating them, so a reader that ignores it will read a silent half as a
  /// clean one.
  final String? note;

  static ComparedHalf fromJson(Map<String, Object?> json) {
    var counts = _counts(json['counts']);
    return ComparedHalf(
      // `rendered` is the previews half's word, `ran` the scenario half's.
      worked: (json['rendered'] ?? json['ran']) as int? ?? 0,
      // The scenario half records this; the previews half never has, because
      // its own counts already carry it. Read from there rather than left at
      // zero, which is a number and therefore reads as an answer.
      skipped: json['skipped'] as int? ?? counts[ComparedState.skipped] ?? 0,
      ms: json['ms'] as int? ?? 0,
      counts: counts,
      because: {
        for (var entry in (json['because'] as Map? ?? const {}).entries)
          '${entry.key}': entry.value as int? ?? 0,
      },
      note: json['note'] as String?,
    );
  }
}

/// One row worth attention, with the half it came from.
///
/// A finding is a row that is neither `same` nor `skipped`. The whole row
/// travels with it rather than a summary of it: whoever is acting on a finding
/// wants its channels and its frames next, and having to go back to the two
/// lists to find them again is the step that makes a script re-implement the
/// ranking.
class ComparedFinding {
  const ComparedFinding({
    required this.id,
    required this.half,
    required this.state,
    this.note,
    this.preview,
    this.scenario,
  });

  /// The entry id, or the scenario id.
  final String id;

  final ComparedHalfKind half;
  final ComparedState state;

  /// Why it is in the state it is, when the state alone does not say.
  final String? note;

  /// The previews row, when [half] is [ComparedHalfKind.previews].
  final ComparedItem? preview;

  /// The whole flow, when [half] is [ComparedHalfKind.scenarios] — its
  /// steps, its branches and its frames.
  final ScenarioComparison? scenario;
}

/// Whether [state] is worth a reader's attention.
bool isComparedFinding(ComparedState state) =>
    state != ComparedState.same && state != ComparedState.skipped;

/// Every row worth attention, worst first, both halves merged.
///
/// One ranking, however many surfaces ask for it. `ComparedState` is declared
/// worst-first, so ranking is a sort — and doing it here rather than at each
/// surface is what stops the CLI, the MCP action and a consumer's script from
/// each having their own idea of what counts and in what order.
List<ComparedFinding> rankComparedFindings({
  List<ComparedItem> previews = const [],
  List<ScenarioComparison> scenarios = const [],
}) =>
    <ComparedFinding>[
      for (var item in previews)
        if (isComparedFinding(item.state))
          ComparedFinding(
            id: item.id,
            half: ComparedHalfKind.previews,
            state: item.state,
            note: item.note,
            preview: item,
          ),
      for (var scenario in scenarios)
        if (isComparedFinding(scenario.state))
          ComparedFinding(
            id: scenario.scenario,
            half: ComparedHalfKind.scenarios,
            state: scenario.state,
            scenario: scenario,
          ),
    ]..sort(
      (a, b) => a.state.index == b.state.index
          ? a.id.compareTo(b.id)
          : a.state.index.compareTo(b.state.index),
    );

/// A whole `index.json`, read back.
///
/// Parses either file both writers produce, and the object `fw compare --json`
/// prints, because the *verdict* is identical in all three — only the frames
/// differ, and [frames] says how. See `ComparisonReport` for opening them.
class ComparisonIndex {
  const ComparisonIndex({
    this.version = comparisonReportVersion,
    required this.base,
    required this.against,
    required this.previewItems,
    required this.scenarios,
    this.head,
    this.ms = 0,
    this.counts = const {},
    this.frames = ComparisonFrames.local,
    this.previewsHalf = const ComparedHalf(),
    this.scenariosHalf,
    this.export,
    this.report,
  });

  final int version;

  /// The base sha, as the artifact records it.
  final String base;

  /// What the header says the comparison is against — the ref's name where the
  /// export wrote one, the abbreviated sha where it did not.
  final String against;

  /// The worktree the comparison ran in. Absent from an export, which is read
  /// somewhere else by definition.
  final String? head;

  /// Both halves together.
  final int ms;

  /// Every row either half produced, by state — the header a reader wants
  /// first. One preview that broke and one scenario that broke is two broken
  /// things; which half they came from is the second question.
  final Map<ComparedState, int> counts;

  /// Whether the frames this file names can be opened from beside it.
  final ComparisonFrames frames;

  final ComparedHalf previewsHalf;

  /// Absent when the project declares no scenarios at all. A half that tried
  /// and could not is present, with a [ComparedHalf.note].
  final ComparedHalf? scenariosHalf;

  final List<ComparedItem> previewItems;
  final List<ScenarioComparison> scenarios;

  /// The exported page's directory, when `fw compare --json` named one.
  ///
  /// Only ever on stdout — a file cannot say where a directory that contains
  /// it is. It is the bridge a script wants: parse the verdict from the pipe,
  /// then open the frames from here.
  final String? export;

  /// The pull-request report's directory, when `--json` named one.
  final String? report;

  /// Why the scenario half has nothing to say, when it has nothing to say.
  String? get scenariosNote => scenariosHalf?.note;

  /// Throws [FormatException] on a version this reader does not know: the
  /// alternative is handing back an object decoded by guesswork.
  static ComparisonIndex fromJson(Map<String, Object?> json) {
    var version = json['version'] as int? ?? 1;
    if (version > comparisonReportVersion) {
      throw FormatException(
        'This comparison is version $version and this is a reader for '
        '$comparisonReportVersion. Upgrade the flutterware dependency of '
        'whatever is reading it.',
      );
    }
    var base = json['base'] as String? ?? '';
    var previews = json['previews'] as Map<String, Object?>? ?? const {};
    var scenarios = json['scenarios'] as Map<String, Object?>?;
    return ComparisonIndex(
      version: version,
      base: base,
      against:
          json['against'] as String? ??
          (base.length > 8 ? base.substring(0, 8) : base),
      head: json['head'] as String?,
      ms: json['ms'] as int? ?? 0,
      counts: _counts(json['counts']),
      // Absent means `local`: that is what every file written before this key
      // existed is, and an export is the thing that has to say so.
      frames: json['frames'] == 'relative'
          ? ComparisonFrames.relative
          : ComparisonFrames.local,
      previewsHalf: ComparedHalf.fromJson(previews),
      scenariosHalf: scenarios == null
          ? null
          : ComparedHalf.fromJson(scenarios),
      previewItems: [
        for (var item in previews['items'] as List? ?? const [])
          ComparedItem.fromJson((item as Map).cast<String, Object?>()),
      ],
      scenarios: [
        for (var scenario in scenarios?['items'] as List? ?? const [])
          ScenarioComparison.fromJson(
            (scenario as Map).cast<String, Object?>(),
          ),
      ],
      export: (json['export'] as Map?)?['output'] as String?,
      report: (json['report'] as Map?)?['comment'] as String?,
    );
  }

  /// Every row worth attention, worst first, both halves merged.
  List<ComparedFinding> get findings =>
      rankComparedFindings(previews: previewItems, scenarios: scenarios);

  /// True when nothing either half looked at came out worse than `same` — the
  /// gate, in one word.
  ///
  /// A scan rather than `findings.isEmpty`: this answers a boolean, and
  /// building a ranked list of rows to throw it away is the wrong price.
  bool get ok =>
      !previewItems.any((item) => isComparedFinding(item.state)) &&
      !scenarios.any((scenario) => isComparedFinding(scenario.state));

  /// Findings across both halves, worst first — the header's chips.
  ///
  /// Counted rather than built, for the same reason [ok] is scanned: the
  /// exported page reads this from inside a `build`, and [findings] allocates
  /// a row per finding and sorts them. A number does not need either.
  Map<ComparedState, int> get findingCounts {
    var counts = <ComparedState, int>{};
    for (var state in [
      for (var item in previewItems) item.state,
      for (var scenario in scenarios) scenario.state,
    ]) {
      if (isComparedFinding(state)) {
        counts[state] = (counts[state] ?? 0) + 1;
      }
    }
    return Map.fromEntries(
      counts.entries.toList()
        ..sort((a, b) => a.key.index.compareTo(b.key.index)),
    );
  }
}

Map<ComparedState, int> _counts(Object? json) {
  if (json is! Map) return const {};
  var byName = ComparedState.values.asNameMap();
  return {
    for (var entry in json.entries)
      ?byName['${entry.key}']: entry.value as int? ?? 0,
  };
}
