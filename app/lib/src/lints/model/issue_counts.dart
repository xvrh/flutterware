import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Injectable process seam, same shape as the dependencies plugin's.
typedef RunProcess =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

Future<ProcessResult> _defaultRunProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(executable, arguments, workingDirectory: workingDirectory);

/// One place a rule fired — enough to see what the rule is about in this
/// repo's own code, without running anything again.
class LintIssueSample {
  final String file;
  final int line;
  final String message;

  LintIssueSample({
    required this.file,
    required this.line,
    required this.message,
  });

  Map<String, Object?> toJson() => {
    'file': file,
    'line': line,
    'message': message,
  };

  static LintIssueSample fromJson(Map<String, Object?> json) => LintIssueSample(
    file: json['file']! as String,
    line: json['line']! as int,
    message: json['message']! as String,
  );

  @override
  String toString() => '$file:$line — $message';
}

/// What one analyzer run said each candidate rule would report today.
class LintIssueCounts {
  /// Candidate rule → number of diagnostics it would add. Zero is the
  /// interesting value: a rule that can be enabled and nothing changes.
  final Map<String, int> counts;

  /// Up to [LintIssueCounter.samplesPerRule] concrete findings per rule, so
  /// "what is this rule like here" is answerable without another run.
  final Map<String, List<LintIssueSample>> samples;

  final DateTime at;
  final Duration elapsed;

  /// Counts are only comparable to the candidate set they were computed for;
  /// this ties a persisted result to it.
  final String candidatesSignature;

  LintIssueCounts({
    required this.counts,
    required this.samples,
    required this.at,
    required this.elapsed,
    required this.candidatesSignature,
  });

  static String signatureOf(Iterable<String> candidates) => sha1
      .convert(utf8.encode((candidates.toList()..sort()).join(',')))
      .toString();

  Map<String, Object?> toJson() => {
    'counts': counts,
    'samples': {
      for (var entry in samples.entries)
        entry.key: [for (var sample in entry.value) sample.toJson()],
    },
    'at': at.toIso8601String(),
    'elapsedMs': elapsed.inMilliseconds,
    'candidatesSignature': candidatesSignature,
  };

  static LintIssueCounts? fromJson(Map<String, Object?> json) {
    try {
      return LintIssueCounts(
        counts: (json['counts']! as Map).cast<String, int>(),
        samples: {
          for (var entry in (json['samples'] as Map? ?? {}).entries)
            entry.key as String: [
              for (var sample in entry.value as List)
                LintIssueSample.fromJson(
                  (sample as Map).cast<String, Object?>(),
                ),
            ],
        },
        at: DateTime.parse(json['at']! as String),
        elapsed: Duration(milliseconds: json['elapsedMs']! as int),
        candidatesSignature: json['candidatesSignature']! as String,
      );
    } catch (e) {
      return null;
    }
  }
}

/// Counts every candidate rule's issues in **one** analyzer run.
///
/// `dart analyze` has no flag for an alternate options file, so for the length
/// of the run the repo-root `analysis_options.yaml` is swapped: the original is
/// renamed to [originalName] and a generated file takes its place — a marker
/// header, an `include:` of the renamed original (so every existing setting,
/// including its own includes, still applies) and the candidates, enabled.
/// Renaming rather than merging is the point: no YAML surgery, no duplicate
/// keys, relative includes keep resolving because nothing moved directories.
/// A candidate the original disables comes back on for the run, because the
/// overlay's own `linter: rules:` wins over its include — which is what lets
/// dismissed rules be counted too.
///
/// The swap is restored in a `finally`. If the process dies anyway, the marker
/// makes the leftover recognizable and [recoverLeftovers] — called by every
/// scan — puts the original back.
class LintIssueCounter {
  static const overlayMarker =
      '# flutterware lint counting overlay — temporary.\n'
      '# If this file survived a crash, restore the original: '
      'mv analysis_options.fw-original.yaml analysis_options.yaml';
  static const originalName = 'analysis_options.fw-original.yaml';

  static const samplesPerRule = 3;

  /// Diagnostic codes the overlay itself provokes, never a rule's own count:
  /// enabling every candidate at once trips the incompatible-pair check.
  static const _noise = {'incompatible_lint', 'included_file_warning'};

  final RunProcess runProcess;

  LintIssueCounter({RunProcess? runProcess})
    : runProcess = runProcess ?? _defaultRunProcess;

