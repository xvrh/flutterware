// How the scene index says what it found, in the words a person would use.
//
// The listing used to describe a folder as `1 library · 3 widgets · 3
// exports` — three counts of three internal nouns, one of which ("exports")
// names the direction a value travels rather than what it is. The counts were
// true and said nothing: what you want to know about a folder is how much is
// in it, which palette its scenes are drawn from, and how much of the app they
// can reach.
//
// Pure string composition, kept out of the panel so it can be read at a glance
// and tested without one.
import '../args_generate.dart';
import '../discovery.dart';

/// `8 scenes · reads brandTokens · 3 widgets and 3 values from the app`.
///
/// Each clause is dropped when it has nothing to say, so a fresh folder reads
/// `No scenes yet` and nothing more.
String groupSummary(SceneGroupEntry group, GroupVocabulary vocabulary) => [
  group.scenes.isEmpty
      ? 'No scenes yet'
      : countOf(group.scenes.length, 'scene'),
  if (vocabulary.libraries.isNotEmpty)
    'reads ${vocabulary.libraries.map((l) => l.entry.symbol).join(', ')}',
  if (appReach(vocabulary) case var reach when reach.isNotEmpty)
    '$reach from the app',
].join(' · ');

/// The two halves of what a group's declaration lends its scenes: the widgets
/// they may place and the values they may name. Joined, because they come from
/// one file and answer one question — how much of the app is in reach.
String appReach(GroupVocabulary vocabulary) => [
  if (vocabulary.widgets.isNotEmpty)
    countOf(vocabulary.widgets.length, 'widget'),
  if (vocabulary.exports.isNotEmpty)
    countOf(vocabulary.exports.length, 'value'),
].join(' and ');

/// Who reads a library, or that nobody does yet.
String readBy(Iterable<String> groups) =>
    groups.isEmpty ? 'read by nothing yet' : 'read by ${groups.join(', ')}';

/// `1 scene` / `8 scenes`. Every noun the listing counts takes a plain `s`.
String countOf(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// The gap between a folder and its declaration, said as the thing that is
/// wrong rather than as two lists.
///
/// Both halves are things a person did — a library dropped into the folder,
/// or one moved out of it — so the sentence names the file that has fallen
/// behind and what it is missing, and leaves the fixing to the button
/// beside it.
String driftWords(SceneLibraryDrift drift, String declarationFileName) {
  var missing = drift.missing.map((l) => l.symbol).toList();
  var stray = drift.stray.map((l) => l.symbol).toList();
  var unlisted = missing.length == 1
      ? '${missing.single} sits in this folder but $declarationFileName does '
            'not list it'
      : '${missing.join(', ')} sit in this folder but $declarationFileName '
            'does not list them';
  var moved = stray.length == 1
      ? '$declarationFileName lists ${stray.single}, which no longer sits '
            'above this folder'
      : '$declarationFileName lists ${stray.join(', ')}, which no longer sit '
            'above this folder';
  return [
    if (missing.isNotEmpty) unlisted,
    if (stray.isNotEmpty) moved,
  ].join(' · ');
}
