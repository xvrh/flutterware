import 'package:flutterware_app/src/comparison/artifact.dart';
import 'package:flutterware_app/src/comparison/runner.dart';
import 'package:flutterware_app/src/session/cli.dart';
import 'package:test/test.dart';

/// What `fw compare` says when it did not do what its summary line implies.
///
/// Both halves print a line that reads the same whether the tool concluded or
/// gave up — `0 scenarios, 0 run, 0 skipped`, `90 entries, 90 rendered` — and
/// both facts that separate those cases were recorded in the artifact and
/// shown to nobody. A consumer wiring this into a pull-request check measured
/// each of them and had no way to learn why.
void main() {
  late StringBuffer out;
  late FwCli cli;

  setUp(() {
    out = StringBuffer();
    cli = FwCli(
      openSession: () => throw StateError('not opened'),
      out: out,
      err: StringBuffer(),
    );
  });

  ComparisonResult previews({
    int rendered = 0,
    Map<String, int> because = const {},
  }) => ComparisonResult(
    items: const [],
    baseSha: 'abc123',
    headRoot: '/head',
    elapsed: Duration.zero,
    rendered: rendered,
    because: because,
  );

  group('why the skip rule could not answer', () {
    // The consumer's case: an empty diff, everything rendered, and three
    // minutes spent proving that nothing changed. The number said the skip
    // rule did not earn its keep; only this line says which path the two
    // checkouts disagreed about.
    test('one shared cause is one line, naming the path', () {
      cli.printPreviews(
        previews(rendered: 90, because: {'pubspec.lock differs': 90}),
      );

      expect(
        out.toString(),
        contains('because pubspec.lock differs — 90 entries'),
      );
    });

    test('a single entry is counted in the singular', () {
      cli.printPreviews(
        previews(rendered: 1, because: {'lib/theme.dart differs': 1}),
      );

      expect(out.toString(), contains('— 1 entry'));
    });

    // Folded first, so the cap is reached only by a branch whose entries
    // genuinely moved for different reasons — where the summary would
    // otherwise be as long as the catalog.
    test('a branch with many reasons prints three and counts the rest', () {
      cli.printPreviews(
        previews(
          rendered: 5,
          because: {
            'a differs': 5,
            'b differs': 4,
            'c differs': 3,
            'd differs': 2,
            'e differs': 1,
          },
        ),
      );

      expect(out.toString(), contains('a differs'));
      expect(out.toString(), contains('c differs'));
      expect(out.toString(), isNot(contains('d differs')));
      expect(out.toString(), contains('… and 2 more reasons'));
    });

    test('a half that skipped everything explains nothing', () {
      cli.printPreviews(previews());

      expect(out.toString(), isNot(contains('because')));
    });

    test('the scenario half counts scenarios, not entries', () {
      cli.printScenarios(
        ScenarioResults.of(
          items: const [],
          ran: 16,
          skipped: 0,
          elapsed: Duration.zero,
          because: {'pubspec.lock differs': 16},
        ),
      );

      expect(out.toString(), contains('— 16 scenarios'));
    });
  });

  group('a half that could not run', () {
    // The dangerous pair: a scenario harness that will not build leaves the
    // same empty list as a project with no scenarios, and the same summary
    // line. "The tool never ran" and "nothing changed" must not read alike.
    test('says so, above the summary that reads like a clean verdict', () {
      cli.printScenarios(
        ScenarioResults.of(
          items: const [],
          ran: 0,
          skipped: 0,
          elapsed: Duration.zero,
          note:
              'The scenarios harness does not compile:\n'
              "harness.dart:12:5: Error: Method not found: 'runScenarios'.",
        ),
      );

      var printed = out.toString();
      expect(printed, contains('scenarios: The scenarios harness'));
      // Whole, not the first line: a refusal naming neither the file nor the
      // symbol is one nobody can act on.
      expect(printed, contains("Method not found: 'runScenarios'"));
      expect(
        printed.indexOf('scenarios: '),
        lessThan(printed.indexOf('0 scenarios, 0 run')),
      );
    });

    test('a half with nothing to explain says nothing', () {
      cli.printScenarios(
        ScenarioResults.of(
          items: const [],
          ran: 0,
          skipped: 3,
          elapsed: Duration.zero,
        ),
      );

      expect(out.toString().trim(), '0 scenarios, 0 run, 3 skipped in 0ms');
    });
  });
}
