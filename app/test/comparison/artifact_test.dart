import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/comparison/artifact.dart';
import 'package:flutterware_app/src/comparison/channels.dart';
import 'package:flutterware_app/src/comparison/runner.dart';
import 'package:flutterware_app/src/comparison/scenario_comparison.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The file both halves land in, and the one a GUI, an agent and a static page
/// all read instead of each computing their own.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_artifact'));
  tearDown(() => root.deleteSync(recursive: true));

  ComparisonResult previews(List<ComparedItem> items, {int rendered = 0}) =>
      ComparisonResult(
        items: items,
        baseSha: 'abc123',
        headRoot: '/work/head',
        elapsed: const Duration(milliseconds: 120),
        rendered: rendered,
      );

  ScenarioResults scenarios(List<ScenarioComparison> items, {int ran = 0}) =>
      ScenarioResults.of(
        items: items,
        ran: ran,
        skipped: 0,
        elapsed: const Duration(milliseconds: 900),
      );

  ScenarioComparison scenario(String id, ComparedState state) =>
      ScenarioComparison(
        scenario: id,
        items: const [],
        branches: const [],
        state: state,
      );

  Map<String, Object?> read(ComparisonArtifact artifact) => jsonDecode(
    artifact.writeTo(p.join(root.path, 'out', 'index.json')).readAsStringSync(),
  ) as Map<String, Object?>;

  test("the base and the head are the comparison's, not a half's", () {
    var json = read(
      ComparisonArtifact(previews: previews([]), scenarios: scenarios([])),
    );

    expect(json['base'], 'abc123');
    expect(json['head'], '/work/head');
    expect(json['previews'], isNot(contains('base')));
  });

  // Two lists under their own names, because `items` at the top of a file
  // holding both halves means previews to whoever wrote it and everything to
  // whoever reads it.
  test('each half keeps its own list', () {
    var json = read(
      ComparisonArtifact(
        previews: previews([
          const ComparedItem(
            id: 'demo/card.dart#card',
            state: ComparedState.changed,
          ),
        ], rendered: 2),
        scenarios: scenarios([
          scenario('test/shop.dart#Checkout', ComparedState.broke),
        ], ran: 1),
      ),
    );

    var half = json['previews']! as Map<String, Object?>;
    expect(half['rendered'], 2);
    expect(
      (half['items']! as List).single,
      containsPair('id', 'demo/card.dart#card'),
    );

    var other = json['scenarios']! as Map<String, Object?>;
    expect(other['ran'], 1);
    expect(
      (other['items']! as List).single,
      containsPair('id', 'test/shop.dart#Checkout'),
    );
  });

  // One preview that broke and one scenario that broke is two broken things.
  // Which half they came from is the second question.
  test('the counts at the top are the whole comparison', () {
    var artifact = ComparisonArtifact(
      previews: previews([
        const ComparedItem(id: 'a', state: ComparedState.broke),
        const ComparedItem(id: 'b', state: ComparedState.same),
      ]),
      scenarios: scenarios([
        scenario('c', ComparedState.broke),
        scenario('d', ComparedState.changed),
      ]),
    );

    expect(artifact.counts[ComparedState.broke], 2);
    expect(read(artifact)['counts'], {'broke': 2, 'changed': 1, 'same': 1});
  });

  test('the elapsed time is both halves', () {
    var json = read(
      ComparisonArtifact(previews: previews([]), scenarios: scenarios([])),
    );

    expect(json['ms'], 1020);
    expect((json['previews']! as Map)['ms'], 120);
    expect((json['scenarios']! as Map)['ms'], 900);
  });

  group('clean', () {
    test('nothing but same and skipped is clean', () {
      expect(
        ComparisonArtifact(
          previews: previews([
            const ComparedItem(id: 'a', state: ComparedState.same),
            const ComparedItem(id: 'b', state: ComparedState.skipped),
          ]),
          scenarios: scenarios([scenario('c', ComparedState.same)]),
        ).clean,
        isTrue,
      );
    });

    test('a scenario alone can make it dirty', () {
      expect(
        ComparisonArtifact(
          previews: previews([
            const ComparedItem(id: 'a', state: ComparedState.same),
          ]),
          scenarios: scenarios([scenario('c', ComparedState.changed)]),
        ).clean,
        isFalse,
      );
    });
  });

  group('the scenario half', () {
    test('ranks worst first, like the previews half', () {
      var results = scenarios([
        scenario('z', ComparedState.same),
        scenario('a', ComparedState.changed),
        scenario('m', ComparedState.broke),
      ]);

      expect(results.items.map((i) => i.scenario), ['m', 'a', 'z']);
    });

    // An empty list is what a project with no scenarios leaves behind, so a
    // reader has to be able to tell that apart from a harness that would not
    // build.
    test('a harness that would not build says so', () {
      var json = ScenarioResults.of(
        items: const [],
        ran: 0,
        skipped: 0,
        elapsed: Duration.zero,
        note: 'Error: no such method',
      ).toJson();

      expect(json['note'], 'Error: no such method');
      expect(json['items'], isEmpty);
    });

    test('a project with no scenarios at all leaves no half', () {
      expect(
        read(ComparisonArtifact(previews: previews([]))),
        isNot(contains('scenarios')),
      );
    });

    // A row that is missing tells a reader nothing; "skipped" tells them the
    // tool looked and found no reason to run it.
    test('a scenario nobody ran is still a row', () {
      var json = const ScenarioComparison.notRun(
        scenario: 'test/shop.dart#Checkout',
        state: ComparedState.skipped,
      ).toJson();

      expect(json['state'], 'skipped');
      expect(json['steps'], isEmpty);
    });
  });
}
