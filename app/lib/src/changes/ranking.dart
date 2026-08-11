/// **"What should I look at first?"** — the feature, not a garnish.
///
/// Three tiers, and every one of them is a *hint*: the drawer is one click from
/// open, the *All* tab holds every path either way, the header always reports
/// the true file count, and nothing here can make a file disappear. A ranking that can lose a file is a ranking nobody
/// can trust, and this screen exists to be trusted about a worktree you were
/// not watching.
///
/// Every verdict carries **the rule that produced it**, spelled the way the
/// user wrote it. A badge you cannot trace back to a line of config is magic,
/// and magic is what people learn to ignore.
///
/// Pure Dart — `fw changes` ranks identically.
library;

import 'package:flutterware/plugins.dart';

import 'diff_shape.dart';
import 'patch_index.dart';
import 'path_glob.dart';

/// How much of your attention a file is asking for.
enum RankTier {
  /// Pinned into the index's *Important* tab.
  attention,

  /// The ordinary case, and the one no rule fired for.
  ordinary,

  /// Collapsed into the noise drawer.
  noise,
}

/// Who said so. Ordered by how specific the claim is, which is also the
/// precedence order — see [rankChanges].
enum RankSource {
  /// `ChangesConfig` in this project's `tool/flutterware.dart`.
  project,

  /// A `.gitattributes` in this repository.
  gitAttributes,

  /// Flutterware's own defaults, which most projects will never change.
  builtIn,

  /// Read off the change itself: a reformat, an import shuffle.
  derived,
}

/// One file's verdict.
class RankedFile {
  const RankedFile({
    required this.file,
    required this.tier,
    this.rule,
    this.source,
  });

  final FileChange file;
  final RankTier tier;

  /// The pattern or attribute that fired, exactly as written. Null when
  /// nothing fired, which is what [RankTier.ordinary] normally means.
  final String? rule;

  final RankSource? source;

  /// One phrase, for a row that has room for one phrase.
  String? get reason => switch ((source, rule)) {
    (null, _) || (_, null) => null,
    (RankSource.project, var it?) => 'matches $it',
    (RankSource.gitAttributes, var it?) => '$it in .gitattributes',
    (RankSource.builtIn, var it?) => 'built-in: $it',
    (RankSource.derived, var it?) => it,
  };
}

/// Every file, sorted into tiers.
class Ranking {
  Ranking(this.files);

  /// Every ranked file, in the order [rankChanges] produced.
  final List<RankedFile> files;

  static final empty = Ranking(const []);

  List<RankedFile> get attention => _tier(RankTier.attention);
  List<RankedFile> get ordinary => _tier(RankTier.ordinary);
  List<RankedFile> get noise => _tier(RankTier.noise);

  List<RankedFile> _tier(RankTier tier) => [
    for (var ranked in files)
      if (ranked.tier == tier) ranked,
  ];

  /// The verdict for one path, for a caller holding a [FileChange] and no
  /// index into this list.
  RankedFile? forPath(String path) => _byPath[path];

  late final Map<String, RankedFile> _byPath = {
    for (var ranked in files) ranked.file.path: ranked,
  };

  Map<String, Object?> toJson() => {
    'attention': [
      for (var it in attention) {'path': it.file.path, 'reason': ?it.reason},
    ],
    'noise': [
      for (var it in noise) {'path': it.file.path, 'reason': ?it.reason},
    ],
  };
}

/// **There is no built-in attention list, and there must not be one.**
///
/// There was: `**/migrations/**`, `openapi.yaml`, `pubspec.yaml`,
/// `.github/workflows/**`. Every one of those is a guess about somebody else's
/// project. flutterware does not know whether a repository has migrations, and
/// putting a file under a heading that says **look here first** is a claim only
/// the person reading it can make.
///
/// The asymmetry with [builtInNoise] below is the whole argument, and it holds
/// in both directions:
///
/// - Noise defaults are facts about the **toolchain flutterware is for**.
///   `*.g.dart` is build_runner's output, `pubspec.lock` is pub's, `build/` is
///   Flutter's. They are not opinions about a domain.
/// - Getting noise wrong is **cheap and reversible**: a demoted file is still
///   listed, one lens away. Getting attention wrong is **loud** — it puts
///   something at the top of the screen and asserts it matters.
///
/// So attention is the project's to declare, in `tool/flutterware.dart`, and
/// nowhere else. When a project declares none, the *Important* tab is empty,
/// and it says there how to write one.
const builtInNoise = [
  'pubspec.lock',
  'package-lock.json',
  'yarn.lock',
  'Podfile.lock',
  '*.g.dart',
  '*.freezed.dart',
  '*.gr.dart',
  // Not a build_runner convention — a hand-rolled one, and common enough that
  // flutterware's own `action_shapes.generated.dart` led a 228-file list until
  // this line existed. Found by running the ranking over every checkout on
  // this machine rather than by reasoning about suffixes.
  '*.generated.dart',
  'build/',
  '**/__snapshots__/**',
  '**/*.golden',
];

