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

/// What one analyzer run said each candidate rule would cost today.
class LintPricing {
  /// Candidate rule → number of diagnostics it would add. Zero is the
  /// interesting value: a rule that can be enabled and nothing changes.
  final Map<String, int> counts;

  final DateTime at;
  final Duration elapsed;

  /// Prices are only comparable to the candidate set they were computed for;
  /// this ties a persisted result to it.
  final String candidatesSignature;

  LintPricing({
    required this.counts,
    required this.at,
    required this.elapsed,
    required this.candidatesSignature,
  });

  int get freeWins => counts.values.where((c) => c == 0).length;

  static String signatureOf(Iterable<String> candidates) => sha1
      .convert(utf8.encode((candidates.toList()..sort()).join(',')))
      .toString();

  Map<String, Object?> toJson() => {
    'counts': counts,
    'at': at.toIso8601String(),
    'elapsedMs': elapsed.inMilliseconds,
    'candidatesSignature': candidatesSignature,
  };

  static LintPricing? fromJson(Map<String, Object?> json) {
    try {
      return LintPricing(
        counts: (json['counts']! as Map).cast<String, int>(),
        at: DateTime.parse(json['at']! as String),
        elapsed: Duration(milliseconds: json['elapsedMs']! as int),
        candidatesSignature: json['candidatesSignature']! as String,
      );
    } catch (e) {
      return null;
    }
  }
}

/// Prices every candidate rule in **one** analyzer run.
///
/// `dart analyze` has no flag for an alternate options file, so for the length
/// of the run the repo-root `analysis_options.yaml` is swapped: the original is
/// renamed to [originalName] and a generated file takes its place — a marker
/// header, an `include:` of the renamed original (so every existing setting,
/// including its own includes, still applies) and the candidates, enabled.
/// Renaming rather than merging is the point: no YAML surgery, no duplicate
/// keys, relative includes keep resolving because nothing moved directories.
///
/// The swap is restored in a `finally`. If the process dies anyway, the marker
/// makes the leftover recognizable and [recoverLeftovers] — called by every
/// scan — puts the original back.
class LintPricer {
  static const overlayMarker =
      '# flutterware lint pricing overlay — temporary.\n'
      '# If this file survived a crash, restore the original: '
      'mv analysis_options.fw-pricing-original.yaml analysis_options.yaml';
  static const originalName = 'analysis_options.fw-pricing-original.yaml';

  /// Diagnostic codes the overlay itself provokes, never a rule's price:
  /// enabling every candidate at once trips the incompatible-pair check.
  static const _noise = {'incompatible_lint', 'included_file_warning'};

  final RunProcess runProcess;

  LintPricer({RunProcess? runProcess})
    : runProcess = runProcess ?? _defaultRunProcess;

  /// Restores an overlay a dead pricing run left behind. Returns true when it
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

  Future<LintPricing> price({
    required String repoRoot,
    required String dartExecutable,
    required List<String> candidates,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (candidates.isEmpty) {
      return LintPricing(
        counts: {},
        at: DateTime.now(),
        elapsed: Duration.zero,
        candidatesSignature: LintPricing.signatureOf(candidates),
      );
    }

    var options = File(p.join(repoRoot, 'analysis_options.yaml'));
    var original = File(p.join(repoRoot, originalName));
    if (original.existsSync()) {
      throw StateError(
        'A previous pricing run left $originalName behind. '
        'Rescan to recover it, then price again.',
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
    for (var diagnostic in diagnostics) {
      var code = (diagnostic as Map)['code'];
      if (code is! String || _noise.contains(code)) continue;
      var current = counts[code];
      if (current != null) counts[code] = current + 1;
    }
    return LintPricing(
      counts: counts,
      at: DateTime.now(),
      elapsed: watch.elapsed,
      candidatesSignature: LintPricing.signatureOf(candidates),
    );
  }
}
