import 'package:flutterware/scenarios_report.dart';
import 'package:test/test.dart';

ScenarioRunStep _step(String position, {String? digest, String? name}) =>
    ScenarioRunStep(
      index: 1,
      position: position,
      auto: name == null,
      name: name,
      digest: digest,
    );

ScenarioRunResult _run(
  List<ScenarioRunStep> steps, {
  Map<String, String>? axes,
}) => ScenarioRunResult(
  packages: [
    ScenarioRunPackage(
      path: 'packages/app',
      output: 'build/out',
      axes: axes,
      scenarios: [
        ScenarioRunOutcome(
          file: 'test/scenarios/shop_test.dart',
          name: 'Order a cappuccino',
          ok: true,
          steps: steps,
        ),
      ],
    ),
  ],
);

/// Two runs of one suite, compared — the check that a green suite is also a
/// deterministic one.
void main() {
  test('a suite that does not move reports nothing', () {
    var drift = compareScenarioRuns(
      _run([_step('#1', digest: 'aaaa'), _step('#2', digest: 'bbbb')]),
      _run([_step('#1', digest: 'aaaa'), _step('#2', digest: 'bbbb')]),
    );

    expect(drift.isEmpty, isTrue);
    expect(drift.compared, 2);
    expect(drift.summary, isNull);
  });

  test('a step whose pixels moved is named, with its shot name', () {
    var drift = compareScenarioRuns(
      _run([
        _step('#1', digest: 'aaaa'),
        _step('#2', digest: 'bbbb', name: 'Cart'),
      ]),
      _run([
        _step('#1', digest: 'aaaa'),
        _step('#2', digest: 'cccc', name: 'Cart'),
      ]),
    );

    expect(drift.changed.single.label, 'Order a cappuccino · Cart');
    expect(drift.summary, '1 of 2 steps differ');
  });

  test('steps are matched by position, not by index', () {
    // A step inserted at the top shifts every index below it and no position
    // but its own siblings'. Matching by index would report the whole scenario
    // as moved.
    var drift = compareScenarioRuns(
      _run([_step('#1', digest: 'aaaa'), _step('#2', digest: 'bbbb')]),
      _run([
        _step('#1', digest: 'aaaa'),
        _step('#2', digest: 'bbbb'),
        _step('#3', digest: 'cccc'),
      ]),
    );

    expect(drift.changed, isEmpty);
    expect(drift.added.single.position, '#3');
    expect(drift.removed, isEmpty);
    expect(drift.summary, '1 new');
  });

  test('a step that stopped being captured is reported gone', () {
    var drift = compareScenarioRuns(
      _run([_step('#1', digest: 'aaaa'), _step('#2', digest: 'bbbb')]),
      _run([_step('#1', digest: 'aaaa')]),
    );

    expect(drift.removed.single.position, '#2');
    expect(drift.compared, 1);
  });

  test('one point of a matrix is never compared against another', () {
    var drift = compareScenarioRuns(
      _run([_step('#1', digest: 'aaaa')], axes: {'language': 'en'}),
      _run([_step('#1', digest: 'zzzz')], axes: {'language': 'fr'}),
    );

    expect(drift.isEmpty, isTrue);
    expect(drift.compared, 0);
  });

  test('a scenario only one of the runs executed is out of scope', () {
    // One of the two was a selective run — one file, one name, one tag. A
    // scenario the other never executed did not move; it was not looked at.
    var whole = ScenarioRunResult(
      packages: [
        ScenarioRunPackage(
          path: 'packages/app',
          output: 'build/out',
          scenarios: [
            ScenarioRunOutcome(
              file: 'test/scenarios/shop_test.dart',
              name: 'Order a cappuccino',
              ok: true,
              steps: [_step('#1', digest: 'aaaa')],
            ),
            ScenarioRunOutcome(
              file: 'test/scenarios/shop_test.dart',
              name: 'Around the shop',
              ok: true,
              steps: [_step('#1', digest: 'bbbb')],
            ),
          ],
        ),
      ],
    );
    var drift = compareScenarioRuns(whole, _run([_step('#1', digest: 'aaaa')]));

    expect(drift.isEmpty, isTrue);
    expect(drift.compared, 1);
  });

  test('a step with no digest is not compared — a beat, or an old run', () {
    // A notification beat captured no bytes, and a run written before digests
    // existed carries none at all. Neither is drift.
    var drift = compareScenarioRuns(
      _run([_step('#1', digest: 'aaaa'), _step('#2')]),
      _run([_step('#1', digest: 'aaaa'), _step('#2')]),
    );

    expect(drift.isEmpty, isTrue);
    expect(drift.compared, 1);
  });

  test('a run from before digests existed is not a suite that moved', () {
    // Every step of the newer run would otherwise read as added, which is a
    // loud answer to a question nothing could ask.
    var drift = compareScenarioRuns(
      _run([_step('#1'), _step('#2')]),
      _run([_step('#1', digest: 'aaaa'), _step('#2', digest: 'bbbb')]),
    );

    expect(drift.isEmpty, isTrue);
    expect(drift.compared, 0);
  });

  test('survives the wire, counts whole and lists capped', () {
    var drift = compareScenarioRuns(
      _run([for (var i = 0; i < 30; i++) _step('#$i', digest: 'a$i')]),
      _run([for (var i = 0; i < 30; i++) _step('#$i', digest: 'b$i')]),
    );
    var back = ScenarioRunDrift.fromJson(drift.toJson());

    expect(drift.toJson()['changed'], 30);
    expect(back.changed, hasLength(20));
    expect(back.compared, 30);
    expect(back.changed.first.scenario, 'Order a cappuccino');
  });
}
