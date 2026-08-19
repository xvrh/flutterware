import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/lints/model/issue_counts.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_lints_count');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File options() => File(p.join(root.path, 'analysis_options.yaml'));
  File original() => File(p.join(root.path, LintIssueCounter.originalName));

  ProcessResult json(List<Map<String, Object?>> diagnostics) => ProcessResult(
    0,
    3, // dart analyze exits non-zero whenever it has findings.
    jsonEncode({'version': 1, 'diagnostics': diagnostics}),
    '',
  );

  test('swaps the options file for the run and restores it after', () async {
    options().writeAsStringSync('linter:\n  rules:\n    existing: true\n');
    String? overlaySeen;
    String? originalSeen;
    var counter = LintIssueCounter(
      runProcess: (executable, arguments, {workingDirectory}) async {
        overlaySeen = options().readAsStringSync();
        originalSeen = original().readAsStringSync();
        return json([
          {'code': 'rule_a'},
          {'code': 'rule_a'},
          {'code': 'existing'},
          {'code': 'incompatible_lint'},
        ]);
      },
    );

    var counts = await counter.count(
      repoRoot: root.path,
      dartExecutable: 'unused-in-test',
      candidates: ['rule_a', 'rule_b'],
    );

    // During the run: the overlay includes the renamed original and enables
    // the candidates; the original is intact under its temporary name.
    expect(overlaySeen, startsWith(LintIssueCounter.overlayMarker));
    expect(overlaySeen, contains('include: ${LintIssueCounter.originalName}'));
    expect(overlaySeen, contains('rule_a: true'));
    expect(originalSeen, contains('existing: true'));

    // After: the original is back, nothing temporary remains.
    expect(options().readAsStringSync(), contains('existing: true'));
    expect(original().existsSync(), isFalse);

    // Counts cover every candidate — zero is an answer — and only candidates:
    // the baseline's own findings and the overlay's incompatible_lint noise
    // are not counts.
    expect(counts.counts, {'rule_a': 2, 'rule_b': 0});
  });

  test('keeps a few concrete findings per rule, repo-relative', () async {
    options().writeAsStringSync('linter:\n');
    Map<String, Object?> diagnostic(String code, String file, int line) => {
      'code': code,
      'problemMessage': 'What $code found.',
      'location': {
        'file': p.join(root.path, file),
        'range': {
          'start': {'line': line, 'column': 1},
        },
      },
    };
    var counter = LintIssueCounter(
      runProcess: (executable, arguments, {workingDirectory}) async => json([
        for (var line = 1; line <= 5; line++)
          diagnostic('rule_a', 'lib/a.dart', line),
      ]),
    );

    var counts = await counter.count(
      repoRoot: root.path,
      dartExecutable: 'unused-in-test',
      candidates: ['rule_a'],
    );

    expect(counts.counts['rule_a'], 5);
    var samples = counts.samples['rule_a']!;
    expect(samples, hasLength(LintIssueCounter.samplesPerRule));
    expect(samples.first.file, 'lib/a.dart');
    expect(samples.first.line, 1);
    expect(samples.first.message, 'What rule_a found.');

    // Samples survive the round trip through persistence.
    var reread = LintIssueCounts.fromJson(
      (jsonDecode(jsonEncode(counts.toJson())) as Map).cast<String, Object?>(),
    )!;
    expect(reread.samples['rule_a']!.first.file, 'lib/a.dart');
  });

  test(
    'a repo with no options file gets a pure overlay, then none again',
    () async {
      var counter = LintIssueCounter(
        runProcess: (executable, arguments, {workingDirectory}) async {
          expect(options().readAsStringSync(), isNot(contains('include:')));
          return json([]);
        },
      );
      await counter.count(
        repoRoot: root.path,
        dartExecutable: 'unused-in-test',
        candidates: ['rule_a'],
      );
      expect(options().existsSync(), isFalse);
    },
  );

  test('the original is restored even when the run throws', () async {
    options().writeAsStringSync('linter:\n');
    var counter = LintIssueCounter(
      runProcess: (executable, arguments, {workingDirectory}) async =>
          ProcessResult(0, 1, '', 'analyzer exploded'),
    );
    await expectLater(
      counter.count(
        repoRoot: root.path,
        dartExecutable: 'unused-in-test',
        candidates: ['rule_a'],
      ),
      throwsStateError,
    );
    expect(options().readAsStringSync(), 'linter:\n');
    expect(original().existsSync(), isFalse);
  });

  test('recoverLeftovers restores what a dead run left behind', () {
    original().writeAsStringSync('the real one');
    options().writeAsStringSync('${LintIssueCounter.overlayMarker}\nrest');
    expect(LintIssueCounter.recoverLeftovers(root.path), isTrue);
    expect(options().readAsStringSync(), 'the real one');
    expect(original().existsSync(), isFalse);

    // Nothing to do is not a recovery.
    expect(LintIssueCounter.recoverLeftovers(root.path), isFalse);
  });

  test(
    'recoverLeftovers deletes a stranded overlay when there was no original',
    () {
      options().writeAsStringSync('${LintIssueCounter.overlayMarker}\nrest');
      expect(LintIssueCounter.recoverLeftovers(root.path), isTrue);
      expect(options().existsSync(), isFalse);
    },
  );
}
