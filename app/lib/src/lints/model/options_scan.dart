import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../utils/list_files.dart';

/// One rule's explicit entry in one `analysis_options.yaml`.
class LintMention {
  final bool enabled;

  /// The comment attached to the entry — trailing on the same line, else the
  /// comment block immediately above with no blank line between. This is a
  /// heuristic: a section header above a group attaches to the group's first
  /// rule, which is usually context and occasionally noise. The panel shows
  /// where it came from, so a misattribution is visible rather than trusted.
  final String? comment;

  /// 1-based, in the file that wrote it.
  final int line;

  LintMention({required this.enabled, this.comment, required this.line});
}

/// What the chain decided about one rule, and which file decided it.
class RuleDecision {
  final bool enabled;

  /// Display name of the deciding file: a repo-relative path, or the
  /// `package:` spelling for an included file from the pub cache.
  final String via;

  RuleDecision({required this.enabled, required this.via});
}

/// One `analysis_options.yaml`, parsed and its `include:` chain resolved.
class LintOptionsFile {
  /// Repo-relative, POSIX separators.
  final String path;

  /// Includes in application order, deepest first — the file itself is not in
  /// the list. Display names, same convention as [RuleDecision.via].
  final List<String> includeChain;

  /// Includes that could not be resolved, with the reason.
  final List<String> includeErrors;

  /// False for a file with no `include:` at all — it severs inheritance, which
  /// is a state worth surfacing: every rule an ancestor enabled is off here.
  final bool hasInclude;

  /// This file's own `linter: rules:` entries.
  final Map<String, LintMention> mentions;

  /// Rule names seen only in comments (`# some_rule: false`, `# - some_rule`):
  /// evidence that someone looked at the rule and left it off.
  final Set<String> commentedOut;

  /// `analyzer: errors:` entries — `ignore` disables a rule as effectively as
  /// `rule: false`, just in a different section.
  final Map<String, String> severityOverrides;

  /// What applies under this file after the whole chain: rule → decision.
  final Map<String, RuleDecision> effective;

  LintOptionsFile({
    required this.path,
    required this.includeChain,
    required this.includeErrors,
    required this.hasInclude,
    required this.mentions,
    required this.commentedOut,
    required this.severityOverrides,
    required this.effective,
  });

  /// Rules this file's effective config enables, `ignore` overrides applied.
  Set<String> get enabled => {
    for (var entry in effective.entries)
      if (entry.value.enabled && severityOverrides[entry.key] != 'ignore')
        entry.key,
  };
}

/// Every `analysis_options.yaml` in the repo, resolved.
class LintOptionsScan {
  final List<LintOptionsFile> files;

  LintOptionsScan(this.files);

  /// The repo-root file, when there is one — the file most classification and
  /// pricing questions are about.
  LintOptionsFile? get root =>
      files.where((f) => f.path == 'analysis_options.yaml').firstOrNull;
}

/// Scans a repository for `analysis_options.yaml` files and resolves each
/// one's `include:` chain.
///
/// Pure parsing — no process, no network — so it fits the `computeAll` budget.
/// `package:` includes need [resolvePackageUri] (built from the project's own
/// `package_config.json`); without it they are reported as unresolvable rather
/// than guessed at.
class LintOptionsScanner {
  final String repoRoot;
  final String? Function(Uri uri)? resolvePackageUri;

  /// Parsed includes from outside the repo (the pub cache), cached across
  /// files: every member chain ends in the same `package:lints` files.
  final _foreign = <String, _ParsedOptions?>{};

  LintOptionsScanner({required this.repoRoot, this.resolvePackageUri});

  LintOptionsScan scan() {
    var found = listFilesInDirectory(repoRoot)
        .where((f) => p.basename(f.path) == 'analysis_options.yaml')
        .map((f) => p.canonicalize(f.path))
        .toList();
    found.sort(
      (a, b) =>
          a.length != b.length ? a.length.compareTo(b.length) : a.compareTo(b),
    );
    return LintOptionsScan([for (var path in found) _resolveFile(path)]);
  }

  LintOptionsFile _resolveFile(String absolutePath) {
    var parsed = _parse(absolutePath);
    var chain = <String>[];
    var errors = <String>[];
    var effective = <String, RuleDecision>{};
    var severities = <String, String>{};
    _apply(
      absolutePath,
      parsed,
      chain: chain,
      errors: errors,
      effective: effective,
      severities: severities,
      visited: {absolutePath},
      isSelf: true,
    );
    return LintOptionsFile(
      path: _display(absolutePath),
      // _apply pushed the file's own display name last; the chain proper is
      // everything before it.
      includeChain: chain.sublist(0, chain.length - 1),
      includeErrors: errors,
      hasInclude: parsed?.includes.isNotEmpty ?? false,
      mentions: parsed?.mentions ?? {},
      commentedOut: parsed?.commentedOut ?? {},
      severityOverrides: parsed?.severityOverrides ?? {},
      effective: effective,
    );
  }

