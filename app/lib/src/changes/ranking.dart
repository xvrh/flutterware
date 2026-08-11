/// **"What should I look at first?"** — the feature, not a garnish.
///
/// Two tiers, and the pinned one is a *hint*: the *All* tab holds every path
/// either way, the header always reports the true file count, and nothing here
/// can make a file disappear. A ranking that can lose a file is a ranking
/// nobody can trust, and this screen exists to be trusted about a worktree you
/// were not watching.
///
/// Every verdict carries **the rule that produced it**, spelled the way the
/// user wrote it. A badge you cannot trace back to a line of config is magic,
/// and magic is what people learn to ignore.
///
/// **There was a third tier**, `noise`: generated code and lockfiles demoted
/// behind a *low-signal* lens, by project globs, by `.gitattributes`, and by
/// what the diff turned out to be. It is gone. Every one of those rules was
/// machinery for hiding files on a screen whose whole claim is that it hides
/// nothing, and the payment for it — a lens, a drawer, a tally, a batched
/// `check-attr`, a second pass over the patch bytes — bought a shorter list
/// nobody had asked to be shorter.
///
/// Pure Dart — `fw changes` ranks identically.
library;

import 'package:flutterware/plugins.dart';

import 'patch_index.dart';
import 'path_glob.dart';

/// How much of your attention a file is asking for.
enum RankTier {
  /// Pinned into the index's *Important* tab.
  attention,

  /// The ordinary case, and the one no rule fired for.
  ordinary,
}

/// One file's verdict.
class RankedFile {
  const RankedFile({required this.file, required this.tier, this.rule});

  final FileChange file;
  final RankTier tier;

  /// The pattern that pinned this file, exactly as written. Null when nothing
  /// fired, which is what [RankTier.ordinary] means.
  final String? rule;

  /// One phrase, for a row that has room for one phrase.
  String? get reason => rule == null ? null : 'matches $rule';
}

/// Every file, sorted into tiers.
class Ranking {
  Ranking(this.files);

  /// Every ranked file, in the order [rankChanges] produced.
  final List<RankedFile> files;

  static final empty = Ranking(const []);

  /// The verdict for one path, for a caller holding a [FileChange] and no
  /// index into this list.
  ///
  /// **The only way in.** Per-tier getters lived here too and had no reader
  /// but their own test: every caller goes through [ChangeSet.ordered], which
  /// filters the same list *and* sorts it by weight, so a second unsorted
  /// filter beside it was a way to draw the same list in the wrong order.
  RankedFile? forPath(String path) => _byPath[path];

  late final Map<String, RankedFile> _byPath = {
    for (var ranked in files) ranked.file.path: ranked,
  };
}

/// Sorts [files] into tiers.
///
/// **There is no built-in attention list, and there must not be one.**
///
/// There was: `**/migrations/**`, `openapi.yaml`, `pubspec.yaml`,
/// `.github/workflows/**`. Every one of those is a guess about somebody else's
/// project. flutterware does not know whether a repository has migrations, and
/// putting a file under a heading that says **look here first** is a claim only
/// the person reading it can make. Getting it wrong is **loud** — it puts
/// something at the top of the screen and asserts it matters.
///
/// So attention is the project's to declare, in `tool/flutterware.dart`, and
/// nowhere else. When a project declares none, the *Important* tab is empty,
/// and it says there how to write one.
Ranking rankChanges(List<FileChange> files, {ChangesConfig? config}) {
  var attention = attentionGlobs(config);

  RankedFile rank(FileChange file) {
    if (attention.firstMatch(file.path) case var rule?) {
      return RankedFile(file: file, tier: RankTier.attention, rule: rule);
    }
    return RankedFile(file: file, tier: RankTier.ordinary);
  }

  return Ranking([for (var file in files) rank(file)]);
}

/// The project's `attention:` globs, compiled.
///
/// **Compiled once and carried**, because compiling them is now the whole cost
/// of ranking: each pattern is up to three `Glob` parses (see [PathGlobSet]),
/// and this used to be rebuilt per untracked path, on a screen that re-probes
/// every couple of seconds.
PathGlobSet attentionGlobs(ChangesConfig? config) =>
    PathGlobSet(config?.attention ?? const []);

/// Whether an **untracked** path is one the project asked to see first, and
/// which rule said so.
///
/// A separate door from [rankChanges] because an untracked entry is a
/// different kind of thing: it has no diff, no counts and no hunks, so it
/// cannot be a [RankedFile]. What it can be is *pinned* — and it has to be,
/// because the motivating case is an agent that just wrote a new migration and
/// has not staged it. A pin that only works once something is `git add`-ed
/// would miss the exact moment it exists for.
///
/// **Never a directory.** git reports the topmost wholly-untracked directory
/// and does not descend, and neither does this: matching `**/migrations/**`
/// against `build/` would mean walking it, which is the walk the whole
/// untracked design avoids.
String? attentionForUntracked(String path, PathGlobSet attention) {
  if (path.endsWith('/')) return null;
  if (attention.firstMatch(path) case var rule?) return 'matches $rule';
  return null;
}
