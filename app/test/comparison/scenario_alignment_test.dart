import 'package:flutterware_app/src/comparison/scenario_alignment.dart';
import 'package:test/test.dart';

/// Two runs of one scenario, matched up — the piece that decides whether a
/// flow diff reads as one insertion or as everything after it changing.
void main() {
  /// A linear run of [labels], each an authored shot name.
  List<AlignableStep> chain(List<String> labels) => [
    for (var (index, label) in labels.indexed)
      AlignableStep(
        index: index + 1,
        position: '#${index + 1}',
        parent: index == 0 ? null : index,
        name: label,
      ),
  ];

  ScenarioAlignment align(List<AlignableStep> base, List<AlignableStep> head) =>
      ScenarioAlignment.of(base: base, head: head);

  List<String> deltas(ScenarioAlignment alignment, StepDelta kind) => [
    for (var pair in alignment.pairs)
      if (pair.delta == kind) pair.path,
  ];

  test('two identical runs match all the way down', () {
    var alignment = align(
      chain(['Cart', 'Address', 'Pay']),
      chain(['Cart', 'Address', 'Pay']),
    );

    expect(alignment.pairs, hasLength(3));
    expect(alignment.pairs.every((p) => p.delta == StepDelta.matched), isTrue);
    expect(alignment.branches, isEmpty);
  });

  // The whole reason this is an LCS: a zip reports every step after an
  // insertion as changed, which is the report nobody can read.
  test('an inserted step is one insertion, not a shifted flow', () {
    var alignment = align(
      chain(['Cart', 'Pay']),
      chain(['Cart', 'Consent', 'Pay']),
    );

    expect(deltas(alignment, StepDelta.added), ['Consent']);
    expect(deltas(alignment, StepDelta.matched), ['Cart', 'Pay']);
  });

  test('a removed step is one removal', () {
    var alignment = align(
      chain(['Cart', 'Coupon', 'Pay']),
      chain(['Cart', 'Pay']),
    );

    expect(deltas(alignment, StepDelta.removed), ['Coupon']);
  });

  // An LCS pairs equal signatures in order, so nothing special is needed for a
  // flow that taps the same button three times.
  test('repeated steps pair in order', () {
    var alignment = align(
      chain(['Next', 'Next', 'Done']),
      chain(['Next', 'Next', 'Next', 'Done']),
    );

    expect(deltas(alignment, StepDelta.added), ['Next']);
    expect(deltas(alignment, StepDelta.matched), hasLength(3));
  });

  group('a step with no name is known by its verb and target', () {
    AlignableStep did(
      int index, {
      required String verb,
      String? target,
      String? kind,
    }) => AlignableStep(
      index: index,
      position: '#$index',
      parent: index == 1 ? null : index - 1,
      verb: verb,
      target: target,
      targetKind: kind,
    );

    test('the same line is the same step', () {
      var alignment = align(
        [did(1, verb: 'pumpWidget'), did(2, verb: 'tap', target: "key 'pay'")],
        [did(1, verb: 'pumpWidget'), did(2, verb: 'tap', target: "key 'pay'")],
      );

      expect(
        alignment.pairs.every((p) => p.delta == StepDelta.matched),
        isTrue,
      );
    });

    // Rename a key and the signature moves, so the step reads as removed plus
    // added over two identical pictures. Same place, same verb, one on each
    // side is as close to proof as this gets.
    test('a retargeted step is paired rather than mourned', () {
      var alignment = align(
        [did(1, verb: 'pumpWidget'), did(2, verb: 'tap', target: "key 'pay'")],
        [
          did(1, verb: 'pumpWidget'),
          did(2, verb: 'tap', target: "key 'pay_now'"),
        ],
      );

      expect(deltas(alignment, StepDelta.retargeted), hasLength(1));
      expect(deltas(alignment, StepDelta.added), isEmpty);
      expect(deltas(alignment, StepDelta.removed), isEmpty);
    });

    test('a different verb in the same place is not a retarget', () {
      var alignment = align(
        [did(1, verb: 'pumpWidget'), did(2, verb: 'tap', target: 'a')],
        [did(1, verb: 'pumpWidget'), did(2, verb: 'longPress', target: 'a')],
      );

      expect(deltas(alignment, StepDelta.retargeted), isEmpty);
      expect(deltas(alignment, StepDelta.added), hasLength(1));
      expect(deltas(alignment, StepDelta.removed), hasLength(1));
    });
  });

  group('split', () {
    /// A trunk step, then a fork into [branches] of one step each.
    List<AlignableStep> fork(Map<String, String> branches) => [
      AlignableStep(index: 1, position: '#1', name: 'Cart'),
      for (var (index, entry) in branches.entries.indexed)
        AlignableStep(
          index: index + 2,
          position: '$index#1',
          parent: 1,
          branch: entry.key,
          name: entry.value,
        ),
    ];

    test('branches match by label, not by position', () {
      var alignment = align(
        fork({'guest': 'Address', 'signed in': 'Confirm'}),
        // Reordered in the source; the same two branches.
        fork({'signed in': 'Confirm', 'guest': 'Address'}),
      );

      expect(alignment.branches, isEmpty);
      expect(
        alignment.pairs.every((p) => p.delta == StepDelta.matched),
        isTrue,
      );
    });

    // One decision in the source. Listing its steps as N additions describes
    // that decision N times and buries whatever else the run found.
    test('a new branch is one delta, not one per step', () {
      var alignment = align(
        fork({'guest': 'Address'}),
        fork({'guest': 'Address', 'apple pay': 'Sheet'}),
      );

      expect(alignment.branches, hasLength(1));
      expect(alignment.branches.single.label, 'apple pay');
      expect(alignment.branches.single.added, isTrue);
      expect(alignment.branches.single.steps, 1);
      expect(deltas(alignment, StepDelta.added), isEmpty);
    });

    test('a removed branch is one delta too', () {
      var alignment = align(
        fork({'guest': 'Address', 'coupon': 'Code'}),
        fork({'guest': 'Address'}),
      );

      expect(alignment.branches.single.label, 'coupon');
      expect(alignment.branches.single.added, isFalse);
    });

    test('a branch reports how many steps went with it', () {
      var base = [
        AlignableStep(index: 1, position: '#1', name: 'Cart'),
        AlignableStep(
          index: 2,
          position: '0#1',
          parent: 1,
          branch: 'coupon',
          name: 'Code',
        ),
        AlignableStep(index: 3, position: '0#2', parent: 2, name: 'Applied'),
        AlignableStep(index: 4, position: '0#3', parent: 3, name: 'Total'),
      ];

      var alignment = align(base, [base.first]);

      expect(alignment.branches.single.steps, 3);
    });

    test('a step inside a matched branch aligns within it', () {
      var base = [
        AlignableStep(index: 1, position: '#1', name: 'Cart'),
        AlignableStep(
          index: 2,
          position: '0#1',
          parent: 1,
          branch: 'guest',
          name: 'Address',
        ),
        AlignableStep(index: 3, position: '0#2', parent: 2, name: 'Pay'),
      ];
      var head = [
        ...base.take(2),
        AlignableStep(index: 3, position: '0#2', parent: 2, name: 'Consent'),
        AlignableStep(index: 4, position: '0#3', parent: 3, name: 'Pay'),
      ];

      var alignment = align(base, head);

      expect(deltas(alignment, StepDelta.added), ['guest › Consent']);
      expect(alignment.branches, isEmpty);
    });

    test('the path names the branch a step is in', () {
      var alignment = align(
        fork({'guest': 'Address'}),
        fork({'guest': 'Somewhere else'}),
      );

      expect(deltas(alignment, StepDelta.added), ['guest › Somewhere else']);
      expect(deltas(alignment, StepDelta.removed), ['guest › Address']);
    });
  });
}