  /// Applies [parsed]'s includes (recursively), then its own rules, into
  /// [effective] — later writes win, which is the analyzer's own semantics.
  void _apply(
    String absolutePath,
    _ParsedOptions? parsed, {
    required List<String> chain,
    required List<String> errors,
    required Map<String, RuleDecision> effective,
    required Map<String, String> severities,
    required Set<String> visited,
    required bool isSelf,
    String? displayOverride,
  }) {
    if (parsed == null) return;
    for (var include in parsed.includes) {
      var resolved = _resolveInclude(include, from: absolutePath);
      if (resolved == null) {
        errors.add(include);
        continue;
      }
      if (!visited.add(resolved)) continue;
      var included = _parseIncluded(resolved);
      if (included == null) {
        errors.add(include);
        continue;
      }
      _apply(
        resolved,
        included,
        chain: chain,
        errors: errors,
        effective: effective,
        severities: severities,
        visited: visited,
        isSelf: false,
        displayOverride: include.startsWith('package:') ? include : null,
      );
    }
    var display = isSelf
        ? _display(absolutePath)
        : displayOverride ?? _display(absolutePath);
    chain.add(display);
    for (var entry in parsed.mentions.entries) {
      effective[entry.key] = RuleDecision(
        enabled: entry.value.enabled,
        via: display,
      );
    }
    severities.addAll(parsed.severityOverrides);
  }

  String? _resolveInclude(String include, {required String from}) {
    if (include.startsWith('package:')) {
      var resolve = resolvePackageUri;
      if (resolve == null) return null;
      Uri uri;
      try {
        uri = Uri.parse(include);
      } catch (e) {
        return null;
      }
      var path = resolve(uri);
      if (path == null || !File(path).existsSync()) return null;
      return p.canonicalize(path);
    }
    var path = p.canonicalize(p.join(p.dirname(from), include));
    if (!File(path).existsSync()) return null;
    return path;
  }

  _ParsedOptions? _parseIncluded(String absolutePath) {
    if (p.isWithin(repoRoot, absolutePath)) return _parse(absolutePath);
    return _foreign.putIfAbsent(absolutePath, () => _parse(absolutePath));
  }

  String _display(String absolutePath) =>
      p.isWithin(repoRoot, absolutePath) || p.equals(repoRoot, absolutePath)
      ? p.posix.joinAll(p.split(p.relative(absolutePath, from: repoRoot)))
      : absolutePath;

  _ParsedOptions? _parse(String absolutePath) {
    String content;
    try {
      content = File(absolutePath).readAsStringSync();
    } catch (e) {
      return null;
    }
    Object? yaml;
    try {
      yaml = loadYaml(content);
    } catch (e) {
      return null;
    }
    if (yaml is! Map) return _ParsedOptions.empty;

    var includes = switch (yaml['include']) {
      String single => [single],
      List list => [for (var entry in list) entry.toString()],
      _ => <String>[],
    };

    var lines = content.split('\n');
    var mentions = <String, LintMention>{};
    var rules = yaml['linter'] is Map ? (yaml['linter'] as Map)['rules'] : null;
    if (rules is List) {
      for (var entry in rules) {
        var name = entry.toString();
        mentions[name] = LintMention(
          enabled: true,
          comment: _commentFor(lines, name),
          line: _lineOf(lines, name),
        );
      }
    } else if (rules is Map) {
      for (var entry in rules.entries) {
        var name = entry.key.toString();
        if (entry.value is! bool) continue;
        mentions[name] = LintMention(
          enabled: entry.value as bool,
          comment: _commentFor(lines, name),
          line: _lineOf(lines, name),
        );
      }
    }

    var severities = <String, String>{};
    var analyzer = yaml['analyzer'];
    if (analyzer is Map && analyzer['errors'] is Map) {
      for (var entry in (analyzer['errors'] as Map).entries) {
        severities[entry.key.toString()] = entry.value.toString();
      }
    }

    return _ParsedOptions(
      includes: includes,
      mentions: mentions,
      severityOverrides: severities,
      commentedOut: _commentedOutRules(lines),
    );
  }

  static final _entryPattern = RegExp(r'^\s*(?:-\s+)?([a-z0-9_]+)\s*:?');
  static final _commentedRule = RegExp(
    r'^\s*#\s*(?:-\s+)?([a-z][a-z0-9_]{3,})\s*(?::\s*(?:true|false))?\s*$',
  );

  int _lineOf(List<String> lines, String rule) {
    for (var i = 0; i < lines.length; i++) {
      var match = _entryPattern.firstMatch(lines[i]);
      if (match != null && match.group(1) == rule) return i + 1;
    }
    return 0;
  }

  String? _commentFor(List<String> lines, String rule) {
    var index = _lineOf(lines, rule) - 1;
    if (index < 0) return null;
    var line = lines[index];
    var hash = line.indexOf('#');
    if (hash > 0) return line.substring(hash + 1).trim();
    var above = <String>[];
    for (var i = index - 1; i >= 0; i--) {
      var candidate = lines[i].trim();
      if (!candidate.startsWith('#')) break;
      // A commented-out rule is a mention of that rule, not a note on this one.
      if (_commentedRule.hasMatch(lines[i])) break;
      above.insert(0, candidate.replaceFirst(RegExp(r'^#\s?'), ''));
    }
    if (above.isEmpty) return null;
    return above.join(' ').trim();
  }

  Set<String> _commentedOutRules(List<String> lines) => {
    for (var line in lines)
      if (_commentedRule.firstMatch(line) case var match?) match.group(1)!,
  };
}

class _ParsedOptions {
  final List<String> includes;
  final Map<String, LintMention> mentions;
  final Map<String, String> severityOverrides;
  final Set<String> commentedOut;

  _ParsedOptions({
    required this.includes,
    required this.mentions,
    required this.severityOverrides,
    required this.commentedOut,
  });

  static final empty = _ParsedOptions(
    includes: [],
    mentions: {},
    severityOverrides: {},
    commentedOut: {},
  );
}