  /// Restores an overlay a dead counting run left behind. Returns true when it
  /// found one.
  static bool recoverLeftovers(String repoRoot) {
    var options = File(p.join(repoRoot, 'analysis_options.yaml'));
    var original = File(p.join(repoRoot, originalName));
    try {
      var overlayInPlace =
          options.existsSync() &&
          options.readAsStringSync().startsWith(overlayMarker);
      if (original.existsSync()) {
        if (overlayInPlace) options.deleteSync();
        if (!options.existsSync()) original.renameSync(options.path);
        return true;
      }
      if (overlayInPlace) {
        // The repo had no options file to begin with.
        options.deleteSync();
        return true;
      }
    } catch (e) {
      // Leave whatever is there for the human; the marker says what to do.
    }
    return false;
  }

  Future<LintIssueCounts> count({
    required String repoRoot,
    required String dartExecutable,
    required List<String> candidates,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (candidates.isEmpty) {
      return LintIssueCounts(
        counts: {},
        samples: {},
        at: DateTime.now(),
        elapsed: Duration.zero,
        candidatesSignature: LintIssueCounts.signatureOf(candidates),
      );
    }

    var options = File(p.join(repoRoot, 'analysis_options.yaml'));
    var original = File(p.join(repoRoot, originalName));
    if (original.existsSync()) {
      throw StateError(
        'A previous counting run left $originalName behind. '
        'Rescan to recover it, then count again.',
      );
    }

    var hadOptions = options.existsSync();
    var overlay = StringBuffer()
      ..writeln(overlayMarker)
      ..writeln();
    if (hadOptions) overlay.writeln('include: $originalName\n');
    overlay.writeln('linter:\n  rules:');
    for (var candidate in candidates) {
      overlay.writeln('    $candidate: true');
    }

    var watch = Stopwatch()..start();
    ProcessResult result;
    try {
      if (hadOptions) options.renameSync(original.path);
      options.writeAsStringSync(overlay.toString());
      result = await runProcess(dartExecutable, [
        'analyze',
        '--format=json',
        '.',
      ], workingDirectory: repoRoot).timeout(timeout);
    } finally {
      try {
        if (options.existsSync() &&
            options.readAsStringSync().startsWith(overlayMarker)) {
          options.deleteSync();
        }
        if (hadOptions && original.existsSync()) {
          original.renameSync(options.path);
        }
      } catch (e) {
        // recoverLeftovers picks this up on the next scan.
      }
    }
    watch.stop();

    // Exit code is not health here: `dart analyze` exits non-zero whenever it
    // has findings, and findings are the product. Parseable JSON is the test.
    var stdout = result.stdout.toString();
    var start = stdout.indexOf('{');
    if (start < 0) {
      throw StateError(
        'dart analyze produced no JSON (exit ${result.exitCode}): '
        '${result.stderr.toString().trim().split('\n').take(4).join(' · ')}',
      );
    }
    List<dynamic> diagnostics;
    try {
      var decoded = jsonDecode(stdout.substring(start)) as Map<String, dynamic>;
      diagnostics = decoded['diagnostics'] as List<dynamic>? ?? [];
    } catch (e) {
      throw StateError('dart analyze JSON did not parse: $e');
    }

    var counts = {for (var candidate in candidates) candidate: 0};
    var samples = <String, List<LintIssueSample>>{};
    for (var diagnostic in diagnostics) {
      var map = diagnostic as Map;
      var code = map['code'];
      if (code is! String || _noise.contains(code)) continue;
      var current = counts[code];
      if (current == null) continue;
      counts[code] = current + 1;
      var collected = samples.putIfAbsent(code, () => []);
      if (collected.length < samplesPerRule) {
        var sample = _sampleOf(map, repoRoot);
        if (sample != null) collected.add(sample);
      }
    }
    return LintIssueCounts(
      counts: counts,
      samples: samples,
      at: DateTime.now(),
      elapsed: watch.elapsed,
      candidatesSignature: LintIssueCounts.signatureOf(candidates),
    );
  }

  LintIssueSample? _sampleOf(Map diagnostic, String repoRoot) {
    try {
      var location = diagnostic['location'] as Map?;
      var file = location?['file'] as String?;
      if (file == null) return null;
      var line =
          ((location?['range'] as Map?)?['start'] as Map?)?['line'] as int? ??
          0;
      return LintIssueSample(
        file: p.isWithin(repoRoot, file)
            ? p.posix.joinAll(p.split(p.relative(file, from: repoRoot)))
            : file,
        line: line,
        message: diagnostic['problemMessage'] as String? ?? '',
      );
    } catch (e) {
      return null;
    }
  }
}
