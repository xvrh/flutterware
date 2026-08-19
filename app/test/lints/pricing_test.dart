import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/lints/model/pricing.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_lints_price');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File options() => File(p.join(root.path, 'analysis_options.yaml'));
  File original() => File(p.join(root.path, LintPricer.originalName));

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
    var pricer = LintPricer(
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

    var pricing = await pricer.price(
      repoRoot: root.path,
      dartExecutable: 'unused-in-test',
      candidates: ['rule_a', 'rule_b'],
    );

    // During the run: the overlay includes the renamed original and enables
    // the candidates; the original is intact under its temporary name.
    expect(overlaySeen, startsWith(LintPricer.overlayMarker));
    expect(overlaySeen, contains('include: ${LintPricer.originalName}'));
    expect(overlaySeen, contains('rule_a: true'));
    expect(originalSeen, contains('existing: true'));

    // After: the original is back, nothing temporary remains.
    expect(options().readAsStringSync(), contains('existing: true'));
    expect(original().existsSync(), isFalse);

    // Counts cover every candidate — zero is an answer — and only candidates:
    // the baseline's own findings and the overlay's incompatible_lint noise
    // are not prices.
    expect(pricing.counts, {'rule_a': 2, 'rule_b': 0});
    expect(pricing.freeWins, 1);
  });

  test(
    'a repo with no options file gets a pure overlay, then none again',
    () async {
      var pricer = LintPricer(
        runProcess: (executable, arguments, {workingDirectory}) async {
          expect(options().readAsStringSync(), isNot(contains('include:')));
          return json([]);
        },
      );
      await pricer.price(
        repoRoot: root.path,
        dartExecutable: 'unused-in-test',
        candidates: ['rule_a'],
      );
      expect(options().existsSync(), isFalse);
    },
  );

  test('the original is restored even when the run throws', () async {
    options().writeAsStringSync('linter:\n');
    var pricer = LintPricer(
      runProcess: (executable, arguments, {workingDirectory}) async =>
          ProcessResult(0, 1, '', 'analyzer exploded'),
    );
    await expectLater(
      pricer.price(
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
    options().writeAsStringSync('${LintPricer.overlayMarker}\nrest');
    expect(LintPricer.recoverLeftovers(root.path), isTrue);
    expect(options().readAsStringSync(), 'the real one');
    expect(original().existsSync(), isFalse);

    // Nothing to do is not a recovery.
    expect(LintPricer.recoverLeftovers(root.path), isFalse);
  });

  test(
    'recoverLeftovers deletes a stranded overlay when there was no original',
    () {
      options().writeAsStringSync('${LintPricer.overlayMarker}\nrest');
      expect(LintPricer.recoverLeftovers(root.path), isTrue);
      expect(options().existsSync(), isFalse);
    },
  );
}
