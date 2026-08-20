import 'channels.dart';
import 'scenario_comparison.dart';

/// What one half concluded the last time it ran, kept so the panel can show
/// it again without running anything.

/// One half's finished run, as the panel restores it on the next visit.
///
/// **The idle state is never blank** — that is the whole reason this exists.
/// A comparison used to evaporate with the panel: every visit started from
/// zero, so opening the tab meant either running the machinery again or
/// looking at nothing. Persisting the last answer makes glancing free, and
/// the explicit Compare button an *informed* choice rather than the only way
/// to see anything at all.
///
/// A reader of a file, like `ComparisonIndex`: it holds what was written and
/// recomputes nothing. The rows round-trip through the same JSON the artifact
/// and the web viewer already use; the pictures stay in the content-addressed
/// shot cache the rows point into, so restoring costs one small file read.
class LastComparison {
  const LastComparison({
    required this.at,
    required this.baseSha,
    required this.against,
    required this.elapsed,
    this.headCommit,
    this.items,
    this.rendered,
    this.scenarios,
    this.ran,
    this.note,
  });

  /// When the run finished.
  final DateTime at;

  final String baseSha;

  /// The ref the base was resolved from — what the receipt names.
  final String against;

  /// Where HEAD sat when the run finished. What lets a later visit say "the
  /// worktree has moved since" without hashing anything. Null when the writer
  /// could not tell.
  final String? headCommit;

  final Duration elapsed;

  /// The previews half's rows. Null on a scenarios record.
  final List<ComparedItem>? items;

  /// How many renders the previews half actually paid for.
  final int? rendered;

  /// The scenario half's rows. Null on a previews record.
  final List<ScenarioComparison>? scenarios;

  /// How many scenarios were replayed on both sides.
  final int? ran;

  /// Why the scenario half had nothing to say, when it had nothing to say.
  final String? note;

  Map<String, Object?> toJson() => {
    'version': 1,
    'at': at.toIso8601String(),
    'baseSha': baseSha,
    'against': against,
    'headCommit': ?headCommit,
    'ms': elapsed.inMilliseconds,
    'rendered': ?rendered,
    'ran': ?ran,
    'note': ?note,
    'items': ?(items == null ? null : [for (var item in items!) item.toJson()]),
    'scenarios': ?(scenarios == null
        ? null
        : [for (var scenario in scenarios!) scenario.toJson()]),
  };

  static LastComparison? fromJson(Map<String, Object?> json) {
    var at = DateTime.tryParse(json['at'] as String? ?? '');
    var baseSha = json['baseSha'] as String?;
    if (at == null || baseSha == null) return null;
    return LastComparison(
      at: at,
      baseSha: baseSha,
      against: json['against'] as String? ?? baseSha,
      headCommit: json['headCommit'] as String?,
      elapsed: Duration(milliseconds: json['ms'] as int? ?? 0),
      rendered: json['rendered'] as int?,
      ran: json['ran'] as int?,
      note: json['note'] as String?,
      items: switch (json['items']) {
        List items => [
          for (var item in items)
            ComparedItem.fromJson((item as Map).cast<String, Object?>()),
        ],
        _ => null,
      },
      scenarios: switch (json['scenarios']) {
        List scenarios => [
          for (var scenario in scenarios)
            ScenarioComparison.fromJson(
              (scenario as Map).cast<String, Object?>(),
            ),
        ],
        _ => null,
      },
    );
  }
}