/// Attributes that mean "this is not yours to read", and what to call each one
/// when a row explains itself.
///
/// **`.gitattributes` comes before flutterware's own defaults** because it is
/// an explicit statement about *this* repository that GitHub already honours,
/// and many repositories already have one. Competing with a standard that works
/// would be indefensible, and it costs a user nothing to have configured
/// already.
const _attributeReasons = {
  'linguist-generated': 'generated',
  'linguist-vendored': 'vendored',
  // `-diff` is git's own way of saying "do not try to read this as text".
  'diff': 'not diffable',
};

/// Sorts [files] into tiers.
///
/// **Precedence is first-match-wins, most specific first**, and the order is
/// the whole design:
///
/// 1. the project's `attention`
/// 2. the project's `noise`
/// 3. `.gitattributes`
/// 4. the built-in `attention`
/// 5. the built-in `noise`
/// 6. what the change itself is — a reformat, an import shuffle
///
/// Project before repository before tool is the ordinary specificity ladder.
/// The derived rules come **last** deliberately: a pinned file that was only
/// reformatted is still pinned, because demoting something the user explicitly
/// asked to see is the one direction a hint must never take.
///
/// [attributes] maps a path to the attribute names git reported set for it —
/// `attributesFrom` decodes it. [patch] is what the derived rules read; pass
/// null to skip them.
Ranking rankChanges(
  List<FileChange> files, {
  ChangesConfig? config,
  Map<String, Set<String>> attributes = const {},
  PatchIndex? patch,
}) {
  var projectAttention = PathGlobSet(config?.attention ?? const []);
  var projectNoise = PathGlobSet(config?.noise ?? const []);
  var defaultNoise = PathGlobSet(builtInNoise);

  RankedFile rank(FileChange file) {
    var path = file.path;

    if (projectAttention.firstMatch(path) case var rule?) {
      return RankedFile(
        file: file,
        tier: RankTier.attention,
        rule: rule,
        source: RankSource.project,
      );
    }
    if (projectNoise.firstMatch(path) case var rule?) {
      return RankedFile(
        file: file,
        tier: RankTier.noise,
        rule: rule,
        source: RankSource.project,
      );
    }
    var set = attributes[path];
    if (set != null) {
      // Iterating our own table rather than git's answer, so which attribute a
      // row names does not depend on the order git happened to print them in.
      for (var entry in _attributeReasons.entries) {
        if (set.contains(entry.key)) {
          return RankedFile(
            file: file,
            tier: RankTier.noise,
            rule: entry.value,
            source: RankSource.gitAttributes,
          );
        }
      }
    }
    // No built-in attention step here, deliberately — see [builtInNoise].
    // Nothing is pinned that the project did not ask for.
    if (defaultNoise.firstMatch(path) case var rule?) {
      return RankedFile(
        file: file,
        tier: RankTier.noise,
        rule: rule,
        source: RankSource.builtIn,
      );
    }
    if (patch != null) {
      var derived = switch (shapeOf(patch, file)) {
        DiffShape.whitespaceOnly => 'only whitespace changed',
        DiffShape.importsOnly => 'only imports changed',
        DiffShape.none => null,
      };
      if (derived != null) {
        return RankedFile(
          file: file,
          tier: RankTier.noise,
          rule: derived,
          source: RankSource.derived,
        );
      }
    }
    return RankedFile(file: file, tier: RankTier.ordinary);
  }

  return Ranking([for (var file in files) rank(file)]);
}

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
String? attentionForUntracked(String path, {ChangesConfig? config}) {
  if (path.endsWith('/')) return null;
  if (PathGlobSet(config?.attention ?? const []).firstMatch(path)
      case var rule?) {
    return 'matches $rule';
  }
  return null;
}

/// Decodes `git check-attr --stdin -a -z`, whose records are
/// `<path>\0<attribute>\0<value>\0` and which **says nothing at all about a
/// path with no attributes** — so the absence of a path here is the normal
/// case, not a failure.
///
/// Only attributes that are actually *set* count. git spells the three states
/// `set`, `unset` and `unspecified`, plus an arbitrary string for a valued
/// attribute; `linguist-generated=true` arrives as the string `true`. The one
/// inversion is `diff`, where **`unset` is the interesting state**: `-diff`
/// means "do not read this as text".
Map<String, Set<String>> attributesFrom(List<String> records) {
  var byPath = <String, Set<String>>{};
  for (var i = 0; i + 2 < records.length; i += 3) {
    var path = records[i];
    var attribute = records[i + 1];
    var value = records[i + 2];
    var isOn = attribute == 'diff'
        ? value == 'unset'
        : value != 'unset' && value != 'unspecified' && value != 'false';
    if (isOn) (byPath[path] ??= <String>{}).add(attribute);
  }
  return byPath;
}
