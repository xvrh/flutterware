/// Subsequence matching, shared so every surface ranks alike.
///
/// It lives in the pure package rather than in the GUI because `fw search` and
/// MCP have to order results the same way the palette does. A ranking that only
/// the GUI knows is a ranking the other two get wrong, and "the same query
/// returns the same list" is not a property you can bolt on afterwards.
library;

/// A successful match: a [score] (higher is better) and the character indexes
/// in the target that the query matched, for highlighting.
class FuzzyMatch {
  const FuzzyMatch(this.score, this.matched);

  final int score;
  final List<int> matched;
}

bool _boundary(String ch) =>
    ch == ' ' || ch == '-' || ch == '_' || ch == '/' || ch == '.' || ch == '#';

/// Case-insensitive subsequence match of [query] against [text]. Null when not
/// every query character is found in order.
///
/// The score rewards consecutive runs, word-boundary starts and early matches,
/// so `dash` ranks "Dashboard" above "Does not compile" — both contain the
/// letters, only one starts with them. `#` counts as a boundary because entry
/// ids are `file.dart#symbol` and the symbol is what a human is typing.
///
/// An empty query matches everything with a neutral score; callers that want an
/// empty query to yield nothing check for it themselves, since "show me all"
/// and "show me nothing" are both legitimate answers depending on the surface.
///
/// It is greedy, and takes the first subsequence rather than the best one.
/// In `a.dart#team` a query of `t` lands in `dart` and never reaches the symbol,
/// so the boundary bonus it would have earned there is lost. Finding the best
/// placement means backtracking over every candidate — worth doing when ranking
/// quality is the complaint, and not before, since it is the difference between
/// one pass and a search.
FuzzyMatch? fuzzyMatch(String query, String text) {
  if (query.isEmpty) return const FuzzyMatch(0, []);
  var q = query.toLowerCase();
  var t = text.toLowerCase();

  var matched = <int>[];
  var qi = 0;
  var score = 0;
  var prev = -2;
  for (var i = 0; i < t.length && qi < q.length; i++) {
    if (t[i] != q[qi]) continue;
    var s = 1;
    if (i == prev + 1) s += 6;
    if (i == 0 || _boundary(t[i - 1])) s += 10;
    score += s;
    matched.add(i);
    prev = i;
    qi++;
  }
  if (qi < q.length) return null;

  score += (20 - matched.first).clamp(0, 20);
  if (t.startsWith(q)) score += 15;
  return FuzzyMatch(score, matched);
}
