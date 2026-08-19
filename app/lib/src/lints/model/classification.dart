import 'package:collection/collection.dart';

import 'options_scan.dart';
import 'rule_catalog.dart';

/// Where one rule stands across the whole repo.
enum LintBucket {
  /// Effectively on in at least one options file.
  enabled,

  /// Explicitly `false` (or severity `ignore`) somewhere, on nowhere.
  dismissed,

  /// Mentioned only in a comment — someone looked, nobody committed.
  mentioned,

  /// In the SDK's rule set for this project, mentioned nowhere. The panel's
  /// whole reason to exist.
  unevaluated,
}

/// One rule of the universe, classified against every options file at once.
class ClassifiedLint {
  final String name;
  final LintBucket bucket;

  /// Catalog metadata. Null only for a configured name the catalog does not
  /// know — a typo, a removed rule, or a catalog that is newer or older than
  /// the config.
  final LintRule? rule;

  /// For [LintBucket.enabled]: the file that turned it on, in the root file's
  /// chain when possible (`package:lints/core.yaml`, `analysis_options.yaml`).
  final String? enabledVia;

  /// For [LintBucket.dismissed]: the comment next to the `false`, when any
  /// mention has one.
  final String? comment;

  /// Repo-relative options files that mention or decide this rule.
  final List<String> files;

  ClassifiedLint({
    required this.name,
    required this.bucket,
    this.rule,
    this.enabledVia,
    this.comment,
    this.files = const [],
  });
}

/// The union view over a [LintOptionsScan] and a [LintCatalog].
///
/// Union semantics keep the hero number honest in a multi-file repo:
/// *unevaluated* means mentioned in **none** of the files — not "off in the
/// file you happen to be looking at".
class LintsClassification {
  final List<ClassifiedLint> rules;

  /// Configured names the catalog does not know (typos, removed rules). They
  /// ride separately rather than polluting the buckets.
  final List<String> unknownNames;

  /// False when no catalog could be loaded — the local buckets still stand,
  /// but nothing can be called unevaluated without a universe to compare to.
  final bool hasCatalog;

  /// How many rules the catalog offers this SDK (stable + experimental).
  final int universe;

  LintsClassification({
    required this.rules,
    required this.unknownNames,
    required this.hasCatalog,
    required this.universe,
  });

  Iterable<ClassifiedLint> inBucket(LintBucket bucket) =>
      rules.where((r) => r.bucket == bucket);

  int count(LintBucket bucket) => inBucket(bucket).length;

  static LintsClassification build({
    required LintOptionsScan scan,
    required LintCatalog? catalog,
  }) {
    var enabledVia = <String, String>{};
    var enabledFiles = <String, Set<String>>{};
    var dismissedFiles = <String, Set<String>>{};
    var comments = <String, String>{};
    var commentMentions = <String, Set<String>>{};

    for (var file in scan.files) {
      for (var name in file.enabled) {
        enabledFiles.putIfAbsent(name, () => {}).add(file.path);
        // The root file's chain is the canonical provenance; a nested file
        // repeating the decision adds nothing.
        enabledVia.putIfAbsent(name, () => file.effective[name]!.via);
      }
      for (var entry in file.mentions.entries) {
        if (!entry.value.enabled) {
          dismissedFiles.putIfAbsent(entry.key, () => {}).add(file.path);
          var comment = entry.value.comment;
          if (comment != null) comments.putIfAbsent(entry.key, () => comment);
        }
      }
      for (var entry in file.severityOverrides.entries) {
        if (entry.value == 'ignore') {
          dismissedFiles.putIfAbsent(entry.key, () => {}).add(file.path);
        }
      }
      for (var name in file.commentedOut) {
        commentMentions.putIfAbsent(name, () => {}).add(file.path);
      }
    }

    var known = catalog?.byName ?? const <String, LintRule>{};
    var rules = <ClassifiedLint>[];
    var unknown = <String>[];
    var placed = <String>{};

    // Names that appeared in a `linter: rules:` list somewhere in the chain.
    // Only these can be "unknown rules" worth warning about: the `analyzer:
    // errors:` section legitimately names non-lint diagnostics (unused_import),
    // and those are silently not-a-lint rather than a typo.
    var lintSpelled = <String>{
      for (var file in scan.files) ...[
        ...file.effective.keys,
        ...file.mentions.keys,
      ],
    };

    ClassifiedLint classify(String name, LintBucket bucket) => ClassifiedLint(
      name: name,
      bucket: bucket,
      rule: known[name],
      enabledVia: enabledVia[name],
      comment: comments[name],
      files: {
        ...?enabledFiles[name],
        ...?dismissedFiles[name],
        ...?commentMentions[name],
      }.toList()..sort(),
    );

    for (var name in enabledFiles.keys) {
      placed.add(name);
      if (catalog != null && !known.containsKey(name)) {
        unknown.add(name);
        continue;
      }
      rules.add(classify(name, LintBucket.enabled));
    }
    for (var name in dismissedFiles.keys) {
      if (!placed.add(name)) continue;
      if (catalog != null && !known.containsKey(name)) {
        if (lintSpelled.contains(name)) unknown.add(name);
        continue;
      }
      rules.add(classify(name, LintBucket.dismissed));
    }
    for (var name in commentMentions.keys) {
      if (!placed.add(name)) continue;
      // Comment tokens are heuristic finds — only a name the catalog knows
      // counts as a mention; anything else is prose that looked like one.
      if (!known.containsKey(name)) continue;
      rules.add(classify(name, LintBucket.mentioned));
    }
    if (catalog != null) {
      for (var rule in catalog.active) {
        if (placed.contains(rule.name)) continue;
        rules.add(
          ClassifiedLint(
            name: rule.name,
            bucket: LintBucket.unevaluated,
            rule: rule,
          ),
        );
      }
    }

    unknown.sort();
    return LintsClassification(
      rules: rules,
      unknownNames: unknown,
      hasCatalog: catalog != null,
      universe: catalog?.active.length ?? 0,
    );
  }
}

/// Orders by `sinceDartSdk` descending — the newest rules first, which is the
/// "what appeared since I last looked" order the unevaluated bucket wants.
int compareBySinceDesc(ClassifiedLint a, ClassifiedLint b) {
  var result = _sinceKey(b).compareTo(_sinceKey(a));
  return result != 0 ? result : a.name.compareTo(b.name);
}

_Version _sinceKey(ClassifiedLint lint) {
  var since = lint.rule?.sinceDartSdk ?? '';
  var parts = since.split('-').first.split('.');
  return _Version(
    int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0,
    int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
  );
}

class _Version implements Comparable<_Version> {
  final int major;
  final int minor;

  _Version(this.major, this.minor);

  @override
  int compareTo(_Version other) => major != other.major
      ? major.compareTo(other.major)
      : minor.compareTo(other.minor);
}
