import 'address.dart';
import 'child.dart';
import 'fuzzy.dart';
import 'report.dart';
import 'view.dart';

/// What a hit *is* — the chip on a result row.
///
/// A kind, not a sentence, so the GUI can pick an icon and `fw search` can
/// print a column without either inventing its own vocabulary.
///
/// Short on purpose. These are the three things the shell can actually put on
/// screen; see [searchReport] for why nothing else is offered.
enum SearchReason {
  plugin('Plugin'),
  package('Package'),
  item('Item');

  const SearchReason(this.label);

  /// What a human reads on the chip.
  final String label;
}

/// One result: where it is, why it matched, and how well.
///
/// [address] is always set, so a hit is portable — the GUI opens it, `fw`
/// prints it, MCP returns it, and none of them needs a callback the others
/// cannot serialise. That is the whole reason this is data and not a
/// `VoidCallback`.
class SearchHit {
  const SearchHit({
    required this.address,
    required this.title,
    required this.group,
    required this.reason,
    required this.score,
    this.subtitle,
    this.matched = const [],
  });

  /// Where the hit is. Always somewhere real: a result that named no
  /// destination was never offered — see [searchReport].
  final Address address;

  final String title;
  final String? subtitle;

  /// The section this belongs under. The plugin's label, so results cluster
  /// the way the sidebar does.
  final String group;

  final SearchReason reason;

  /// Ranking within a group. Higher is better; comparable only against hits
  /// from the same query.
  final int score;

  /// Character indexes in [title] the query matched, for highlighting. Empty
  /// when the match came from [subtitle] instead.
  final List<int> matched;

  @override
  String toString() => '$title (${reason.label}, $score) $address';
}

/// How much each kind is worth before its fuzzy score is added.
///
/// A plugin outranks a stray field that happens to contain the same letters,
/// because "pre" should find Previews rather than a table cell. The
/// weights are small on purpose: a genuinely better match still wins, so
/// typing `dash` finds the Dashboard entry rather than the plugin above it.
const _weights = {SearchReason.plugin: 30, SearchReason.package: 20};

/// Everywhere in [report] you could go that matches [query], without asking the
/// plugin for anything.
///
/// This is the baseline every plugin gets for free. `PluginReport` is already
/// all data, so walking it means a plugin is searchable the day it reports,
/// with no search code of its own.
///
/// Only destinations. A result offers to take you somewhere, so a row that
/// names no destination is not a result. That rules out three kinds the report
/// also carries:
///
/// - **Actions.** A verb rather than a place. "Screenshot" in a list of places is a
///   category error, and running one off a fuzzy match is worse — some are
///   declared `danger`. Commands are a different surface (a `>` mode, the way
///   an editor separates go-to-file from run-command), not this one.
/// - **Free text and fields.** A diagnostic or a label/value pair is output.
///   Matching it strands you on the plugin, which is the wrong page.
/// - **Rows with no address.** These used to be listed as "found, but not
///   followed". In use that reads as a broken result: you searched a specific
///   thing, something opened, and it was not that thing.
///
/// So a plugin is as findable as it is addressable. The way in is to give rows
/// an address, not to be listed without one.
///
/// [worktree] is stamped into every address so hits stay distinguishable if a
/// caller ever merges several.
List<SearchHit> searchReport(
  PluginReport report,
  String query, {

  /// Which worktree the report came from. Required, because a hit exists to be
  /// gone to and a place cannot be reached without one — the same reason
  /// `2de5004` stopped offering results that named no destination.
  required String worktree,
}) {
  var trimmed = query.trim();
  if (trimmed.isEmpty) return const [];

  var hits = <SearchHit>[];
  var plugin = Address(worktree: worktree, plugin: report.id);

  void add({
    required String title,
    required Address address,
    required SearchReason reason,
    String? subtitle,
  }) {
    var match = fuzzyMatch(trimmed, title);
    var matched = match?.matched ?? const <int>[];
    var score = match?.score;
    if (score == null && subtitle != null) {
      // **Substring here, not subsequence.** A detail is an entry id, a version
      // or a sentence of prose, and a long string contains almost any short
      // subsequence — matching `dash` against "…its id and address…" is how a
      // fuzzy palette fills with noise. A name is short and the user is
      // recalling it, so a subsequence is right there and wrong here.
      var index = subtitle.toLowerCase().indexOf(trimmed.toLowerCase());
      if (index >= 0) score = 10 + (20 - index).clamp(0, 20);
    }
    if (score == null) return;

    hits.add(
      SearchHit(
        address: address,
        title: title,
        subtitle: subtitle,
        group: report.label,
        reason: reason,
        score: score + (_weights[reason] ?? 0),
        matched: matched,
      ),
    );
  }

  add(title: report.label, address: plugin, reason: SearchReason.plugin);

  for (var child in report.children) {
    add(
      title: child.label,
      subtitle: child.status.isEmpty ? null : child.status.message,
      address: _childAddress(plugin, child),
      reason: SearchReason.package,
    );
  }

  _walk(report.view.nodes, plugin, add);

  hits.sort((a, b) => b.score - a.score);
  return _dedupe(hits);
}

/// Drops hits a user could not tell apart.
///
/// A projection repeats itself honestly — the same entry can appear under more
/// than one heading — but two rows going to the same place and reading the same
/// way are one result as far as a list is concerned.
///
/// Keyed on what the row displays plus where it goes, so two entries that
/// merely share a name stay separate.
List<SearchHit> _dedupe(List<SearchHit> hits) {
  var seen = <String>{};
  return [
    for (var hit in hits)
      if (seen.add('${hit.address} ${hit.title} ${hit.subtitle}')) hit,
  ];
}

Address _childAddress(Address plugin, PluginChild child) =>
    plugin.child(child.id);

/// Recurses the projection looking for rows that say where they are.
///
/// Sections are walked through rather than matched: a section title is a
/// heading over content, and selecting a heading has no meaning. Text, fields
/// and table rows are skipped entirely — none of them carries an address, and a
/// table has nowhere to put one. Only [ViewItem] can, and only those that did
/// are offered.
void _walk(
  List<ViewNode> nodes,
  Address plugin,
  void Function({
    required String title,
    required Address address,
    required SearchReason reason,
    String? subtitle,
  })
  add,
) {
  for (var node in nodes) {
    switch (node) {
      case ViewSection section:
        _walk(section.children, plugin, add);
      case ViewItems items:
        for (var item in items.items) {
          if (item.address case var address?) {
            add(
              title: item.label,
              subtitle: item.detail,
              address: address,
              reason: SearchReason.item,
            );
          }
        }
      case ViewText() || ViewField() || ViewTable():
        break;
    }
  }
}
